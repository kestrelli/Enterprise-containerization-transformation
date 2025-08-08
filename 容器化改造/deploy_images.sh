#!/bin/bash
set -euo pipefail

### ===== 日志函数 =====
log_info() { echo -e "\033[1;34m[i] $1\033[0m"; }
log_success() { echo -e "\033[1;32m[✓] $1\033[0m"; }
log_warning() { echo -e "\033[1;33m[!] $1\033[0m"; }
log_error() { echo -e "\033[1;31m[✗] $1\033[0m"; exit 1; }

### ===== 用户输入配置 =====
# 获取用户输入
read -p "输入TCR仓库URL（TCR_REGISTRY_URL）: " TCR_REGISTRY_URL
read -p "输入TCR凭证服务级用户名（TCR_USERNAME）: " TCR_USERNAME
read -s -p "输入TCR凭证服务级密码（TCR_PASSWORD）: " TCR_PASSWORD
read -p "输入TCR命名空间（TCR_NAMESPACE）: " TCR_NAMESPACE
read -p "输入TCR镜像版本（IMAGE_TAG）: " IMAGE_TAG
echo

### ===== 核心配置 =====
APP_DIR="/opt/spring-petclinic"
BUILD_LOG="/tmp/petclinic-build.log"

# 使用TCR仓库URL作为全流程标识
export FULL_IMAGE_NAME="${TCR_REGISTRY_URL}/${TCR_NAMESPACE}/petclinic:${IMAGE_TAG}"
log_info "使用TCR仓库URL: $FULL_IMAGE_NAME"

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

### ===== 网络修复措施 =====
log_info "配置Docker使用TCR仓库URL访问..."
sudo tee /etc/docker/daemon.json <<EOF
{
  "debug": true,
  "insecure-registries": ["$TCR_REGISTRY_URL"],
  "dns": ["183.60.83.19"],
  "dns-opts": ["timeout:1", "attempts:3"],
  "mtu": 1450
}
EOF
systemctl restart docker

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
# 修复 Maven Wrapper 配置
if [ -f ".mvn/wrapper/maven-wrapper.properties" ]; then
    log_info "修复 Maven Wrapper 配置..."
    # 备份原始配置
    cp .mvn/wrapper/maven-wrapper.properties .mvn/wrapper/maven-wrapper.properties.bak
    
    # 设置为正确的下载 URL
    echo "distributionUrl=https://mirrors.cloud.tencent.com/nexus/repository/maven-public/org/apache/maven/apache-maven/3.9.10/apache-maven-3.9.10-bin.zip" > .mvn/wrapper/maven-wrapper.properties
fi

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

log_info "登录TCR仓库..."
echo "$TCR_PASSWORD" | docker login "$TCR_REGISTRY_URL" -u "$TCR_USERNAME" --password-stdin

log_info "推送镜像: $FULL_IMAGE_NAME"
docker push "$FULL_IMAGE_NAME"

log_success "镜像构建和推送完成!"
echo "==========================="
echo "镜像地址: $FULL_IMAGE_NAME"
echo "TCR仓库URL: $TCR_REGISTRY_URL"
echo "TCR命名空间: $TCR_NAMESPACE"
echo "镜像版本: $IMAGE_TAG"
echo "==========================="

# 安全清理
docker logout "$TCR_REGISTRY_URL" >/dev/null 2>&1 || true
unset TCR_PASSWORD