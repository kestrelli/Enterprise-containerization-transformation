# 构建阶段,使用腾讯云镜像源加速alibabadragonwell/dragonwell:17-ubuntu 作为基础镜像，该基础镜像满足项目运行依赖需要（包含java 17, mvnw 工具），如有其他需求可以更换其他镜像
FROM alibabadragonwell/dragonwell:17-ubuntu AS builder 

# 设置工作目录
WORKDIR /app

# 安装Git（使用腾讯云源）
RUN sed -i 's/archive.ubuntu.com/mirrors.tencentyun.com/g' /etc/apt/sources.list && \
    apt update && \
    apt install -y git

# 从GitHub拉取代码
RUN git clone https://github.com/spring-projects/spring-petclinic.git .

# 配置Maven使用腾讯云镜像
RUN mkdir -p /root/.m2
COPY settings.xml /root/.m2/settings.xml

# 先下载依赖（利用缓存）
RUN ./mvnw dependency:go-offline -B

# 构建项目（跳过测试）
RUN ./mvnw package -DskipTests -B

# 运行阶段
FROM mirror.ccs.tencentyun.com/alibabadragonwell/dragonwell:17-ubuntu
# 设置工作目录
WORKDIR /app
# 暴露端口
EXPOSE 8080
# 复制构建产物到运行时镜像
COPY --from=builder /app/target/*.jar petclinic.jar
# 定义容器启动命令
ENTRYPOINT ["java", "-jar", "petclinic.jar"]


