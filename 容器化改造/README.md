### 背景与必要性

传统应用部署面临资源利用率低、扩缩容缓慢、运维复杂等挑战。容器化改造通过 Kubernetes 标准化管理，实现：
- ​**资源弹性**​：按需伸缩，降低闲置成本
- ​**高可用保障**​：多可用区部署，避免单点故障
### 实践意义：
聚焦业务系统容器化全流程实践，深度验证TKE原生节点与超级节点的核心能力，沉淀可复用的技术经验与最佳实践。
为后续客户业务拓展提供强有力的产品能力支撑与落地参考。

### 项目核心价值

1. ​**成本优化**​：原生节点（常驻） + 超级节点（弹性）
2. ​**高可用架构**​：南京一区 + 南京三区双可用区部署
3. ​**一键式运维**​：日志采集 + 自动伸缩 + 定时伸缩
4. ​**安全合规**​：私有镜像仓库（TCR） + 内网访问 + 精细化权限控制

### 部署流程图

```mermaid
graph TD
    %% 主框架
    A[容器化改造]
    A --> B[Terraform基础设施部署]
    A --> C[镜像构建与推送]
    A --> D[服务部署与暴露]
    A --> E[日志采集配置]
    A --> F[弹性伸缩配置]
    
    %% 基础设施部署
    subgraph B[Terraform基础设施部署]
        B1[创建VPC/子网/安全组配置]
        B2[配置TKE集群]
        B3[部署TCR仓库]
    end
    
    %% 镜像管理
    subgraph C[镜像构建与推送]
        C1[构建业务镜像]
        C2[推送至TCR]
    end
    
    %% 服务部署
    subgraph D[服务部署与暴露]
        D1[部署工作负载]
        D2[配置4层Service]
        D3[配置7层Ingress]

    end
    
    %% 精确日志采集配置
    subgraph E[日志采集配置]
       
        E4[标准输出采集]
        E5[文件日志采集]
  
    end
    
    %% 精确弹性伸缩配置
    subgraph F[弹性伸缩配置]
        F1[配置HPA]
        
        F2[配置HPC]
       
        
    
    end
    
    %% 依赖关系
   
    
    %% 样式定义
    classDef infra fill:#e6f7ff,stroke:#1890ff;
    classDef image fill:#f6ffed,stroke:#52c41a;
    classDef service fill:#fff7e6,stroke:#ffc53d;
    classDef logging fill:#f9f0ff,stroke:#722ed1;
    classDef scaling fill:#fcffe6,stroke:#a0d911;
    
    class B infra
    class C image
    class D service
    class E logging
    class F scaling
    class B1,B2,B3,B4,B5 infra
    class C1,C2 image
    class D1,D2,D3,D4 service
    class E1,E2,E3,E4,E5 logging
    class F1,F1a,F1b,F1c,F2,F2a,F2b,F2c scaling
```

### 业务访问链路流程图

```mermaid
graph LR
    User["👥 终端用户"] --> |"HTTP/HTTPS<br>(80/443端口)"| LB["🔵 CLB类型Service/Ingress"]
    LB --> |"直连"| Pod["🟪 应用Pod"]
    
    classDef user fill:#f0f7ff,stroke:#5b8ff9,stroke-width:2px;
    classDef lb fill:#e6f7ff,stroke:#1890ff,stroke-width:2px;
    classDef pod fill:#f9f0ff,stroke:#722ed1,stroke-width:2px;
    
    class User user
    class LB lb
    class Pod pod
    
    linkStyle 0 stroke:#888,stroke-width:2px;
    linkStyle 1 stroke:#722ed1,stroke-width:2px;
```
`
### 前提条件

1. ​**腾讯云账号**​：子账号需 `QcloudTKEAccess` 权限

  - 访问地址：[使用 TKE 预设策略授权](https://cloud.tencent.com/document/product/457/46033) 
3. ​**网络环境**​：- VPC CIDR：`172.18.0.0/16`（默认，变量可自设）。
	- 子网分配：默认南京一区（`primary`）、南京三区（`secondary`）。
4. ​**TKE 集群规格​**​：
    - TKE 集群规格 ≥ L20
5. ​**TCR 镜像仓库​**​：
	- TCR 企业版实例
	

### 快速开始

#### 步骤1：Terraform基础设施搭建
```
# 执行 deploy_infra.sh
./deploy_infra.sh
read -p "请输入区域（默认ap-nanjing）: " REGION
REGION=${REGION:-"ap-nanjing"}
read -p "请输入VPC CIDR（默认172.18.0.0/16）: " VPC_CIDR
VPC_CIDR=${VPC_CIDR:-"172.18.0.0/16"}
read -p "请输入Kubernetes版本（默认1.32.2）: " CLUSTER_VERSION
CLUSTER_VERSION=${CLUSTER_VERSION:-"1.32.2"}
read -p "请输入服务CIDR（默认10.200.0.0/22）: " SERVICE_CIDR
SERVICE_CIDR=${SERVICE_CIDR:-"10.200.0.0/22"}
read -p "请输入节点实例类型（默认SA5.MEDIUM4）: " INSTANCE_TYPE
INSTANCE_TYPE=${INSTANCE_TYPE:-"SA5.MEDIUM4"}
```
- 输出：集群 ID、VPC ID、安全组 ID、子网 ID(primary,secondary)、TCR 仓库 URL、kubeconfig.yaml

![这是个图片](images/Terraform基础设施搭建截图.png)

#### 步骤2：镜像构建及推送
```
# 执行 deploy_images.sh
./deploy_images.sh
read -p "输入TCR仓库URL（TCR_REGISTRY_URL）: " TCR_REGISTRY_URL #步骤1生成的TCR仓库URL
read -p "输入TCR凭证服务级用户名（TCR_USERNAME）: " TCR_USERNAME
read -s -p "输入TCR凭证服务级密码（TCR_PASSWORD）: " TCR_PASSWORD
read -p "输入TCR命名空间（TCR_NAMESPACE）: " TCR_NAMESPACE
read -p "输入TCR镜像版本（IMAGE_TAG）: " IMAGE_TAG
```
- 输出：镜像地址、TCR仓库URL、TCR命名空间、镜像版本

![这是个图片](images/镜像构建及推送.png)
#### 步骤3：服务部署与暴露
```
# 执行 deploy_services.sh
./deploy_services.sh
read -p "输入完整的镜像地址（FULL_IMAGE_NAME）: " FULL_IMAGE_NAME
read -p "输入TCR凭证服务级用户名（TCR_USERNAME）: " TCR_USERNAME
read -s -p "输入TCR凭证服务级密码（TCR_PASSWORD）: " TCR_PASSWORD
read -p "输入TCR仓库URL（TCR_REGISTRY_URL）: " TCR_REGISTRY_URL
read -p "输入集群命名空间（K8S_NAMESPACE）: " K8S_NAMESPACE
```
- 输出：工作负载、4层服务、7层服务

![这是个图片](images/服务部署与暴露.png)
#### 步骤4：日志采集
```
# 执行 deploy_logging.sh
./deploy_logging.sh
read -p "输入集群命名空间（K8S_NAMESPACE）: " K8S_NAMESPACE
```
- 输出：标准输出日志、容器文件日志

![这是个图片](images/日志采集.png)
#### 步骤5：弹性伸缩配置
```
# 执行 deploy_autoscale.sh
./deploy_autoscale.sh
read -p "输入集群命名空间（K8S_NAMESPACE）: " K8S_NAMESPACE
```
- 输出：HPA状态、HPC状态

![这是个图片](images/弹性伸缩配置.png)



### 演练环境配置举例说明

#### 配置1：多子网高可用设计（默认南京一区/三区）
**网络配置​**:
```
variable "subnets" {
  description = "子网配置"
  type = map(object({
    cidr = string
    az   = string
  }))
  default = {
    "primary" = {
      cidr = "172.18.100.0/24"
      az   = "ap-nanjing-1"
    }
    "secondary" = {
      cidr = "172.18.101.0/24"
      az   = "ap-nanjing-3"
    }
  }
}
```

#### 配置2：TKE集群与节点池配置

##### ​**原生节点池​**:
```
### ===== 南京一区专用节点池（primary子网） =====
  native {
    instance_charge_type = "POSTPAID_BY_HOUR"
    instance_types       = [var.instance_type]
    security_group_ids   = [tencentcloud_security_group.main.id]
    subnet_ids           = [tencentcloud_subnet.subnets["primary"].id] # 仅使用primary子网
    
    key_ids              = ["skey-gigpdrzz"]
    replicas             = 2  # 可用区1节点数
    machine_type         = "Native"
    
    scaling {
      min_replicas  = 2
      max_replicas  = 6
      create_policy = "ZoneEquality"  # 确保节点均匀分布
    }
    
    system_disk {
      disk_type = "CLOUD_BSSD"
      disk_size = 100
    }

    data_disks {
      auto_format_and_mount = true
      disk_type             = "CLOUD_BSSD"
      disk_size             = 100
      file_system           = "xfs"
      mount_target          = "/var/lib/containerd"
    }
  }

### ===== 南京三区专用节点池（primary子网） =====
  native {
    instance_charge_type = "POSTPAID_BY_HOUR"
    instance_types       = [var.instance_type]
    security_group_ids   = [tencentcloud_security_group.main.id]
    subnet_ids           = [tencentcloud_subnet.subnets["secondary"].id] # 仅使用secondary子网
    
    key_ids              = ["skey-gigpdrzz"]
    replicas             = 2  # 可用区3节点数
    machine_type         = "Native"
    
    scaling {
      min_replicas  = 2
      max_replicas  = 6
      create_policy = "ZoneEquality"  # 确保节点均匀分布
    }
    
    system_disk {
      disk_type = "CLOUD_BSSD"
      disk_size = 100
    }

    data_disks {
      auto_format_and_mount = true
      disk_type             = "CLOUD_BSSD"
      disk_size             = 100
      file_system           = "xfs"
      mount_target          = "/var/lib/containerd"
    }
  }
  ```
  
#####  **超级节点池​**:
  ```
  # 主可用区节点
  serverless_nodes {
    display_name = "super-node-1"
    subnet_id    = tencentcloud_subnet.subnets["primary"].id
  }
  # 备用可用区节点
  serverless_nodes {
    display_name = "super-node-2"
    subnet_id    = tencentcloud_subnet.subnets["secondary"].id
  }
  
  labels = {
    "workload-type" = "elastic"
    "ha"            = "enabled"
  }
  
  lifecycle {
    ignore_changes = [
      serverless_nodes
    ]
  }
  ```
  #### 配置3：四层/七层访问入口

##### ​**四层访问​**:
```
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
```
##### **七层访问​**:
```
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
```

#### 配置4：日志采集
##### **标准输出日志采集​**:
```
### ===== 配置标准输出日志采集 =====
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
```
##### **容器文件日志采集​**:
```
### ===== 配置容器文件日志采集 =====
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
```
#### 配置5：弹性伸缩
##### **HPA 配置​**:
```
### ===== 配置HPA水平伸缩 =====
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
```
##### **HPC 配置​**:
```
### ===== 配置HPC定时伸缩策略 =====
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
```

### 验证标准

1. ​**基础设施层**​：
   - `terraform output` 显示 VPC/子网状态正常且输出ID
   -  集群及相关资源部署完成
	- TCR 镜像仓库构建成功

![这是个图片](images/Terraform基础设施搭建截图.png)
2. ​**应用层**​：
   - 访问 `http://$LAYER4_IP:8080` 访问网址成功
   - 访问 `http://$INGRESS_IP` 访问网址成功
	-  日志采集-业务日志开启可见容器文件路径及容器标准输出

![这是个图片](images/四层访问.png)
![这是个图片](images/七层访问.png)
![这是个图片](images/文件日志采集.png)
3. ​**弹性能力**​：
   - HPA CPU利用率达到范围触发策略变化
   - HPC 定时触发副本数变化

![这是个图片](images/HPA（1）.png)
![这是个图片](images/HPA（2）.png)
![这是个图片](images/HPC（1）.png)
![这是个图片](images/HPC（2）.png)

### 项目结构
```
containerization-transformation/
├── infra/                  # Terraform基础设施
│   ├── deploy_infra.sh     # 主脚本（创建VPC/TKE/TCR/验证）
│   ├── terraform/          # Terraform 模块
        └── network.tf          # 网络模块资源
        └── cluster.tf          # 集群模块资源
        └── tcr.tf              # 镜像模块资源
        └── providers.tf        # 腾讯云提供者
	    └── variables.tf        # 定义变量传递
│       └── output.tf           # 资源输出定义
├── images/                 # 镜像构建及推送
│   ├── deploy_images.sh    # 主脚本（镜像构建/推送）
│   ├── Dockerfile              # 应用容器化定义
├── services/               # 服务与暴露
│   ├── deploy_services.sh  # 主脚本（服务/暴露/验证）
│   └── k8s-manifests/          #K8s YAML 文件
├── logging/                # 日志采集
│   ├── deploy_logging.sh   # 主脚本（标准输出日志/容器文件日志）
│   └── k8s-manifests/          #K8s YAML 文件
├── autoscale/              # 弹性伸缩
│   ├── deploy_autoscale.sh # 主脚本（HPA/HPC）
│   └── k8s-manifests/          # K8s YAML 文件
├── docs/                   # 文档
│   └── README.md           # 本指南
```
