#!/bin/bash
set -euo pipefail

### ===== 日志函数 =====
log_info() { echo -e "\033[1;34m[i] $1\033[0m"; }
log_success() { echo -e "\033[1;32m[✓] $1\033[0m"; }
log_warning() { echo -e "\033[1;33m[!] $1\033[0m"; }
log_error() { echo -e "\033[1;31m[✗] $1\033[0m"; exit 1; }

### ===== 环境准备 =====
# 检查关键变量是否已设置
REQUIRED_VARS=("TCR_REGISTRY_URL" "APP_DIR" "TCR_IMAGE_FQIN" "TCR_NAMESPACE" "IMAGE_TAG")
for var in "${REQUIRED_VARS[@]}"; do
    if [ -z "${!var:-}" ]; then
        log_error "缺少环境变量: $var"
    fi
done

log_info "开始构建Java业务镜像"
log_info "镜像目标: $TCR_IMAGE_FQIN"
log_info "应用目录: $APP_DIR"

### ===== Docker 环境准备（以CentOS为例） =====
log_info "检查Docker环境..."
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

sudo systemctl restart docker || log_warning "Docker服务重启失败"

### ===== 网络修复措施 =====
log_info "配置Docker使用TCR仓库URL访问..."
sudo tee /etc/docker/daemon.json <<EOF
{
  "debug": true,
  "insecure-registries": ["${TCR_REGISTRY_URL}"],
  "dns": ["183.60.83.19"],
  "dns-opts": ["timeout:1", "attempts:3"],
  "mtu": 1450
}
EOF
sudo systemctl restart docker

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
cd "$APP_DIR" || log_error "应用目录不存在"

# 修复 Maven Wrapper 配置
if [ -f ".mvn/wrapper/maven-wrapper.properties" ]; then
    log_info "修复 Maven Wrapper 配置..."
    echo "distributionUrl=https://mirrors.cloud.tencent.com/nexus/repository/maven-public/org/apache/maven/apache-maven/3.9.10/apache-maven-3.9.10-bin.zip" > .mvn/wrapper/maven-wrapper.properties
fi

if [ -d "target" ]; then
    read -p "检测到已有构建目录，是否清理？(y/n): " clean_confirm
    [ "$clean_confirm" = "y" ] && rm -rf target
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
./mvnw package -DskipTests -Dcheckstyle.skip=true -Dnohttp-checkstyle.skip=true -B -V || log_error "Java编译失败"

### ===== 构建 Docker 镜像 =====
log_info "创建 Dockerfile..."
cat > Dockerfile <<EOF
FROM mirror.ccs.tencentyun.com/library/openjdk:17-slim
WORKDIR /app
COPY target/spring-petclinic*.jar /app/petclinic.jar
EXPOSE 8080
ENTRYPOINT ["java", "-jar", "petclinic.jar"]
EOF

log_info "构建TCR镜像: ${TCR_IMAGE_FQIN}"
docker build -t "${TCR_IMAGE_FQIN}" .

### ===== 时间同步 =====
log_info "检查系统时间..."
CURRENT_YEAR=$(date +%Y)
if [ "$CURRENT_YEAR" -gt 2024 ] || [ "$CURRENT_YEAR" -lt 2020 ]; then
    log_warning "系统时间异常: $(date)"
    log_info "同步系统时间..."
    
    ! command -v chronyc &>/dev/null && sudo yum install -y chrony
    
    sudo tee /etc/chrony.conf <<EOF
server ntp.tencent.com iburst
server ntp1.tencent.com iburst
server ntp2.tencent.com iburst
server ntp3.tencent.com iburst
EOF
    
    sudo systemctl enable --now chronyd
    sudo chronyc -a makestep
    sudo hwclock --systohc
    
    chronyc tracking | grep -q "Leap status     : Normal" || {
        chronyc tracking
        log_error "时间同步失败"
    }
    
    log_success "系统时间已同步: $(date)"
fi

echo "${TCR_IMAGE_FQIN}" > /tmp/image_name.txt
log_success "Java业务镜像构建完成: ${TCR_IMAGE_FQIN}"
