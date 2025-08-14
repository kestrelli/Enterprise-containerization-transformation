#!/bin/bash
set -euo pipefail

### ===== 日志函数 =====
log_info() { echo -e "\033[1;34m[i] $1\033[0m"; }
log_success() { echo -e "\033[1;32m[✓] $1\033[0m"; }
log_warning() { echo -e "\033[1;33m[!] $1\033[0m"; }
log_error() { echo -e "\033[1;31m[✗] $1\033[0m"; exit 1; }

### ===== 用户输入配置 =====
read -p "输入TCR仓库URL: " TCR_REGISTRY_URL
read -p "输入TCR凭证服务级用户名: " TCR_USERNAME
read -s -p "输入TCR凭证服务级密码: " TCR_PASSWORD
echo
read -p "输入TCR命名空间（默认: default）: " TCR_NAMESPACE
TCR_NAMESPACE=${TCR_NAMESPACE:-"default"}  
read -p "输入镜像版本标签（默认: v3.5.0）: " IMAGE_TAG
IMAGE_TAG=${IMAGE_TAG:-"v3.5.0"}

# Java应用特有配置
export TCR_REGISTRY_URL  # 添加导出语句
export APP_DIR="/opt/spring-petclinic"
export TCR_IMAGE_FQIN="${TCR_REGISTRY_URL}/${TCR_NAMESPACE}/petclinic:${IMAGE_TAG}"
export TCR_NAMESPACE
export IMAGE_TAG
log_info "TCR镜像全限定名: $TCR_IMAGE_FQIN"

### ===== 构建业务镜像 =====
log_info "=== 构建Java业务镜像 ==="
./java-image-builder.sh || log_error "镜像构建失败"

# 检查镜像文件
[ ! -f /tmp/image_name.txt ] && log_error "镜像构建结果丢失"
BUILT_IMAGE=$(cat /tmp/image_name.txt)
log_success "镜像构建完成: $BUILT_IMAGE"

### ===== 验证镜像 =====
log_info "启动测试容器验证镜像..."
TEST_CONTAINER_NAME="test-container-$(date +%s)"
docker run -d --name "$TEST_CONTAINER_NAME" -p 8080:8080 "$BUILT_IMAGE" || {
    docker logs "$TEST_CONTAINER_NAME" || true
    log_error "容器启动失败"
}

log_info "等待Java应用启动..."
TIMEOUT=120
START_TIME=$(date +%s)
while true; do
    if docker logs "$TEST_CONTAINER_NAME" 2>&1 | grep -q "Started PetClinicApplication"; then
        log_success "Java应用启动成功"
        break
    fi
    
    if ! docker ps | grep -q "$TEST_CONTAINER_NAME"; then
        log_error "容器已停止运行"
        docker logs "$TEST_CONTAINER_NAME"
        exit 1
    fi
    
    ELAPSED=$(( $(date +%s) - START_TIME ))
    if [ $ELAPSED -ge $TIMEOUT ]; then
        log_error "应用启动超时"
        docker logs "$TEST_CONTAINER_NAME" | tail -n 50
        docker rm -f "$TEST_CONTAINER_NAME" >/dev/null 2>&1
        exit 1
    fi
    
    sleep 5
done

log_info "检查健康状态..."
HEALTH_STATUS=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/actuator/health || true)
if [ "$HEALTH_STATUS" != "200" ]; then
    log_error "Java应用健康检查失败 (状态码: $HEALTH_STATUS)"
    docker logs "$TEST_CONTAINER_NAME"
    docker rm -f "$TEST_CONTAINER_NAME" >/dev/null 2>&1
    exit 1
fi

log_success "Java业务镜像验证成功"
docker rm -f "$TEST_CONTAINER_NAME" >/dev/null 2>&1 || true

### ===== 推送镜像 =====
log_info "登录TCR仓库..."
echo "$TCR_PASSWORD" | docker login "$TCR_REGISTRY_URL" -u "$TCR_USERNAME" --password-stdin

log_info "推送镜像到TCR: $BUILT_IMAGE"
docker push "$BUILT_IMAGE"

log_success "镜像构建和推送完成!"
echo "==========================="
echo "TCR镜像地址: $BUILT_IMAGE"
echo "TCR仓库URL: $TCR_REGISTRY_URL"
echo "TCR命名空间: $TCR_NAMESPACE"
echo "镜像版本标签: $IMAGE_TAG"
echo "==========================="

### ===== 安全清理 =====
docker logout "$TCR_REGISTRY_URL" >/dev/null 2>&1 || true
unset TCR_PASSWORD
rm -f /tmp/image_name.txt
