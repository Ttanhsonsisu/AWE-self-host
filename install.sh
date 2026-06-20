#!/bin/bash
set -e

echo "================================================================="
echo "   🚀 BẮT ĐẦU CÀI ĐẶT NỀN TẢNG AWE WORKFLOW ENGINE 🚀"
echo "================================================================="

# 1. Kiểm tra Docker
if ! command -v docker &> /dev/null; then
    echo "❌ [LỖI] Docker chưa được cài đặt. Vui lòng cài đặt Docker và thử lại."
    exit 1
fi

# Nhận diện lệnh Docker Compose
if docker compose version &> /dev/null; then
    DOCKER_CMD="docker compose"
elif docker-compose version &> /dev/null; then
    DOCKER_CMD="docker-compose"
else
    echo "❌ [LỖI] Docker Compose chưa được cài đặt."
    exit 1
fi

# Định nghĩa hàm xử lý rollback dọn dẹp khi có lỗi xảy ra hoặc bị người dùng ngắt bằng Ctrl+C
rollback_on_failure() {
    local exit_code=$?
    if [ $exit_code -ne 0 ]; then
        echo ""
        echo "❌ [LỖI] Quá trình cài đặt gặp sự cố (Mã lỗi: $exit_code)."
        echo ">> 🔄 Đang tự động rollback hệ thống (docker compose down -v)..."
        if [ -n "$DOCKER_CMD" ]; then
            $DOCKER_CMD down -v --remove-orphans &>/dev/null || true
        fi
        echo ">> 🔄 Đã dọn dẹp xong tài nguyên bị lỗi. Hệ thống đã được khôi phục về trạng thái sạch."
        exit $exit_code
    fi
}
# Thiết lập bẫy lỗi (trap)
trap rollback_on_failure ERR INT TERM

# 2. Sửa lỗi thư mục rabbitmq.conf (do Docker tự tạo sai nếu thiếu file)
if [ -d "rabbitmq.conf" ]; then
    echo ">> ⚠️  Phát hiện 'rabbitmq.conf' là thư mục (do Docker tự tạo). Đang xóa để cấu hình đúng..."
    rm -rf rabbitmq.conf
fi

if [ ! -f "rabbitmq.conf" ]; then
    echo ">> ⚙️  Đang tạo file cấu hình 'rabbitmq.conf' tiêu chuẩn..."
    echo "loopback_users.guest = false" > rabbitmq.conf
fi

# Đảm bảo phân quyền thực thi cho init-dbs.sh
if [ -f "init-dbs.sh" ]; then
    chmod +x init-dbs.sh 2>/dev/null || true
fi

# 3. Khởi tạo và đồng bộ file cấu hình (.env)
if [ ! -f .env ]; then
    echo ">> ⚙️  Không tìm thấy file .env. Đang tự động khởi tạo từ .env.example..."
    if [ ! -f .env.example ]; then
        echo "❌ [LỖI] Không tìm thấy file .env.example! Vui lòng tải lại bản cài đặt."
        exit 1
    fi
    cp .env.example .env
fi

# Hàm thay thế biến trong file .env sử dụng Bash thuần (Tránh lỗi sed trên macOS/Linux và các ký tự đặc biệt)
replace_env() {
    local key=$1
    local val=$2
    local file=".env"
    local temp_file=".env.tmp"
    local found=0
    
    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ "$line" == "$key="* ]]; then
            echo "$key=$val"
            found=1
        else
            echo "$line"
        fi
    done < "$file" > "$temp_file"
    
    if [ $found -eq 0 ]; then
        echo "$key=$val" >> "$temp_file"
    fi
    mv "$temp_file" "$file"
}

# Hàm lấy giá trị hiện tại của một biến trong .env
get_env_val() {
    local key=$1
    if [ -f .env ]; then
        grep "^$key=" .env | cut -d'=' -f2-
    else
        echo ""
    fi
}

# 4. Lựa chọn cấu hình Môi trường Triển khai
echo ""
echo "================================================================="
echo " 🌐 CẤU HÌNH MÔI TRƯỜNG MẠNG & TÊN MIỀN"
echo "================================================================="
echo "Chọn chế độ chạy ứng dụng:"
echo " 1) Localhost Mode (Dành cho chạy thử nghiệm cục bộ trên máy tính cá nhân)"
echo " 2) Domain Mode (Dành cho Production/Server có tên miền & Cloudflare Tunnel)"
read -p "Nhập lựa chọn của bạn (1 hoặc 2, mặc định là 1): " DEPLOY_MODE

DEPLOY_MODE=${DEPLOY_MODE:-1}

if [ "$DEPLOY_MODE" = "2" ]; then
    echo ""
    read -p ">> Nhập tên miền chính của bạn (ví dụ: oneforallshop.com): " USER_DOMAIN
    if [ -z "$USER_DOMAIN" ]; then
        echo "⚠️  Tên miền không được để trống. Sẽ sử dụng mặc định: localhost"
        USER_DOMAIN="localhost"
        DEPLOY_MODE=1
    else
        read -p ">> Nhập Cloudflare Tunnel Token (để trống nếu tự cấu hình Reverse Proxy): " CF_TOKEN
        
        # Nhập cổng chạy frontend trên host
        read -p ">> Nhập cổng ánh xạ Web Frontend trên Host (mặc định: 80): " USER_FE_PORT
        USER_FE_PORT=${USER_FE_PORT:-80}
        replace_env "FRONTEND_PORT" "$USER_FE_PORT"
        
        replace_env "ROOT_DOMAIN" "$USER_DOMAIN"
        replace_env "CLOUDFLARE_TUNNEL_TOKEN" "$CF_TOKEN"
        
        # Cấu hình URL Production
        replace_env "OIDC_AUTHORITY" "https://id.$USER_DOMAIN/realms/awe-auth"
        replace_env "FRONTEND_API_URL" "https://$USER_DOMAIN/api"
        replace_env "FRONTEND_SIGNALR_URL" "https://$USER_DOMAIN/hubs/workflow"
        replace_env "OIDC_REDIRECT_URI" "https://$USER_DOMAIN/"
        replace_env "OIDC_POST_LOGOUT_REDIRECT_URI" "https://$USER_DOMAIN/"
        echo ">> ✅ Đã cấu hình hệ thống chạy với tên miền: $USER_DOMAIN (Cổng host: $USER_FE_PORT)"
    fi
fi

if [ "$DEPLOY_MODE" = "1" ]; then
    replace_env "ROOT_DOMAIN" "localhost"
    replace_env "CLOUDFLARE_TUNNEL_TOKEN" ""
    
    # Nhập cổng chạy frontend
    echo ""
    read -p ">> Nhập cổng cho Web Frontend (mặc định: 80, chọn 3000 hoặc cổng khác nếu cổng 80 bị trùng): " USER_FE_PORT
    USER_FE_PORT=${USER_FE_PORT:-80}
    replace_env "FRONTEND_PORT" "$USER_FE_PORT"
    
    # Cấu hình URL Localhost
    if [ "$USER_FE_PORT" = "80" ]; then
        replace_env "OIDC_REDIRECT_URI" "http://localhost/"
        replace_env "OIDC_POST_LOGOUT_REDIRECT_URI" "http://localhost/"
    else
        replace_env "OIDC_REDIRECT_URI" "http://localhost:$USER_FE_PORT/"
        replace_env "OIDC_POST_LOGOUT_REDIRECT_URI" "http://localhost:$USER_FE_PORT/"
    fi
    
    replace_env "FRONTEND_API_URL" "/api"
    replace_env "FRONTEND_SIGNALR_URL" "/hubs/workflow"
    echo ">> ✅ Đã cấu hình hệ thống chạy với Localhost trên cổng: $USER_FE_PORT"
fi

# Đồng bộ hóa OIDC_WEB_ORIGIN không có dấu gạch chéo cuối cho Keycloak CORS
REDIRECT_URI_VAL=$(get_env_val "OIDC_REDIRECT_URI")
WEB_ORIGIN_VAL="${REDIRECT_URI_VAL%/}"
replace_env "OIDC_WEB_ORIGIN" "$WEB_ORIGIN_VAL"


# 5. Khởi tạo mật khẩu bảo mật ngẫu nhiên nếu còn ở trạng thái mặc định
echo ""
echo ">> 🔐 Đang kiểm tra và vá bảo mật các mật khẩu mặc định..."

# Hàm sinh mật khẩu ngẫu nhiên (24 ký tự chữ và số)
gen_pass() {
    tr -dc 'A-Za-z0-9' </dev/urandom | head -c 24
}

# Hàm sinh Token/Secret ngẫu nhiên (32 ký tự chữ và số)
gen_token() {
    tr -dc 'A-Za-z0-9' </dev/urandom | head -c 32
}

MQ_PASS=$(get_env_val "RABBITMQ_DEFAULT_PASS")
if [ -z "$MQ_PASS" ] || [ "$MQ_PASS" = "change_me" ]; then
    MQ_PASS=$(gen_pass)
fi

patch_secret() {
    local key=$1
    local type=$2
    local current_val=$(get_env_val "$key")
    
    if [ -z "$current_val" ] || [ "$current_val" = "change_me" ] || [ "$current_val" = "YourStrongRedisPasswordHere" ] || [ "$current_val" = "admin" ]; then
        local new_val=""
        if [ "$type" = "pass" ]; then
            new_val=$(gen_pass)
        elif [ "$type" = "token" ]; then
            new_val=$(gen_token)
        elif [ "$type" = "mq" ]; then
            new_val="$MQ_PASS"
        fi
        replace_env "$key" "$new_val"
        echo "   [Vá bảo mật] -> Đã tự động tạo mới cho biến: $key"
    fi
}

patch_secret "POSTGRES_PASSWORD" "pass"
patch_secret "REDIS_PASSWORD" "pass"
patch_secret "RABBITMQ_DEFAULT_PASS" "mq"
patch_secret "RABBITMQ_PASSWORD" "mq"
patch_secret "MINIO_ROOT_PASSWORD" "pass"
patch_secret "KEYCLOAK_ADMIN_PASSWORD" "pass"
patch_secret "OIDC_CLIENT_SECRET" "token"
patch_secret "DASHBOARD_OTLP_TOKEN" "token"

echo ">> ✅ Kiểm tra bảo mật hoàn tất!"

# 6. Kéo Image và Khởi chạy
echo ""
echo ">> 📥 Đang tải các Docker Image mới nhất từ kho lưu trữ..."
$DOCKER_CMD pull

echo ""
echo ">> 🚀 Đang khởi động toàn bộ hệ thống AWE..."
$DOCKER_CMD up -d

# 7. Vòng lặp kiểm tra sức khoẻ các dịch vụ container
echo ""
echo ">> ⏳ Đang đợi các dịch vụ cốt lõi khởi động hoàn tất..."

CONTAINERS=("awe-postgres" "awe-rabbitmq" "awe-keycloak" "awe-api-gateway" "awe-frontend")

check_healthy() {
    local container=$1
    local status=$(docker inspect --format='{{.State.Status}}' "$container" 2>/dev/null || echo "not_found")
    if [ "$status" != "running" ]; then
        return 1
    fi
    local health=$(docker inspect --format='{{if .State.Health}}{{.State.Health.Status}}{{else}}healthy{{end}}' "$container" 2>/dev/null || echo "healthy")
    if [ "$health" = "healthy" ]; then
        return 0
    else
        return 1
    fi
}

MAX_RETRIES=20
RETRY_COUNT=0
ALL_HEALTHY=0

while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    ALL_HEALTHY=1
    for c in "${CONTAINERS[@]}"; do
        if ! check_healthy "$c"; then
            ALL_HEALTHY=0
            break
        fi
    done
    
    if [ $ALL_HEALTHY -eq 1 ]; then
        break
    fi
    
    echo -n "."
    sleep 3
    RETRY_COUNT=$((RETRY_COUNT+1))
done

echo ""

if [ $ALL_HEALTHY -eq 1 ]; then
    echo ">> ✅ Tất cả các dịch vụ đã hoạt động và ở trạng thái khỏe mạnh!"
else
    echo "❌ [LỖI] Khởi động hệ thống thất bại. Dịch vụ không thể sẵn sàng trong thời gian chờ."
    exit 1
fi

# Lấy các cổng và tên miền để hiển thị thông tin chính xác
HOST_DOMAIN=$(get_env_val "ROOT_DOMAIN")
PORT_FE=$(get_env_val "FRONTEND_PORT")
PORT_FE=${PORT_FE:-80}
PORT_KEYCLOAK=$(get_env_val "KEYCLOAK_PORT")
PORT_KEYCLOAK=${PORT_KEYCLOAK:-8081}
PORT_DASHBOARD=$(get_env_val "DASHBOARD_UI_PORT")
PORT_DASHBOARD=${PORT_DASHBOARD:-19888}
PORT_MQ=$(get_env_val "RABBITMQ_MANAGEMENT_PORT")
PORT_MQ=${PORT_MQ:-15673}
PORT_MINIO=$(get_env_val "MINIO_MANAGEMENT_PORT")
PORT_MINIO=${PORT_MINIO:-9001}

# 8. Hiển thị thông tin kết nối
echo ""
echo "================================================================="
echo " 🎉 CÀI ĐẶT THÀNH CÔNG! HỆ THỐNG AWE ĐANG CHẠY."
echo "================================================================="
if [ "$HOST_DOMAIN" = "localhost" ]; then
    if [ "$PORT_FE" = "80" ]; then
        echo " 🌐 Web Frontend         : http://localhost"
    else
        echo " 🌐 Web Frontend         : http://localhost:$PORT_FE"
    fi
    echo " 🔑 Keycloak Admin       : http://localhost:$PORT_KEYCLOAK"
    echo " 📊 Aspire Dashboard     : http://localhost:$PORT_DASHBOARD"
    echo " 🐰 RabbitMQ Management  : http://localhost:$PORT_MQ"
    echo " 🪣 MinIO Console        : http://localhost:$PORT_MINIO"
else
    if [ "$PORT_FE" = "80" ]; then
        echo " 🌐 Web Frontend         : https://$HOST_DOMAIN"
    else
        echo " 🌐 Web Frontend         : https://$HOST_DOMAIN (Cổng host: $PORT_FE)"
    fi
    echo " 🔑 Keycloak Admin       : https://id.$HOST_DOMAIN"
    echo " 📊 Aspire Dashboard     : http://localhost:$PORT_DASHBOARD (SSH Tunnel/Port Forwarding)"
    echo " 🐰 RabbitMQ Management  : http://localhost:$PORT_MQ (SSH Tunnel/Port Forwarding)"
    echo " 🪣 MinIO Console        : http://localhost:$PORT_MINIO (SSH Tunnel/Port Forwarding)"
fi
echo ""
echo " 📝 Ghi chú quan trọng: "
echo " - Toàn bộ tài khoản (Admin SSO, Database, OTLP Token) đã được"
echo "   sinh ngẫu nhiên và bảo mật tại file '.env'."
echo " - Vui lòng mở file '.env' để lấy thông tin kết nối và mật khẩu."
echo " - Xem log hệ thống  : $DOCKER_CMD logs -f"
echo " - Dừng hệ thống     : $DOCKER_CMD down"
echo "================================================================="