#!/bin/bash
set -euo pipefail

### ===== 日志函数 =====
log_info() { echo -e "\033[1;34m[i] $1\033[0m"; }
log_success() { echo -e "\033[1;32m[✓] $1\033[0m"; }
log_warning() { echo -e "\033[1;33m[!] $1\033[0m"; }
log_error() { echo -e "\033[1;31m[✗] $1\033[0m"; exit 1; }

### ===== 用户输入配置 =====
read -p "输入TCR镜像完整地址（TCR_IMAGE_FQIN）: " TCR_IMAGE_FQIN
read -p "输入TCR凭证服务级用户名（TCR_USERNAME）: " TCR_USERNAME
read -s -p "输入TCR凭证服务级密码（TCR_PASSWORD）: " TCR_PASSWORD
read -p "输入TCR仓库URL（TCR_REGISTRY_URL）: " TCR_REGISTRY_URL
echo

### ===== 硬编码命名空间配置 =====
K8S_NAMESPACE="petclinic"
log_info "使用指定命名空间: $K8S_NAMESPACE"

### ===== Kubernetes 部署 =====
# 检查集群连接
! kubectl cluster-info &>/dev/null && log_error "kubectl 无法连接到集群"

# ==== 工作负载部署 ====
log_info "开始部署工作负载..."
log_info "创建命名空间 $K8S_NAMESPACE..."
kubectl apply -f manifests/namespace.yaml || log_warning "命名空间创建失败（可能已存在）"

log_info "创建镜像拉取Secret..."
kubectl create secret docker-registry tcr-internal-credentials \
  --docker-server="${TCR_REGISTRY_URL}" \
  --docker-username="${TCR_USERNAME}" \
  --docker-password="${TCR_PASSWORD}" \
  -n "$K8S_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f - || log_error "Secret创建失败"
log_success "镜像拉取Secret配置完成"

log_info "创建Deployment资源..."
# 使用envsubst替换镜像地址变量
export TCR_IMAGE_FQIN
envsubst < manifests/deployment.yaml | kubectl apply -f - || log_error "Deployment创建失败"

log_info "验证工作负载状态..."
if kubectl rollout status deployment/petclinic -n "$K8S_NAMESPACE" --timeout=180s; then
    log_success "工作负载部署完成且运行正常"
else
    log_warning "工作负载启动可能存在问题，请检查Pod状态"
    kubectl get pods -n "$K8S_NAMESPACE" -l app=petclinic
    kubectl describe deployment/petclinic -n "$K8S_NAMESPACE"
fi

# ==== 4层访问配置 ====
log_info "开始配置4层访问服务..."
kubectl apply -f manifests/service-layer4.yaml || log_error "4层服务创建失败"
log_success "4层服务配置完成"

log_info "验证4层服务状态..."
MAX_RETRY=24
LAYER4_IP=""
for ((i=1; i<=MAX_RETRY; i++)); do
    LAYER4_IP=$(kubectl -n $K8S_NAMESPACE get svc petclinic-service-layer4 -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)
    [ -n "$LAYER4_IP" ] && break
    sleep 5
done

if [ -n "$LAYER4_IP" ]; then
    log_success "4层服务已生效，IP: $LAYER4_IP"
    echo "4层访问地址: http://$LAYER4_IP:8080"
else
    log_warning "4层IP获取超时，请检查Service状态"
fi

# ==== 7层访问配置 ====
log_info "开始配置7层访问服务..."
log_info "创建ClusterIP服务..."
kubectl apply -f manifests/service-clusterip.yaml || log_error "ClusterIP服务创建失败"

log_info "创建Ingress资源..."
kubectl apply -f manifests/ingress.yaml || log_error "Ingress创建失败"
log_success "7层Ingress配置完成"

log_info "验证7层服务状态..."
INGRESS_IP=""
for ((i=1; i<=MAX_RETRY; i++)); do
    INGRESS_IP=$(kubectl -n $K8S_NAMESPACE get ingress petclinic-ingress -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)
    [ -n "$INGRESS_IP" ] && break
    sleep 5
done

if [ -n "$INGRESS_IP" ]; then
    log_success "7层服务已生效，IP: $INGRESS_IP"
    echo "7层访问地址: http://$INGRESS_IP"
else
    log_warning "7层IP获取超时，请检查Ingress状态"
fi

log_success "服务部署与暴露配置全部完成!"
unset TCR_PASSWORD
