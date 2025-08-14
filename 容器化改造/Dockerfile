# 构建阶段,使用alibabadragonwell/dragonwell:17-ubuntu 作为基础镜像，该基础镜像满足项目运行依赖需要（包含java 17, mvnw 工具），如有其他需求可以更换其他镜像
FROM alibabadragonwell/dragonwell:17-ubuntu AS builder 
# 设置工作目录
WORKDIR /app
# 安装Git
RUN apt-get update && apt-get install -y git
# 从GitHub拉取代码
RUN git clone https://github.com/spring-projects/spring-petclinic.git .
# 构建项目
RUN ./mvnw package 

# 运行阶段
FROM alibabadragonwell/dragonwell:17-ubuntu
# 设置工作目录
WORKDIR /app
# 暴露端口
EXPOSE 8080
# 复制构建产物到运行时镜像
COPY --from=builder /app/target/*.jar petclinic.jar
#RUN chmod 775 *.jar
# 定义容器启动命令
ENTRYPOINT ["java", "-jar", "petclinic.jar"]
