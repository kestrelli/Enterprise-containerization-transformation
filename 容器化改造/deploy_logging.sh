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
# 使用默认的kubeconfig路径
KUBECONFIG_FILE="$HOME/.kube/config"
log_info "使用默认kubeconfig文件: $KUBECONFIG_FILE"

### ===== 配置日志采集 =====
export KUBECONFIG="$KUBECONFIG_FILE"
[ ! -f "$KUBECONFIG_FILE" ] && log_error "kubeconfig 文件不存在"
! kubectl cluster-info &>/dev/null && log_error "kubectl 无法连接到集群"

log_info "开始配置日志采集系统..."
log_info "安装日志采集CRD..."
cat <<EOF | kubectl apply -f - >/dev/null
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata:
  name: logconfigs.cls.cloud.tencent.com
spec:
  group: cls.cloud.tencent.com
  names:
    kind: LogConfig
    listKind: LogConfigList
    plural: logconfigs
    singular: logconfig
  scope: Cluster
  versions:
  - name: v1
    schema:
      openAPIV3Schema:
        type: object
        properties:
          spec:
            type: object
            properties:
              clsDetail:
                type: object
                properties:
                  topicId: 
                    type: string
                  logsetName:
                    type: string
                  topicName:
                    type: string
                  logType:
                    type: string
                    enum: [minimalist_log, fullregex_log]
              inputDetail:
                type: object
                properties:
                  type:
                    type: string
                    enum: [container_stdout, container_file]
                  containerStdout:
                    type: object
                    properties:
                      namespace:
                        type: string
                      workload:
                        type: array
                        items:
                          type: object
                          properties:
                            kind: 
                              type: string
                            name: 
                              type: string
                            namespace: 
                              type: string
                  containerFile:
                    type: object
                    properties:
                      namespace:
                        type: string
                      container:
                        type: string
                      logPath: 
                        type: string
                      filePattern: 
                        type: string
                      workload:
                        type: array
                        items:
                          type: object
                          properties:
                            kind: 
                              type: string
                            name: 
                              type: string
                            namespace: 
                              type: string
                required: [type]
        required: [spec]
    served: true
    storage: true
EOF
log_success "日志采集CRD安装完成"

log_info "等待CRD注册完成..."
for i in {1..10}; do
  kubectl get crd logconfigs.cls.cloud.tencent.com >/dev/null 2>&1 && break
  sleep 3
done
log_success "CRD注册验证完成"

log_info "配置标准输出日志采集..."
kubectl apply -f - >/dev/null <<EOF
apiVersion: cls.cloud.tencent.com/v1
kind: LogConfig
metadata:
  name: petclinic-log-stdout
spec:
  inputDetail:
    type: container_stdout
    containerStdout:
      namespace: ${K8S_NAMESPACE}
      workload:
        - kind: Deployment
          name: petclinic
          namespace: ${K8S_NAMESPACE}
  clsDetail:
    logsetName: "TC-log"
    topicName: "petclinic-stdout-topic"
    logType: minimalist_log
EOF
log_success "标准输出日志规则配置完成"

log_info "配置容器文件日志采集..."
kubectl apply -f - >/dev/null <<EOF
apiVersion: cls.cloud.tencent.com/v1
kind: LogConfig
metadata:
  name: petclinic-log-files
spec:
  inputDetail:
    type: container_file
    containerFile:
      namespace: ${K8S_NAMESPACE}
      container: '*'
      logPath: /var/log
      filePattern: '*.log'
      workload:
        - kind: Deployment
          name: petclinic
          namespace: ${K8S_NAMESPACE}
  clsDetail:
    logsetName: "TC-log"
    topicName: "petclinic-file-topic"
    logType: fullregex_log
EOF
log_success "文件日志规则配置完成"

log_info "验证日志规则状态..."
if kubectl get logconfigs.cls.cloud.tencent.com -A; then
    log_success "日志采集配置已生效"
else
    log_warning "日志规则状态异常，请检查"
fi

log_success "日志采集配置全部完成!"