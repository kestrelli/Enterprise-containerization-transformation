#!/bin/bash
set -euo pipefail

### ===== 日志函数 =====
log_info() { echo -e "\033[1;34m[i] $1\033[0m"; }
log_success() { echo -e "\033[1;32m[✓] $1\033[0m"; }
log_warning() { echo -e "\033[1;33m[!] $1\033[0m"; }
log_error() { echo -e "\033[1;31m[✗] $1\033[0m"; exit 1; }

### ===== 命名空间配置 =====
K8S_NAMESPACE="petclinic"
log_info "使用指定命名空间: $K8S_NAMESPACE"

### ===== 核心配置 =====
KUBECONFIG_FILE="$HOME/.kube/config"
log_info "使用默认kubeconfig文件: $KUBECONFIG_FILE"

### ===== 配置弹性伸缩 =====
export KUBECONFIG="$KUBECONFIG_FILE"
[ ! -f "$KUBECONFIG_FILE" ] && log_error "kubeconfig 文件不存在"
! kubectl cluster-info &>/dev/null && log_error "kubectl 无法连接到集群"

log_info "开始配置弹性伸缩策略..."
log_info "配置HPA自动扩容策略..."
# 替换命名空间变量
export K8S_NAMESPACE
envsubst < manifests/hpa.yaml | kubectl apply -f - || log_error "HPA配置失败"
log_success "HPA配置完成"

log_info "验证HPA状态..."
if kubectl -n $K8S_NAMESPACE get hpa petclinic-hpa; then
    log_success "HPA已成功部署"
else
    log_error "HPA部署失败"
fi

log_info "配置HPC定时伸缩策略..."
# 替换命名空间变量
envsubst < manifests/hpc.yaml | kubectl apply -f - || log_error "HPC配置失败"
log_success "HPC配置完成"

log_info "验证HPC状态..."
if kubectl -n $K8S_NAMESPACE get hpc petclinic-hpc; then
    log_success "HPC已成功部署"
else
    log_error "HPC部署失败"
fi

log_success "弹性伸缩配置全部完成!"
