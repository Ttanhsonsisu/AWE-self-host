#!/bin/bash
set -e

echo "================================================================="
echo "   🗑️ BẮT ĐẦU GỠ CÀI ĐẶT NỀN TẢNG AWE WORKFLOW ENGINE 🗑️"
echo "================================================================="

# 1. Kiểm tra Docker
if ! command -v docker &> /dev/null; then
    echo "❌ [LỖI] Docker chưa được cài đặt. Không thể thực hiện gỡ bỏ."
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

# 2. Xác nhận từ người dùng
echo "⚠️  CẢNH BÁO: Hành động này sẽ dừng toàn bộ các container, xóa mạng lưới,"
echo "   và xóa toàn bộ dữ liệu lưu trữ (Volumes) của hệ thống AWE."
read -p ">> Bạn có chắc chắn muốn gỡ cài đặt? (y/N): " CONFIRM
CONFIRM=${CONFIRM:-n}

if [[ "$CONFIRM" =~ ^[Yy]$ ]]; then
    echo ""
    echo ">> 🛑 Đang dừng và xóa toàn bộ container, volume, network của AWE..."
    $DOCKER_CMD down -v --remove-orphans
    
    # Xóa file cấu hình rabbitmq.conf nếu có
    if [ -f "rabbitmq.conf" ]; then
        echo ">> 🗑️  Đang xóa file cấu hình rabbitmq.conf..."
        rm -f rabbitmq.conf
    fi
    
    # Hỏi người dùng có muốn xóa file .env không
    echo ""
    read -p ">> Bạn có muốn xóa cả file cấu hình bí mật '.env' chứa mật khẩu không? (y/N): " REMOVE_ENV
    REMOVE_ENV=${REMOVE_ENV:-n}
    if [[ "$REMOVE_ENV" =~ ^[Yy]$ ]]; then
        if [ -f ".env" ]; then
            echo ">> 🗑️  Đang xóa file .env..."
            rm -f .env
        fi
    else
        echo ">> ⏭️  Giữ lại file .env làm bản sao lưu mật khẩu."
    fi

    echo ""
    echo "================================================================="
    echo " 🎉 GỠ CÀI ĐẶT THÀNH CÔNG!"
    echo " Hệ thống AWE đã được dọn dẹp sạch sẽ khỏi máy tính của bạn."
    echo "================================================================="
else
    echo ">> ⏭️  Hủy bỏ lệnh gỡ cài đặt. Không có thay đổi nào được thực hiện."
fi
