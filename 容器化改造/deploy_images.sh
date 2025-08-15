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
read -p "输入镜像版本标签（默认: latest）: " IMAGE_TAG
IMAGE_TAG=${IMAGE_TAG:-"latest"}

### ===== 核心配置 =====
export TCR_IMAGE_FQIN="${TCR_REGISTRY_URL}/${TCR_NAMESPACE}/petclinic:${IMAGE_TAG}"
log_info "TCR镜像全限定名: $TCR_IMAGE_FQIN"

### ===== 构建镜像 =====
log_info "构建Docker镜像..."
docker build --network=host -t "${TCR_IMAGE_FQIN}" . || log_error "镜像构建失败"
log_success "镜像构建完成: $TCR_IMAGE_FQIN"

### ===== 推送镜像 =====
log_info "登录TCR仓库..."
echo "$TCR_PASSWORD" | docker login "$TCR_REGISTRY_URL" -u "$TCR_USERNAME" --password-stdin

log_info "推送镜像到TCR: $TCR_IMAGE_FQIN"
docker push "$TCR_IMAGE_FQIN"

log_success "镜像构建和推送完成!"
echo "==========================="
echo "TCR镜像地址: $TCR_IMAGE_FQIN"
echo "TCR仓库URL: $TCR_REGISTRY_URL"
echo "TCR命名空间: $TCR_NAMESPACE"
echo "镜像版本标签: $IMAGE_TAG"
echo "==========================="

### ===== 安全清理 =====
docker logout "$TCR_REGISTRY_URL" >/dev/null 2>&1 || true
unset TCR_PASSWORD
