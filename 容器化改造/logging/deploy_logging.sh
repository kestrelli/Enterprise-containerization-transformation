#!/bin/bash
set -euo pipefail

# 获取脚本所在目录作为工作目录
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR" || exit 1

### ===== 日志函数 =====
log_info() { echo -e "\033[1;34m[i] $1\033[0m"; }
log_success() { echo -e "\033[1;32m[✓] $1\033[0m"; }
log_warning() { echo -e "\033[1;33m[!] $1\033[0m"; }
log_error() { echo -e "\033[1;31m[✗] $1\033[0m"; exit 1; }

### ===== 命名空间配置 =====
K8S_NAMESPACE="petclinic"
log_info "使用指定命名空间: $K8S_NAMESPACE"

### ===== 配置日志采集 =====
# 检查集群连接
! kubectl cluster-info &>/dev/null && log_error "kubectl 无法连接到集群"

log_info "开始配置日志采集系统..."
log_info "安装日志采集CRD..."
kubectl apply -f manifests/logconfig-crd.yaml >/dev/null || log_error "CRD安装失败"
log_success "日志采集CRD安装完成"

log_info "等待CRD注册完成..."
for i in {1..10}; do
  kubectl get crd logconfigs.cls.cloud.tencent.com >/dev/null 2>&1 && break
  sleep 3
done
log_success "CRD注册验证完成"

log_info "配置标准输出日志采集..."
# 替换命名空间变量
export K8S_NAMESPACE
envsubst < manifests/logconfig-stdout.yaml | kubectl apply -f - >/dev/null || log_error "标准输出日志配置失败"
log_success "标准输出日志规则配置完成"

log_info "配置容器文件日志采集..."
# 替换命名空间变量
envsubst < manifests/logconfig-files.yaml | kubectl apply -f - >/dev/null || log_error "文件日志配置失败"
log_success "文件日志规则配置完成"

log_info "验证日志规则状态..."
if kubectl get logconfigs.cls.cloud.tencent.com -A; then
    log_success "日志采集配置已生效"
else
    log_warning "日志规则状态异常，请检查"
fi

log_success "日志采集配置全部完成!"
