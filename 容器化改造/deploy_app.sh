#!/bin/bash
set -euo pipefail

### ===== 日志函数 =====
log_info() { echo -e "\033[1;34m[i] $1\033[0m"; }
log_success() { echo -e "\033[1;32m[✓] $1\033[0m"; }
log_warning() { echo -e "\033[1;33m[!] $1\033[0m"; }
log_error() { echo -e "\033[1;31m[✗] $1\033[0m"; exit 1; }

### ===== 核心配置 =====
APP_DIR="/opt/spring-petclinic"
TCR_DOMAIN="tcr-kestrelli-9gbq7wqm.tencentcloudcr.com"
TCR_NAMESPACE="default"
TCR_USERNAME="tcr\$kestrelli"
IMAGE_TAG="v3.5.0"
K8S_NAMESPACE="petclinic"
BUILD_LOG="/tmp/petclinic-build.log"
KUBECONFIG_FILE="/kestrelli/kubeconfig.yaml"
CLUSTER_NAME="tke-kestrelli-9gbq7wqm"
CLUSTER_ID="cls-dme9f9x4"
REGION="ap-nanjing"

# 安全建议：从环境变量获取密码
read -s -p "请输入TCR密码: " TCR_PASSWORD
echo
### ===== 网络修复配置 =====
# 使用内网IP地址作为全流程标识
TCR_IP="172.18.100.10"
export FULL_IMAGE_NAME="${TCR_IP}/${TCR_NAMESPACE}/petclinic:${IMAGE_TAG}"
log_info "使用内网TCR地址: $FULL_IMAGE_NAME"

### ===== 网络修复措施 =====
log_info "配置Docker使用内网访问..."
sudo tee /etc/docker/daemon.json <<EOF
{
  "debug": true,
  "insecure-registries": ["$TCR_IP"],
  "dns": ["183.60.83.19"],
  "dns-opts": ["timeout:1", "attempts:3"],
  "mtu": 1450
}
EOF
systemctl restart docker

### ===== Docker 环境准备 =====
if ! command -v docker &>/dev/null; then
    log_info "安装 Docker..."
    sudo yum install -y yum-utils
    sudo yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
    sudo yum install -y docker-ce docker-ce-cli containerd.io
    sudo systemctl enable --now docker
    log_success "Docker 已安装"
fi

if ! docker ps &>/dev/null; then
    log_error "Docker 权限不足，请修复权限"
fi

if sudo systemctl restart docker; then
    log_success "Docker服务重启成功"
else
    log_warning "Docker服务重启失败..."
    [ -f /etc/docker/daemon.json.bak ] && sudo mv /etc/docker/daemon.json.bak /etc/docker/daemon.json
    sudo systemctl restart docker || log_error "无法恢复Docker配置"
fi

### ===== 安装必要依赖 =====
log_info "检查并安装必要依赖: jq..."
if ! command -v jq &>/dev/null; then
    log_info "安装 jq..."
    sudo yum install -y jq
    log_success "jq 已安装"
fi

### ===== Java 17 环境检查 =====
log_info "检查 Java 17 环境..."
if ! command -v java &>/dev/null; then
    log_info "安装 Java 17..."
    sudo yum install -y java-17-openjdk-devel
    log_success "Java 17 已安装"
fi

JAVA_VERSION=$(java -version 2>&1 | head -n1 | awk -F '"' '{print $2}')
if [[ $JAVA_VERSION != 17* ]]; then
    log_info "设置 Java 17 为默认版本..."
    JAVA_17_PATH=$(find /usr/lib/jvm -name "java-17-openjdk-*" -type d | head -1)
    if [ -z "$JAVA_17_PATH" ]; then
        sudo yum install -y java-17-openjdk-devel
        JAVA_17_PATH=$(find /usr/lib/jvm -name "java-17-openjdk-*" -type d | head -1)
    fi
    sudo alternatives --set java "$JAVA_17_PATH/bin/java"
    sudo alternatives --set javac "$JAVA_17_PATH/bin/javac"
    export JAVA_HOME="$JAVA_17_PATH"
    export PATH="${JAVA_HOME}/bin:${PATH}"
    log_success "Java 17 已设置为默认版本"
else
    log_success "已安装 Java 17: $JAVA_VERSION"
    export JAVA_HOME=$(dirname $(dirname $(readlink -f $(which java))))
    export PATH="${JAVA_HOME}/bin:${PATH}"
fi

### ===== 构建 Java 应用 =====
log_info "进入应用目录: $APP_DIR"
cd "$APP_DIR"
if [ -d "target" ]; then
    read -p "检测到已有构建目录，是否清理？(y/n): " clean_confirm
    if [ "$clean_confirm" = "y" ]; then
        rm -rf target
    fi
fi

mkdir -p ~/.m2
cat > ~/.m2/settings.xml <<EOF
<settings>
  <mirrors>
    <mirror>
      <id>tencent-cloud</id>
      <name>Tencent Cloud Mirror</name>
      <url>https://mirrors.cloud.tencent.com/nexus/repository/maven-public/</url>
      <mirrorOf>*</mirrorOf>
    </mirror>
  </mirrors>
</settings>
EOF

export MAVEN_OPTS="-Xmx1024m -Xms512m"
log_info "编译Java应用..."
if ! ./mvnw package -DskipTests -Dcheckstyle.skip=true -Dnohttp-checkstyle.skip=true -B -V; then
    log_error "Java编译失败"
fi

### ===== 构建 Docker 镜像 =====
log_info "创建 Dockerfile..."
cat > Dockerfile <<EOF
FROM mirror.ccs.tencentyun.com/library/openjdk:17-slim
WORKDIR /app
COPY target/spring-petclinic*.jar /app/petclinic.jar
EXPOSE 8080
ENTRYPOINT ["java", "-jar", "petclinic.jar"]
EOF

log_info "构建Docker镜像: $FULL_IMAGE_NAME"
docker build -t "$FULL_IMAGE_NAME" .

### ===== 修复时间问题 =====
log_info "检查系统时间..."
CURRENT_YEAR=$(date +%Y)
if [ "$CURRENT_YEAR" -gt 2024 ]; then
    log_warning "系统时间异常: $(date)"
    log_info "同步系统时间..."
    
    if ! command -v chronyc &>/dev/null; then
        log_info "安装chrony..."
        sudo yum install -y chrony
    fi
    
    sudo tee /etc/chrony.conf <<EOF
server ntp.aliyun.com iburst
server ntp1.aliyun.com iburst
server ntp2.aliyun.com iburst
server ntp3.aliyun.com iburst
server ntp4.aliyun.com iburst
EOF
    
    sudo systemctl enable --now chronyd
    sudo chronyc -a makestep
    sudo hwclock --systohc
    
    log_info "验证时间同步..."
    if chronyc tracking | grep -q "Leap status     : Normal"; then
        log_success "时间同步成功"
    else
        log_error "时间同步失败"
        chronyc tracking
        exit 1
    fi
    
    log_success "系统时间已同步: $(date)"
else
    log_success "系统时间正常: $(date)"
fi

### ===== 验证镜像 =====
log_info "启动测试容器验证镜像..."
TEST_CONTAINER_NAME="test-container-$(date +%s)"
docker run -d --name "$TEST_CONTAINER_NAME" -p 8080:8080 "$FULL_IMAGE_NAME"

log_info "等待应用启动..."
TIMEOUT=120
START_TIME=$(date +%s)
while true; do
    if ! docker inspect "$TEST_CONTAINER_NAME" &>/dev/null; then
        log_error "容器已停止运行"
        docker logs "$TEST_CONTAINER_NAME" || true
        exit 1
    fi
    
    if docker logs "$TEST_CONTAINER_NAME" | grep -q "Started PetClinicApplication"; then
        log_success "应用启动成功"
        break
    fi
    
    ELAPSED=$(( $(date +%s) - START_TIME ))
    if [ $ELAPSED -ge $TIMEOUT ]; then
        log_error "应用启动超时"
        docker logs "$TEST_CONTAINER_NAME" | tail -n 50
        docker stop "$TEST_CONTAINER_NAME" >/dev/null 2>&1 || true
        docker rm "$TEST_CONTAINER_NAME" >/dev/null 2>&1 || true
        exit 1
    fi
    
    sleep 5
done

HEALTH_STATUS=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/actuator/health)
if [ "$HEALTH_STATUS" != "200" ]; then
    log_error "健康检查失败 (状态码: $HEALTH_STATUS)"
    docker logs "$TEST_CONTAINER_NAME"
    docker stop "$TEST_CONTAINER_NAME" >/dev/null 2>&1 || true
    docker rm "$TEST_CONTAINER_NAME" >/dev/null 2>&1 || true
    exit 1
fi

log_success "镜像验证成功"
docker stop "$TEST_CONTAINER_NAME" >/dev/null 2>&1 || true
docker rm "$TEST_CONTAINER_NAME" >/dev/null 2>&1 || true

### ===== 推送镜像 =====
log_info "处理TCR密码..."
ENCODED_PASSWORD=$(echo -n "$TCR_PASSWORD" | jq -aRs . | sed 's/^"//;s/"$//')
[ -z "$ENCODED_PASSWORD" ] && ENCODED_PASSWORD="$TCR_PASSWORD"

log_info "登录TCR仓库..."
echo "$TCR_PASSWORD" | docker login "$TCR_IP" -u "$TCR_USERNAME" --password-stdin

log_info "推送镜像: $FULL_IMAGE_NAME"
docker push "$FULL_IMAGE_NAME"

### ===== Kubernetes 部署 =====
export FULL_IMAGE_NAME="${TCR_DOMAIN}/${TCR_NAMESPACE}/petclinic:${IMAGE_TAG}"
export KUBECONFIG="$KUBECONFIG_FILE"

[ ! -f "$KUBECONFIG_FILE" ] && log_error "kubeconfig 文件不存在"
! kubectl cluster-info &>/dev/null && log_error "kubectl 无法连接到集群"

log_info "检查命名空间 $K8S_NAMESPACE 是否存在..."
if ! kubectl get namespace "$K8S_NAMESPACE" &>/dev/null; then
    kubectl create namespace "$K8S_NAMESPACE"
fi

log_info "创建镜像拉取Secret..."
kubectl create secret docker-registry tcr-internal-credentials \
  --docker-server="${TCR_IP}" \
  --docker-username="${TCR_USERNAME}" \
  --docker-password="${ENCODED_PASSWORD}" \
  -n "$K8S_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

log_info "部署应用到Kubernetes..."
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: petclinic
  namespace: $K8S_NAMESPACE
spec:
  replicas: 3
  selector:
    matchLabels:
      app: petclinic
  template:
    metadata:
      labels:
        app: petclinic
    spec:
      imagePullSecrets:
      - name: tcr-credentials
      containers:
      - name: petclinic
        image: $FULL_IMAGE_NAME
        ports:
        - containerPort: 8080
        startupProbe:
          httpGet:
            path: /actuator/health
            port: 8080
          failureThreshold: 30
          periodSeconds: 10
EOF

### ===== 4层访问配置 =====
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: petclinic-service-layer4
  namespace: $K8S_NAMESPACE
  annotations:
    service.cloud.tencent.com/direct-access: "true"
spec:
  type: LoadBalancer
  externalTrafficPolicy: Local
  selector:
    app: petclinic
  ports:
  - protocol: TCP
    port: 8080
    targetPort: 8080
EOF

### ===== 7层访问配置 =====
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: petclinic-service-clusterip
  namespace: $K8S_NAMESPACE
spec:
  type: ClusterIP
  selector:
    app: petclinic
  ports:
  - name: http
    protocol: TCP
    port: 80
    targetPort: 8080
EOF

cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: petclinic-ingress
  namespace: $K8S_NAMESPACE
  annotations:
    ingress.cloud.tencent.com/direct-access: "true"
spec:
  ingressClassName: qcloud
  rules:
  - http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: petclinic-service-clusterip
            port:
              number: 80
EOF

### ===== 验证双访问 =====
log_info "获取4层访问地址..."
LAYER4_IP=""
MAX_RETRY=24  # 120秒超时
for ((i=1; i<=MAX_RETRY; i++)); do
    LAYER4_IP=$(kubectl -n $K8S_NAMESPACE get svc petclinic-service-layer4 -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)
    [ -n "$LAYER4_IP" ] && break
    [ $i -eq 1 ] && echo -n "等待IP分配" || echo -n "."
    [ $((i % 12)) -eq 0 ] && echo # 每60秒换行
    sleep 5
done
[ -n "$LAYER4_IP" ] && log_success "4层IP: $LAYER4_IP" || log_warning "4层IP获取超时"

log_info "获取7层访问地址..."
INGRESS_IP=""
for ((i=1; i<=MAX_RETRY; i++)); do
    INGRESS_IP=$(kubectl -n $K8S_NAMESPACE get ingress petclinic-ingress -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)
    [ -n "$INGRESS_IP" ] && break
    [ $i -eq 1 ] && echo -n "等待Ingress就绪" || echo -n "."
    [ $((i % 12)) -eq 0 ] && echo
    sleep 5
done
[ -n "$INGRESS_IP" ] && log_success "7层IP: $INGRESS_IP" || log_warning "7层IP获取超时"


### ===== 日志收集配置 =====
log_info "配置容器日志收集..."

# 安装日志采集CRD（使用官方文档示例结构）
log_info "安装日志采集CRD..."
cat <<EOF | kubectl apply -f -
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
log_success "日志采集CRD已安装"

# 等待CRD注册完成
log_info "等待CRD注册完成..."
for i in {1..10}; do
  kubectl get crd logconfigs.cls.cloud.tencent.com >/dev/null 2>&1 && break
  sleep 3
done
log_success "CRD注册验证完成"

# 配置日志采集Agent（ConfigMap）
log_info "开通日志采集功能..."
kubectl apply -f - <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: tke-log-agent-config
  namespace: kube-system
data:
  clusterId: ${CLUSTER_ID}  # 使用CLUSTER_ID而不是CLUSTER_NAME
  region: ${REGION}
  logAgent: "enabled"
EOF
log_success "日志采集功能已开通"

# 配置标准输出日志采集
log_info "配置标准日志采集规则..."
kubectl apply -f - <<EOF
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
    logsetName: "TC-log"  # 指定日志集名称（自动创建）
    topicName: "petclinic-stdout-topic"  # 指定日志主题名称（自动创建）
    logType: minimalist_log
EOF
log_success "标准输出日志规则已配置"

# 配置容器文件日志采集
log_info "配置容器文件日志采集..."
kubectl apply -f - <<EOF
apiVersion: cls.cloud.tencent.com/v1
kind: LogConfig
metadata:
  name: petclinic-log-files
spec:
  inputDetail:
    type: container_file
    containerFile:
      namespace: ${K8S_NAMESPACE}
      container: '*'  # 采集所有容器
      logPath: /var/log  # 官方文档中常用路径
      filePattern: '*.log'  # 日志文件模式
      workload:
        - kind: Deployment
          name: petclinic
          namespace: ${K8S_NAMESPACE}
  clsDetail:
    logsetName: "TC-log"  # 使用同一个日志集
    topicName: "petclinic-file-topic"  # 不同的主题
    logType: fullregex_log  # 完全正则格式
EOF
log_success "文件日志规则已配置"

log_success "日志收集配置完成!"

### ===== 配置HPA水平伸缩 =====
log_info "配置HPA自动扩容策略..."
cat <<EOF | kubectl apply -f -
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: petclinic-hpa
  namespace: $K8S_NAMESPACE
spec:
  behavior:  # 添加平滑扩缩策略
    scaleDown:
      stabilizationWindowSeconds: 300  # 5分钟冷却期
      policies:
      - type: Percent
        value: 10
        periodSeconds: 60
    scaleUp:
      stabilizationWindowSeconds: 60    # 1分钟快速扩容
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
# 添加平滑扩缩行为配置，CPU阈值设为65%更具响应性

### ===== 配置HPC定时伸缩策略 =====
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
    schedule: "2 8 * * 1-5"    # 添加分钟偏移，避免整点高峰冲突
    targetSize: 10
  - name: evening-scale-down
    schedule: "2 18 * * 1-5"   # 添加分钟偏移
    targetSize: 3
  - name: weekend-scale-down
    schedule: "30 23 * * 5"    # 调整为周五晚上11:30，避免周六凌晨处理
    targetSize: 2
EOF

### ===== 完成 =====
log_success "所有配置完成!"
echo "==========================="
echo "集群名称: $CLUSTER_NAME"
echo "集群ID: $CLUSTER_ID"
echo "地域: $REGION"
[ -n "$LAYER4_IP" ] && echo "4层访问地址: http://$LAYER4_IP:8080"
[ -n "$INGRESS_IP" ] && echo "7层访问地址: http://$INGRESS_IP"
echo "健康检查: curl http://$INGRESS_IP/actuator/health"
echo "HPA状态: kubectl get hpa -n $K8S_NAMESPACE"
echo "HPC状态: kubectl get hpc -n $K8S_NAMESPACE"
echo "日志控制台: https://console.cloud.tencent.com/cls"
echo "==========================="

# 安全清理
docker logout "$TCR_IP" >/dev/null 2>&1 || true
unset TCR_PASSWORD  
