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

# 2. Khởi tạo cấu hình bảo mật (.env)
if [ ! -f .env ]; then
    echo ">> ⚙️  Không tìm thấy file .env. Đang tự động khởi tạo từ .env.example..."
    
    if [ ! -f .env.example ]; then
        echo "❌ [LỖI] Không tìm thấy file .env.example! Vui lòng tải lại bản cài đặt."
        exit 1
    fi
    
    cp .env.example .env

    # Hàm sinh mật khẩu ngẫu nhiên (24 ký tự chữ và số)
    gen_pass() {
        tr -dc 'A-Za-z0-9' </dev/urandom | head -c 24
    }
    
    # Hàm sinh Token/Secret ngẫu nhiên (32 ký tự chữ và số)
    gen_token() {
        tr -dc 'A-Za-z0-9' </dev/urandom | head -c 32
    }

    echo ">> 🔐 Đang tạo mật khẩu bảo mật ngẫu nhiên..."

    # Hàm thay thế biến trong file .env (Tương thích cả Linux và macOS)
    replace_env() {
        local key=$1
        local val=$2
        if [[ "$OSTYPE" == "darwin"* ]]; then
            sed -i '' "s|^$key=.*|$key=$val|" .env
        else
            sed -i "s|^$key=.*|$key=$val|" .env
        fi
    }

    # Sinh mật khẩu chung cho RabbitMQ (Bắt buộc 2 biến phải giống nhau)
    MQ_PASS=$(gen_pass)

    replace_env "POSTGRES_PASSWORD" "$(gen_pass)"
    replace_env "REDIS_PASSWORD" "$(gen_pass)"
    replace_env "RABBITMQ_DEFAULT_PASS" "$MQ_PASS"
    replace_env "RABBITMQ_PASSWORD" "$MQ_PASS"
    replace_env "MINIO_ROOT_PASSWORD" "$(gen_pass)"
    replace_env "KEYCLOAK_ADMIN_PASSWORD" "$(gen_pass)"
    replace_env "OIDC_CLIENT_SECRET" "$(gen_token)"
    replace_env "DASHBOARD_OTLP_TOKEN" "$(gen_token)"

    echo ">> ✅ Đã tạo file .env thành công với độ bảo mật cao nhất!"
else
    echo ">> ⏭️  File .env đã tồn tại, bỏ qua bước khởi tạo mật khẩu."
fi

# 3. Kéo Image và Khởi chạy
echo ">> 📥 Đang tải các Docker Image mới nhất từ kho lưu trữ..."
$DOCKER_CMD pull

echo ">> 🚀 Đang khởi động hệ thống AWE..."
$DOCKER_CMD up -d

# 4. Hiển thị thông tin kết nối
echo ""
echo "================================================================="
echo " 🎉 CÀI ĐẶT THÀNH CÔNG! HỆ THỐNG ĐANG CHẠY NGẦM."
echo "================================================================="
echo " 🌐 Web Frontend         : http://localhost"
echo " 🔑 Keycloak Admin       : http://localhost:8081"
echo " 📊 Aspire Dashboard     : http://localhost:19888"
echo " 🐰 RabbitMQ Management  : http://localhost:15673"
echo " 🪣 MinIO Console        : http://localhost:9001"
echo ""
echo " 📝 Ghi chú quan trọng: "
echo " - Toàn bộ tài khoản (Admin SSO, Database, OTLP Token) đã được"
echo "   sinh ngẫu nhiên và lưu tại file '.env'."
echo " - Vui lòng mở file '.env' để lấy mật khẩu đăng nhập."
echo " - Xem log hệ thống  : $DOCKER_CMD logs -f"
echo " - Dừng hệ thống     : $DOCKER_CMD down"
echo "================================================================="