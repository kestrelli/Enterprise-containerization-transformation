
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


### ===== 使用默认的kubeconfig路径 =====
KUBECONFIG_FILE="$HOME/.kube/config"
log_info "使用默认kubeconfig文件: $KUBECONFIG_FILE"

### ===== 配置弹性伸缩 =====
export KUBECONFIG="$KUBECONFIG_FILE"
[ ! -f "$KUBECONFIG_FILE" ] && log_error "kubeconfig 文件不存在"
! kubectl cluster-info &>/dev/null && log_error "kubectl 无法连接到集群"

log_info "开始配置弹性伸缩策略..."
log_info "配置HPA自动扩容策略..."
cat <<EOF | kubectl apply -f -
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: petclinic-hpa
  namespace: $K8S_NAMESPACE
spec:
  behavior:
    scaleDown:
      stabilizationWindowSeconds: 300
      policies:
      - type: Percent
        value: 10
        periodSeconds: 60
    scaleUp:
      stabilizationWindowSeconds: 60
      policies:
      - type: Percent
        value: 100
        periodSeconds: 60
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: petclinic
  minReplicas: 3
  maxReplicas: 20
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 65
EOF
log_success "HPA配置完成"

log_info "验证HPA状态..."
if kubectl -n $K8S_NAMESPACE get hpa petclinic-hpa; then
    log_success "HPA已成功部署"
else
    log_error "HPA部署失败"
fi

log_info "配置HPC定时伸缩策略..."
cat <<EOF | kubectl apply -f -
apiVersion: autoscaling.cloud.tencent.com/v1
kind: HorizontalPodCronscaler 
metadata:
  name: petclinic-hpc
  namespace: $K8S_NAMESPACE
spec:
  scaleTarget:
    apiVersion: apps/v1
    kind: Deployment
    name: petclinic
    namespace: $K8S_NAMESPACE
  crons:
  - name: morning-scale-up
    schedule: "2 8 * * 1-5"
    targetSize: 10
  - name: evening-scale-down
    schedule: "2 18 * * 1-5"
    targetSize: 3
  - name: weekend-scale-down
    schedule: "30 23 * * 5"
    targetSize: 2
EOF
log_success "HPC配置完成"

log_info "验证HPC状态..."
if kubectl -n $K8S_NAMESPACE get hpc petclinic-hpc; then
    log_success "HPC已成功部署"
else
    log_error "HPC部署失败"
fi

log_success "弹性伸缩配置全部完成!"