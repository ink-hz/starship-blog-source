---
title: 'Kubernetes与容器编排深度指南'
description: '全面覆盖Kubernetes架构、核心组件（API Server、etcd、Scheduler）、Pod调度、服务网格、存储管理、安全策略及生产运维实践，含丰富代码示例。'
pubDate: 2026-03-23
tags: ['云原生架构']
---
# Kubernetes与容器编排深度指南

**学习深度**: ⭐⭐⭐⭐⭐

---

## 第一部分：Kubernetes 架构与核心组件

### 1.1 Kubernetes 整体架构

Kubernetes 是一个用于自动部署、扩展和管理容器化应用程序的开源平台。

**架构全景图**:
```
┌─────────────────────────────────────────────────────────────┐
│                     Kubernetes Cluster                      │
│                                                              │
│  ┌────────────────────────────────────────────────────┐    │
│  │              Control Plane (Master)                │    │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────┐ │    │
│  │  │              │  │              │  │          │ │    │
│  │  │ API Server   │  │   etcd       │  │Scheduler │ │    │
│  │  │ (kube-api)   │  │(分布式存储) │  │          │ │    │
│  │  │              │  │              │  │          │ │    │
│  │  └──────┬───────┘  └──────────────┘  └────┬─────┘ │    │
│  │         │                                  │       │    │
│  │  ┌──────▼────────────────────────────────▼─────┐  │    │
│  │  │  Controller Manager                         │  │    │
│  │  │  - Node Controller                          │  │    │
│  │  │  - Replication Controller                   │  │    │
│  │  │  - Endpoints Controller                     │  │    │
│  │  └─────────────────────────────────────────────┘  │    │
│  └────────────────────────────────────────────────────┘    │
│                           │                                 │
│                           │ (通过 kubelet)                 │
│                           │                                 │
│  ┌────────────────────────▼───────────────────────────┐    │
│  │                   Worker Nodes                     │    │
│  │                                                     │    │
│  │  ┌─────────────┐  ┌─────────────┐  ┌────────────┐ │    │
│  │  │   Node 1    │  │   Node 2    │  │   Node 3   │ │    │
│  │  │             │  │             │  │            │ │    │
│  │  │  ┌────────┐ │  │  ┌────────┐ │  │ ┌────────┐│ │    │
│  │  │  │kubelet │ │  │  │kubelet │ │  │ │kubelet ││ │    │
│  │  │  └───┬────┘ │  │  └───┬────┘ │  │ └───┬────┘│ │    │
│  │  │      │      │  │      │      │  │     │     │ │    │
│  │  │  ┌───▼────┐ │  │  ┌───▼────┐ │  │ ┌───▼────┐│ │    │
│  │  │  │ Pods   │ │  │  │ Pods   │ │  │ │ Pods   ││ │    │
│  │  │  │┌──┐┌──┐│ │  │  │┌──┐┌──┐│ │  │ │┌──┐┌──┐││ │    │
│  │  │  ││C1││C2││ │  │  ││C1││C2││ │  │ ││C1││C2│││ │    │
│  │  │  │└──┘└──┘│ │  │  │└──┘└──┘│ │  │ │└──┘└──┘││ │    │
│  │  │  └────────┘ │  │  └────────┘ │  │ └────────┘│ │    │
│  │  │             │  │             │  │            │ │    │
│  │  │  ┌────────┐ │  │  ┌────────┐ │  │ ┌────────┐│ │    │
│  │  │  │kube-   │ │  │  │kube-   │ │  │ │kube-   ││ │    │
│  │  │  │proxy   │ │  │  │proxy   │ │  │ │proxy   ││ │    │
│  │  │  └────────┘ │  │  └────────┘ │  │ └────────┘│ │    │
│  │  └─────────────┘  └─────────────┘  └────────────┘ │    │
│  └─────────────────────────────────────────────────────┘    │
└──────────────────────────────────────────────────────────────┘
```

### 1.2 核心组件详解

#### 1.2.1 Control Plane 组件

##### **API Server (kube-apiserver)**

**职责**:
- Kubernetes 的前端，所有组件都通过它通信
- 提供 RESTful API 接口
- 负责认证、授权、准入控制

**请求流程**:
```
kubectl apply -f deployment.yaml
         │
         ▼
   ┌─────────────┐
   │ API Server  │
   └──────┬──────┘
          │
          ├─► 1. Authentication (认证)
          │      - ServiceAccount Token
          │      - X.509 证书
          │
          ├─► 2. Authorization (授权)
          │      - RBAC
          │      - ABAC
          │
          ├─► 3. Admission Control (准入控制)
          │      - MutatingWebhook
          │      - ValidatingWebhook
          │      - ResourceQuota
          │
          ▼
   ┌─────────────┐
   │    etcd     │
   │  (持久化)   │
   └─────────────┘
```

**自定义准入控制器示例**:
```go
// ValidatingWebhook 示例 - 验证 Pod 必须有资源限制
package main

import (
    "encoding/json"
    "fmt"
    "io/ioutil"
    "net/http"

    admissionv1 "k8s.io/api/admission/v1"
    corev1 "k8s.io/api/core/v1"
    metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
)

type WebhookServer struct{}

func (ws *WebhookServer) validate(w http.ResponseWriter, r *http.Request) {
    // 读取请求体
    body, err := ioutil.ReadAll(r.Body)
    if err != nil {
        http.Error(w, "Failed to read request", http.StatusBadRequest)
        return
    }

    // 解析 AdmissionReview
    admissionReview := admissionv1.AdmissionReview{}
    if err := json.Unmarshal(body, &admissionReview); err != nil {
        http.Error(w, "Failed to parse request", http.StatusBadRequest)
        return
    }

    // 解析 Pod
    pod := corev1.Pod{}
    if err := json.Unmarshal(admissionReview.Request.Object.Raw, &pod); err != nil {
        http.Error(w, "Failed to parse pod", http.StatusBadRequest)
        return
    }

    // 验证逻辑：检查每个容器是否有资源限制
    allowed := true
    message := ""

    for _, container := range pod.Spec.Containers {
        if container.Resources.Limits == nil ||
           container.Resources.Requests == nil {
            allowed = false
            message = fmt.Sprintf(
                "Container %s must have resource limits and requests",
                container.Name,
            )
            break
        }

        // 检查是否设置了 CPU 和内存
        limits := container.Resources.Limits
        requests := container.Resources.Requests

        if _, ok := limits[corev1.ResourceCPU]; !ok {
            allowed = false
            message = fmt.Sprintf(
                "Container %s must have CPU limit",
                container.Name,
            )
            break
        }

        if _, ok := requests[corev1.ResourceMemory]; !ok {
            allowed = false
            message = fmt.Sprintf(
                "Container %s must have memory request",
                container.Name,
            )
            break
        }
    }

    // 构造响应
    admissionResponse := &admissionv1.AdmissionResponse{
        UID:     admissionReview.Request.UID,
        Allowed: allowed,
    }

    if !allowed {
        admissionResponse.Result = &metav1.Status{
            Message: message,
        }
    }

    // 返回 AdmissionReview
    responseAdmissionReview := admissionv1.AdmissionReview{
        TypeMeta: admissionReview.TypeMeta,
        Response: admissionResponse,
    }

    respBytes, err := json.Marshal(responseAdmissionReview)
    if err != nil {
        http.Error(w, "Failed to marshal response", http.StatusInternalServerError)
        return
    }

    w.Header().Set("Content-Type", "application/json")
    w.Write(respBytes)
}

func main() {
    ws := &WebhookServer{}
    http.HandleFunc("/validate", ws.validate)
    fmt.Println("Webhook server started on :8443")
    http.ListenAndServeTLS(":8443", "server.crt", "server.key", nil)
}
```

**ValidatingWebhookConfiguration**:
```yaml
apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingWebhookConfiguration
metadata:
  name: pod-resource-validator
webhooks:
- name: validate.resources.example.com
  clientConfig:
    service:
      name: resource-validator
      namespace: default
      path: "/validate"
    caBundle: <base64-encoded-ca-cert>
  rules:
  - operations: ["CREATE", "UPDATE"]
    apiGroups: [""]
    apiVersions: ["v1"]
    resources: ["pods"]
  admissionReviewVersions: ["v1"]
  sideEffects: None
  timeoutSeconds: 5
  failurePolicy: Fail  # 验证失败则拒绝
```

##### **etcd**

**职责**:
- 分布式键值存储
- 保存集群所有状态信息
- 支持 watch 机制

**数据结构**:
```
etcd 数据存储结构:

/registry
├── pods
│   └── default
│       └── nginx-pod
│           └── {pod-spec-json}
├── services
│   └── default
│       └── web-service
│           └── {service-spec-json}
├── deployments
│   └── default
│       └── nginx-deployment
│           └── {deployment-spec-json}
└── secrets
    └── default
        └── db-password
            └── {encrypted-secret}
```

**etcd 备份与恢复**:
```bash
# 备份 etcd
ETCDCTL_API=3 etcdctl snapshot save /backup/etcd-snapshot.db \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key

# 验证快照
ETCDCTL_API=3 etcdctl snapshot status /backup/etcd-snapshot.db --write-out=table

# 恢复 etcd
ETCDCTL_API=3 etcdctl snapshot restore /backup/etcd-snapshot.db \
  --data-dir=/var/lib/etcd-restore \
  --initial-cluster=etcd-0=https://10.0.0.1:2380 \
  --initial-advertise-peer-urls=https://10.0.0.1:2380 \
  --name=etcd-0
```

##### **Scheduler (kube-scheduler)**

**职责**:
- 监听未调度的 Pod
- 为 Pod 选择最优节点
- 考虑资源需求、亲和性、污点等

**调度流程**:
```
新 Pod 创建
    │
    ▼
┌──────────────────┐
│ 1. Filtering     │  过滤阶段
│  (预选)          │
└────────┬─────────┘
         │
         ├─► PodFitsResources (检查资源是否充足)
         ├─► PodFitsHostPorts (检查端口冲突)
         ├─► NodeSelector (检查节点标签)
         ├─► NodeAffinity (检查节点亲和性)
         └─► TaintToleration (检查污点容忍)
         │
         ▼
    可调度节点列表: [Node1, Node2, Node5]
         │
         ▼
┌──────────────────┐
│ 2. Scoring       │  打分阶段
│  (优选)          │
└────────┬─────────┘
         │
         ├─► LeastRequestedPriority (资源使用率低的优先)
         ├─► BalancedResourceAllocation (CPU/内存均衡)
         ├─► NodeAffinityPriority (节点亲和性得分)
         └─► InterPodAffinityPriority (Pod亲和性得分)
         │
         ▼
    节点得分: Node1(85) Node2(92) Node5(78)
         │
         ▼
    选择 Node2 (最高分)
         │
         ▼
┌──────────────────┐
│ 3. Binding       │  绑定阶段
│                  │
└──────────────────┘
    更新 Pod.spec.nodeName = "Node2"
```

**自定义调度器示例**:
```go
package main

import (
    "context"
    "fmt"
    "math/rand"

    corev1 "k8s.io/api/core/v1"
    metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
    "k8s.io/client-go/kubernetes"
    "k8s.io/client-go/rest"
)

type CustomScheduler struct {
    clientset *kubernetes.Clientset
}

func NewCustomScheduler() (*CustomScheduler, error) {
    config, err := rest.InClusterConfig()
    if err != nil {
        return nil, err
    }

    clientset, err := kubernetes.NewForConfig(config)
    if err != nil {
        return nil, err
    }

    return &CustomScheduler{clientset: clientset}, nil
}

// 简单的随机调度算法
func (s *CustomScheduler) Schedule(pod *corev1.Pod) (string, error) {
    // 1. 获取所有节点
    nodes, err := s.clientset.CoreV1().Nodes().List(
        context.TODO(),
        metav1.ListOptions{},
    )
    if err != nil {
        return "", err
    }

    // 2. 过滤阶段：移除不可调度的节点
    var availableNodes []corev1.Node
    for _, node := range nodes.Items {
        if !node.Spec.Unschedulable && s.nodeHasEnoughResources(node, pod) {
            availableNodes = append(availableNodes, node)
        }
    }

    if len(availableNodes) == 0 {
        return "", fmt.Errorf("no available nodes")
    }

    // 3. 打分阶段：简单随机选择（实际应该有复杂的评分逻辑）
    selectedNode := availableNodes[rand.Intn(len(availableNodes))]

    return selectedNode.Name, nil
}

func (s *CustomScheduler) nodeHasEnoughResources(
    node corev1.Node,
    pod *corev1.Pod,
) bool {
    // 计算 Pod 的资源需求
    var cpuRequest, memoryRequest int64
    for _, container := range pod.Spec.Containers {
        cpuRequest += container.Resources.Requests.Cpu().MilliValue()
        memoryRequest += container.Resources.Requests.Memory().Value()
    }

    // 获取节点可分配资源
    allocatable := node.Status.Allocatable
    availableCPU := allocatable.Cpu().MilliValue()
    availableMemory := allocatable.Memory().Value()

    return cpuRequest <= availableCPU && memoryRequest <= availableMemory
}

func (s *CustomScheduler) Bind(pod *corev1.Pod, nodeName string) error {
    binding := &corev1.Binding{
        ObjectMeta: metav1.ObjectMeta{
            Name:      pod.Name,
            Namespace: pod.Namespace,
        },
        Target: corev1.ObjectReference{
            Kind: "Node",
            Name: nodeName,
        },
    }

    return s.clientset.CoreV1().Pods(pod.Namespace).Bind(
        context.TODO(),
        binding,
        metav1.CreateOptions{},
    )
}

func (s *CustomScheduler) Run() {
    // 监听未调度的 Pod
    for {
        pods, err := s.clientset.CoreV1().Pods("").List(
            context.TODO(),
            metav1.ListOptions{
                FieldSelector: "spec.nodeName=",  // 未调度的 Pod
            },
        )
        if err != nil {
            fmt.Printf("Error listing pods: %v\n", err)
            continue
        }

        for _, pod := range pods.Items {
            // 只调度指定调度器名称的 Pod
            if pod.Spec.SchedulerName == "custom-scheduler" {
                nodeName, err := s.Schedule(&pod)
                if err != nil {
                    fmt.Printf("Failed to schedule pod %s: %v\n", pod.Name, err)
                    continue
                }

                err = s.Bind(&pod, nodeName)
                if err != nil {
                    fmt.Printf("Failed to bind pod %s to %s: %v\n",
                        pod.Name, nodeName, err)
                    continue
                }

                fmt.Printf("Successfully scheduled pod %s to %s\n",
                    pod.Name, nodeName)
            }
        }
    }
}
```

**使用自定义调度器的 Pod**:
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: custom-scheduled-pod
spec:
  schedulerName: custom-scheduler  # 指定自定义调度器
  containers:
  - name: nginx
    image: nginx:1.21
    resources:
      requests:
        cpu: 100m
        memory: 128Mi
```

##### **Controller Manager**

**职责**:
- 运行各种控制器
- 确保集群状态与期望状态一致

**核心控制器**:

1. **Deployment Controller**
```
期望状态: replicas = 3

当前状态检查:
┌─────────────────────────────────┐
│  ReplicaSet-v1 (旧版本)         │
│  ┌────┐ ┌────┐ ┌────┐          │
│  │Pod1│ │Pod2│ │Pod3│          │
│  └────┘ └────┘ └────┘          │
└─────────────────────────────────┘

滚动更新过程:
┌─────────────────────────────────┐
│  ReplicaSet-v2 (新版本)         │
│  ┌────┐                         │
│  │Pod4│  (创建1个新Pod)        │
│  └────┘                         │
└─────────────────────────────────┘
┌─────────────────────────────────┐
│  ReplicaSet-v1                  │
│  ┌────┐ ┌────┐                 │
│  │Pod2│ │Pod3│ (删除1个旧Pod)  │
│  └────┘ └────┘                 │
└─────────────────────────────────┘

...重复直到全部更新完成...

最终状态:
┌─────────────────────────────────┐
│  ReplicaSet-v2                  │
│  ┌────┐ ┌────┐ ┌────┐          │
│  │Pod4│ │Pod5│ │Pod6│          │
│  └────┘ └────┘ └────┘          │
└─────────────────────────────────┘
```

**Deployment Controller 实现逻辑**:
```go
// 简化的 Deployment Controller 逻辑
func (dc *DeploymentController) syncDeployment(deployment *appsv1.Deployment) error {
    // 1. 获取所有关联的 ReplicaSet
    replicaSets, err := dc.getReplicaSetsForDeployment(deployment)
    if err != nil {
        return err
    }

    // 2. 获取当前活跃的 ReplicaSet
    activeRS := dc.getActiveReplicaSet(replicaSets)

    // 3. 检查是否需要创建新的 ReplicaSet
    if dc.needsNewReplicaSet(deployment, activeRS) {
        newRS, err := dc.createReplicaSet(deployment)
        if err != nil {
            return err
        }
        replicaSets = append(replicaSets, newRS)
    }

    // 4. 执行滚动更新
    return dc.rolloutDeployment(deployment, replicaSets)
}

func (dc *DeploymentController) rolloutDeployment(
    deployment *appsv1.Deployment,
    replicaSets []*appsv1.ReplicaSet,
) error {
    newRS := dc.getNewReplicaSet(replicaSets, deployment)
    oldRSs := dc.getOldReplicaSets(replicaSets, deployment)

    // 计算需要扩容和缩容的副本数
    maxSurge := dc.getMaxSurge(deployment)        // 最多超出期望副本数
    maxUnavailable := dc.getMaxUnavailable(deployment)  // 最多不可用副本数

    // 扩容新 ReplicaSet
    newReplicasCount := calculateNewReplicasCount(
        deployment.Spec.Replicas,
        newRS.Spec.Replicas,
        maxSurge,
    )

    if newRS.Spec.Replicas < newReplicasCount {
        _, err := dc.scaleReplicaSet(newRS, newReplicasCount)
        if err != nil {
            return err
        }
    }

    // 等待新 Pod 就绪...

    // 缩容旧 ReplicaSet
    for _, oldRS := range oldRSs {
        oldReplicasCount := calculateOldReplicasCount(
            deployment.Spec.Replicas,
            oldRS.Spec.Replicas,
            maxUnavailable,
        )

        if oldRS.Spec.Replicas > oldReplicasCount {
            _, err := dc.scaleReplicaSet(oldRS, oldReplicasCount)
            if err != nil {
                return err
            }
        }
    }

    return nil
}
```

2. **Node Controller**
```go
// Node Controller 监控节点健康
func (nc *NodeController) monitorNodeHealth() {
    for {
        nodes, _ := nc.listNodes()

        for _, node := range nodes {
            // 检查节点心跳
            lastHeartbeat := nc.getLastHeartbeat(node)
            timeSinceLastHeartbeat := time.Since(lastHeartbeat)

            if timeSinceLastHeartbeat > nc.nodeMonitorGracePeriod {
                // 节点失联，标记为 NotReady
                nc.markNodeAsNotReady(node)

                // 等待 pod 驱逐时间
                if timeSinceLastHeartbeat > nc.podEvictionTimeout {
                    // 驱逐节点上的 Pod
                    nc.evictPodsFromNode(node)
                }
            } else {
                nc.markNodeAsReady(node)
            }
        }

        time.Sleep(nc.nodeMonitorPeriod)
    }
}
```

#### 1.2.2 Node 组件

##### **kubelet**

**职责**:
- 管理 Pod 生命周期
- 上报节点和 Pod 状态
- 执行健康检查

**Pod 生命周期管理**:
```
API Server 分配 Pod 到节点
         │
         ▼
   ┌──────────┐
   │ kubelet  │
   └────┬─────┘
        │
        ├─► 1. 拉取镜像
        │     docker pull nginx:1.21
        │
        ├─► 2. 创建容器
        │     docker create --name nginx ...
        │
        ├─► 3. 启动容器
        │     docker start nginx
        │
        ├─► 4. 健康检查
        │     - Liveness Probe (存活探针)
        │     - Readiness Probe (就绪探针)
        │     - Startup Probe (启动探针)
        │
        ├─► 5. 日志收集
        │     收集容器输出
        │
        └─► 6. 资源监控
              上报 CPU/内存使用情况
```

**健康检查配置示例**:
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: health-check-demo
spec:
  containers:
  - name: app
    image: myapp:1.0
    ports:
    - containerPort: 8080

    # 启动探针：容器启动时检查
    startupProbe:
      httpGet:
        path: /healthz
        port: 8080
      failureThreshold: 30  # 失败30次才认为启动失败
      periodSeconds: 10     # 每10秒检查一次

    # 存活探针：容器运行时检查
    livenessProbe:
      httpGet:
        path: /healthz
        port: 8080
        httpHeaders:
        - name: X-Custom-Header
          value: Awesome
      initialDelaySeconds: 15  # 启动后15秒开始检查
      periodSeconds: 10        # 每10秒检查一次
      timeoutSeconds: 1        # 超时时间1秒
      failureThreshold: 3      # 连续失败3次重启容器

    # 就绪探针：流量是否可以进入
    readinessProbe:
      exec:
        command:
        - cat
        - /tmp/healthy
      initialDelaySeconds: 5
      periodSeconds: 5
      successThreshold: 1      # 成功1次就认为就绪
      failureThreshold: 3      # 失败3次移出服务端点

    resources:
      requests:
        cpu: 100m
        memory: 128Mi
      limits:
        cpu: 500m
        memory: 512Mi
```

##### **kube-proxy**

**职责**:
- 实现 Service 的网络代理
- 维护网络规则
- 负载均衡

**Service 代理模式**:

1. **iptables 模式** (默认):
```
Service: web-service (ClusterIP: 10.96.0.10:80)
Endpoints:
  - 192.168.1.5:8080
  - 192.168.1.6:8080
  - 192.168.1.7:8080

kube-proxy 生成的 iptables 规则:

# 1. 拦截发往 Service ClusterIP 的流量
-A KUBE-SERVICES -d 10.96.0.10/32 -p tcp -m tcp --dport 80 \
   -j KUBE-SVC-XXXX

# 2. 负载均衡到 Endpoints (随机1/3概率到每个端点)
-A KUBE-SVC-XXXX -m statistic --mode random --probability 0.33333 \
   -j KUBE-SEP-EP1
-A KUBE-SVC-XXXX -m statistic --mode random --probability 0.50000 \
   -j KUBE-SEP-EP2
-A KUBE-SVC-XXXX -j KUBE-SEP-EP3

# 3. DNAT 到实际 Pod IP
-A KUBE-SEP-EP1 -p tcp -m tcp \
   -j DNAT --to-destination 192.168.1.5:8080
-A KUBE-SEP-EP2 -p tcp -m tcp \
   -j DNAT --to-destination 192.168.1.6:8080
-A KUBE-SEP-EP3 -p tcp -m tcp \
   -j DNAT --to-destination 192.168.1.7:8080
```

**请求流程**:
```
客户端 Pod (192.168.1.100)
   │
   │ 请求: curl http://web-service
   │ DNS 解析: web-service -> 10.96.0.10
   │
   ▼
发送请求到 10.96.0.10:80
   │
   ▼
iptables 规则匹配
   │
   ├─► 33% 概率 -> DNAT 到 192.168.1.5:8080
   ├─► 33% 概率 -> DNAT 到 192.168.1.6:8080
   └─► 34% 概率 -> DNAT 到 192.168.1.7:8080
        │
        ▼
    到达 Pod
```

2. **IPVS 模式** (高性能):
```bash
# 查看 IPVS 规则
ipvsadm -Ln

# 输出示例:
IP Virtual Server version 1.2.1 (size=4096)
Prot LocalAddress:Port Scheduler Flags
  -> RemoteAddress:Port           Forward Weight ActiveConn InActConn
TCP  10.96.0.10:80 rr
  -> 192.168.1.5:8080             Masq    1      0          0
  -> 192.168.1.6:8080             Masq    1      0          0
  -> 192.168.1.7:8080             Masq    1      0          0
```

**IPVS 优势**:
- 支持更多负载均衡算法 (rr, lc, dh, sh 等)
- 更好的性能 (O(1) vs O(n))
- 支持更大规模的服务

---

## 第二部分：GPU 资源调度与共享

### 2.1 GPU 调度基础

Kubernetes 通过 Device Plugin 框架支持 GPU 等硬件加速器。

**GPU 节点架构**:
```
┌─────────────────────────────────────────┐
│           Worker Node (GPU)             │
│                                          │
│  ┌────────────────────────────────────┐ │
│  │         kubelet                    │ │
│  │  ┌──────────────────────────────┐  │ │
│  │  │   Device Plugin Manager      │  │ │
│  │  └──────────┬───────────────────┘  │ │
│  │             │                       │ │
│  │             ▼                       │ │
│  │  ┌──────────────────────────────┐  │ │
│  │  │  NVIDIA Device Plugin        │  │ │
│  │  │  - 发现 GPU                  │  │ │
│  │  │  - 上报 GPU 数量             │  │ │
│  │  │  - 分配 GPU 给 Pod           │  │ │
│  │  └──────────┬───────────────────┘  │ │
│  └─────────────┼──────────────────────┘ │
│                │                         │
│  ┌─────────────▼──────────────────────┐ │
│  │    Container Runtime (Docker)      │ │
│  │  ┌──────────────────────────────┐  │ │
│  │  │  NVIDIA Container Runtime    │  │ │
│  │  │  (nvidia-docker)             │  │ │
│  │  └──────────┬───────────────────┘  │ │
│  └─────────────┼──────────────────────┘ │
│                │                         │
│  ┌─────────────▼──────────────────────┐ │
│  │        GPU Driver                  │ │
│  └─────────────┬──────────────────────┘ │
│                │                         │
│  ┌─────────────▼──────────────────────┐ │
│  │   物理 GPU (NVIDIA A100 x4)        │ │
│  │   ┌──────┐ ┌──────┐ ┌──────┐ ...  │ │
│  │   │GPU 0 │ │GPU 1 │ │GPU 2 │      │ │
│  │   └──────┘ └──────┘ └──────┘      │ │
│  └────────────────────────────────────┘ │
└─────────────────────────────────────────┘
```

### 2.2 NVIDIA GPU Operator

NVIDIA GPU Operator 自动化 GPU 节点的配置和管理。

**安装 GPU Operator**:
```bash
# 添加 NVIDIA Helm 仓库
helm repo add nvidia https://helm.ngc.nvidia.com/nvidia
helm repo update

# 安装 GPU Operator
helm install gpu-operator nvidia/gpu-operator \
  --namespace gpu-operator \
  --create-namespace \
  --set driver.enabled=true \
  --set toolkit.enabled=true \
  --set devicePlugin.enabled=true \
  --set dcgmExporter.enabled=true \
  --set gfd.enabled=true
```

**GPU Operator 部署的组件**:
```
gpu-operator namespace:
├── nvidia-driver-daemonset        # GPU 驱动
├── nvidia-container-toolkit-ds    # 容器工具包
├── nvidia-device-plugin-ds        # Device Plugin
├── gpu-feature-discovery-ds       # GPU 特性发现
└── nvidia-dcgm-exporter-ds        # GPU 监控指标
```

**验证 GPU 可用性**:
```bash
# 查看节点 GPU 资源
kubectl describe node gpu-node-1

# 输出示例:
Capacity:
  cpu:                64
  memory:             256Gi
  nvidia.com/gpu:     4      # 4 块 GPU
  pods:               110

Allocatable:
  cpu:                64
  memory:             256Gi
  nvidia.com/gpu:     4
  pods:               110
```

### 2.3 GPU Pod 调度

**请求 GPU 资源的 Pod**:
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: gpu-pod
spec:
  containers:
  - name: cuda-container
    image: nvidia/cuda:11.0-base
    command: ["nvidia-smi"]
    resources:
      limits:
        nvidia.com/gpu: 1  # 请求 1 块 GPU
```

**多 GPU Pod**:
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: multi-gpu-pod
spec:
  containers:
  - name: training
    image: tensorflow/tensorflow:latest-gpu
    command: ["python", "train.py"]
    resources:
      limits:
        nvidia.com/gpu: 4  # 请求 4 块 GPU
    env:
    - name: NVIDIA_VISIBLE_DEVICES
      value: "0,1,2,3"  # 指定使用的 GPU
```

### 2.4 GPU 共享与虚拟化

#### 2.4.1 时间片共享 (Time-Slicing)

允许多个 Pod 共享同一块 GPU。

**配置 GPU 时间片**:
```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: gpu-sharing-config
  namespace: gpu-operator
data:
  any: |-
    version: v1
    sharing:
      timeSlicing:
        replicas: 4  # 将每块 GPU 虚拟为 4 个
```

**应用配置**:
```bash
# 更新 GPU Operator
helm upgrade gpu-operator nvidia/gpu-operator \
  --set devicePlugin.config.name=gpu-sharing-config
```

**共享 GPU 的 Pod**:
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: shared-gpu-pod-1
spec:
  containers:
  - name: app
    image: nvidia/cuda:11.0-base
    command: ["nvidia-smi", "-L"]
    resources:
      limits:
        nvidia.com/gpu: 1  # 实际分配 1/4 块物理 GPU
---
apiVersion: v1
kind: Pod
metadata:
  name: shared-gpu-pod-2
spec:
  containers:
  - name: app
    image: nvidia/cuda:11.0-base
    command: ["sleep", "3600"]
    resources:
      limits:
        nvidia.com/gpu: 1  # 与上面的 Pod 共享
```

**时间片调度示意**:
```
物理 GPU 0:
┌───────────────────────────────────────┐
│  时间片轮转                           │
│  ┌───┐ ┌───┐ ┌───┐ ┌───┐ ┌───┐ ...  │
│  │P1 │ │P2 │ │P3 │ │P4 │ │P1 │      │
│  └───┘ └───┘ └───┘ └───┘ └───┘      │
│   ^     ^     ^     ^                │
│   │     │     │     └─ Pod 4         │
│   │     │     └─ Pod 3               │
│   │     └─ Pod 2                     │
│   └─ Pod 1                           │
└───────────────────────────────────────┘
```

#### 2.4.2 MIG (Multi-Instance GPU)

NVIDIA A100/A30 支持将一块 GPU 分割为多个独立实例。

**MIG 分区示例**:
```
NVIDIA A100 (40GB):
┌─────────────────────────────────────┐
│                                     │
│  ┌───────────┐ ┌──────┐ ┌─────┐   │
│  │ MIG 1     │ │MIG 2 │ │MIG 3│   │
│  │ 20GB      │ │10GB  │ │10GB │   │
│  │ 3g.20gb   │ │2g.10gb│2g.10gb   │
│  └───────────┘ └──────┘ └─────┘   │
│                                     │
└─────────────────────────────────────┘
```

**创建 MIG 实例**:
```bash
# 启用 MIG 模式
nvidia-smi -i 0 -mig 1

# 创建 GPU 实例
nvidia-smi mig -cgi 9,14,19 -C

# 查看 MIG 设备
nvidia-smi -L

# 输出:
GPU 0: NVIDIA A100 (UUID: GPU-xxx)
  MIG 3g.20gb Device 0: (UUID: MIG-GPU-xxx)
  MIG 2g.10gb Device 1: (UUID: MIG-GPU-yyy)
  MIG 2g.10gb Device 2: (UUID: MIG-GPU-zzz)
```

**使用 MIG 的 Pod**:
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: mig-pod
spec:
  containers:
  - name: cuda-app
    image: nvidia/cuda:11.0-base
    resources:
      limits:
        nvidia.com/mig-3g.20gb: 1  # 请求特定 MIG 配置
```

#### 2.4.3 vGPU (虚拟 GPU)

NVIDIA vGPU 软件允许 GPU 虚拟化。

**vGPU 架构**:
```
宿主机 (Host):
┌─────────────────────────────────────────┐
│  NVIDIA vGPU Manager                    │
│  ┌───────────────────────────────────┐  │
│  │    物理 GPU (A100)                │  │
│  │  ┌──────┐ ┌──────┐ ┌──────┐      │  │
│  │  │vGPU 1│ │vGPU 2│ │vGPU 3│      │  │
│  │  │ 8GB  │ │ 8GB  │ │ 8GB  │      │  │
│  │  └──┬───┘ └──┬───┘ └──┬───┘      │  │
│  └─────┼────────┼────────┼───────────┘  │
└────────┼────────┼────────┼──────────────┘
         │        │        │
    ┌────▼───┐ ┌──▼────┐ ┌▼─────┐
    │ VM 1   │ │ VM 2  │ │ VM 3 │
    │ (Pod)  │ │ (Pod) │ │ (Pod)│
    └────────┘ └───────┘ └──────┘
```

### 2.5 GPU 拓扑感知调度

对于多 GPU 训练，GPU 之间的通信拓扑很重要。

**GPU 拓扑示例**:
```bash
nvidia-smi topo -m

# 输出 (简化):
        GPU0    GPU1    GPU2    GPU3    NIC0
GPU0     X      NV12    NV12    NV12    NODE
GPU1    NV12     X      NV12    NV12    NODE
GPU2    NV12    NV12     X      NV12    SYS
GPU3    NV12    NV12    NV12     X      SYS

# NV12 = NVLink 12 lanes (高速互联)
# NODE = 同一 NUMA 节点
# SYS  = 跨 NUMA 节点 (较慢)
```

**拓扑感知 Pod 调度**:
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: distributed-training
spec:
  # 使用 GPU 拓扑调度插件
  schedulerName: gpu-topology-scheduler
  containers:
  - name: trainer
    image: pytorch/pytorch:1.9.0-cuda11.1
    command: ["python", "-m", "torch.distributed.launch", "train.py"]
    resources:
      limits:
        nvidia.com/gpu: 4
    env:
    - name: NCCL_TOPOLOGY
      value: "NVLINK"  # 要求 NVLink 连接
```

---

## 第三部分：多租户隔离

### 3.1 命名空间隔离

Namespace 是 Kubernetes 的基本隔离单元。

**创建租户命名空间**:
```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: tenant-a
  labels:
    tenant: tenant-a
---
apiVersion: v1
kind: Namespace
metadata:
  name: tenant-b
  labels:
    tenant: tenant-b
```

### 3.2 资源配额 (ResourceQuota)

限制每个租户可使用的资源总量。

```yaml
apiVersion: v1
kind: ResourceQuota
metadata:
  name: tenant-a-quota
  namespace: tenant-a
spec:
  hard:
    # 计算资源
    requests.cpu: "100"          # 总共可请求 100 核 CPU
    requests.memory: 200Gi       # 总共可请求 200GB 内存
    requests.nvidia.com/gpu: "4" # 总共可请求 4 块 GPU
    limits.cpu: "200"
    limits.memory: 400Gi
    limits.nvidia.com/gpu: "4"

    # 对象数量
    pods: "100"                  # 最多 100 个 Pod
    services: "50"               # 最多 50 个 Service
    persistentvolumeclaims: "20" # 最多 20 个 PVC
    secrets: "100"
    configmaps: "100"

    # 存储资源
    requests.storage: 1Ti        # 总共可请求 1TB 存储
```

**LimitRange - 设置默认资源限制**:
```yaml
apiVersion: v1
kind: LimitRange
metadata:
  name: tenant-a-limits
  namespace: tenant-a
spec:
  limits:
  # Pod 级别限制
  - type: Pod
    max:
      cpu: "16"
      memory: 32Gi
    min:
      cpu: 100m
      memory: 128Mi

  # 容器级别限制
  - type: Container
    max:
      cpu: "8"
      memory: 16Gi
      nvidia.com/gpu: "1"
    min:
      cpu: 100m
      memory: 128Mi
    default:  # 未指定时的默认 limits
      cpu: "1"
      memory: 1Gi
    defaultRequest:  # 未指定时的默认 requests
      cpu: 500m
      memory: 512Mi

  # PVC 限制
  - type: PersistentVolumeClaim
    max:
      storage: 100Gi
    min:
      storage: 1Gi
```

### 3.3 网络隔离 (NetworkPolicy)

控制 Pod 之间的网络流量。

**默认拒绝所有流量**:
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
  namespace: tenant-a
spec:
  podSelector: {}  # 匹配所有 Pod
  policyTypes:
  - Ingress
  - Egress
```

**允许同租户内部通信**:
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-same-namespace
  namespace: tenant-a
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress
  ingress:
  - from:
    - podSelector: {}  # 同命名空间的 Pod
  egress:
  - to:
    - podSelector: {}
```

**允许特定服务访问**:
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-frontend-to-backend
  namespace: tenant-a
spec:
  podSelector:
    matchLabels:
      app: backend  # 后端 Pod
  policyTypes:
  - Ingress
  ingress:
  - from:
    - podSelector:
        matchLabels:
          app: frontend  # 只允许前端访问
    ports:
    - protocol: TCP
      port: 8080
```

**允许访问外部服务**:
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-external-egress
  namespace: tenant-a
spec:
  podSelector:
    matchLabels:
      app: web
  policyTypes:
  - Egress
  egress:
  # 允许 DNS 查询
  - to:
    - namespaceSelector:
        matchLabels:
          name: kube-system
    - podSelector:
        matchLabels:
          k8s-app: kube-dns
    ports:
    - protocol: UDP
      port: 53

  # 允许访问特定外部 IP
  - to:
    - ipBlock:
        cidr: 0.0.0.0/0
        except:
        - 169.254.169.254/32  # 排除元数据服务
    ports:
    - protocol: TCP
      port: 443
```

### 3.4 RBAC 权限隔离

基于角色的访问控制。

**租户管理员角色**:
```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: tenant-admin
  namespace: tenant-a
rules:
# 完全控制 Pod
- apiGroups: [""]
  resources: ["pods", "pods/log", "pods/exec"]
  verbs: ["*"]

# 完全控制 Deployment
- apiGroups: ["apps"]
  resources: ["deployments", "replicasets", "statefulsets"]
  verbs: ["*"]

# 完全控制 Service
- apiGroups: [""]
  resources: ["services", "endpoints"]
  verbs: ["*"]

# 只读 ResourceQuota
- apiGroups: [""]
  resources: ["resourcequotas"]
  verbs: ["get", "list"]

# 禁止修改 NetworkPolicy
- apiGroups: ["networking.k8s.io"]
  resources: ["networkpolicies"]
  verbs: ["get", "list"]
```

**绑定角色到用户**:
```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: tenant-a-admin-binding
  namespace: tenant-a
subjects:
- kind: User
  name: alice@example.com  # 租户 A 的管理员
  apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: Role
  name: tenant-admin
  apiGroup: rbac.authorization.k8s.io
```

**租户开发者角色** (受限权限):
```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: tenant-developer
  namespace: tenant-a
rules:
# 可以查看和创建 Pod，但不能删除
- apiGroups: [""]
  resources: ["pods"]
  verbs: ["get", "list", "create"]

# 可以查看日志
- apiGroups: [""]
  resources: ["pods/log"]
  verbs: ["get", "list"]

# 可以管理 Deployment (但会受 ResourceQuota 限制)
- apiGroups: ["apps"]
  resources: ["deployments"]
  verbs: ["get", "list", "create", "update", "patch"]

# 只读其他资源
- apiGroups: [""]
  resources: ["services", "configmaps", "secrets"]
  verbs: ["get", "list"]
```

### 3.5 Pod Security Standards

限制 Pod 的安全配置。

**Baseline Policy (基线策略)**:
```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: tenant-a
  labels:
    pod-security.kubernetes.io/enforce: baseline
    pod-security.kubernetes.io/audit: restricted
    pod-security.kubernetes.io/warn: restricted
```

**Restricted Policy - PodSecurityPolicy 示例**:
```yaml
apiVersion: policy/v1beta1
kind: PodSecurityPolicy
metadata:
  name: restricted
spec:
  privileged: false  # 禁止特权容器
  allowPrivilegeEscalation: false
  requiredDropCapabilities:
  - ALL
  volumes:
  - 'configMap'
  - 'emptyDir'
  - 'projected'
  - 'secret'
  - 'downwardAPI'
  - 'persistentVolumeClaim'
  hostNetwork: false  # 禁止使用主机网络
  hostIPC: false
  hostPID: false
  runAsUser:
    rule: 'MustRunAsNonRoot'  # 必须以非 root 运行
  seLinux:
    rule: 'RunAsAny'
  supplementalGroups:
    rule: 'RunAsAny'
  fsGroup:
    rule: 'RunAsAny'
  readOnlyRootFilesystem: false
```

### 3.6 多租户调度

**节点池隔离 - 使用污点和容忍**:
```bash
# 为租户 A 保留节点
kubectl taint nodes node-1 node-2 node-3 \
  tenant=tenant-a:NoSchedule
```

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: tenant-a-pod
  namespace: tenant-a
spec:
  # 只有带此容忍的 Pod 才能调度到租户 A 的节点
  tolerations:
  - key: "tenant"
    operator: "Equal"
    value: "tenant-a"
    effect: "NoSchedule"

  # 确保只调度到租户 A 的节点
  nodeSelector:
    tenant: tenant-a

  containers:
  - name: app
    image: myapp:1.0
```

**使用节点亲和性实现软隔离**:
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: tenant-b-pod
spec:
  affinity:
    nodeAffinity:
      # 优先选择租户 B 的节点
      preferredDuringSchedulingIgnoredDuringExecution:
      - weight: 100
        preference:
          matchExpressions:
          - key: tenant
            operator: In
            values:
            - tenant-b

      # 禁止调度到租户 A 的节点
      requiredDuringSchedulingIgnoredDuringExecution:
        nodeSelectorTerms:
        - matchExpressions:
          - key: tenant
            operator: NotIn
            values:
            - tenant-a

  containers:
  - name: app
    image: myapp:1.0
```

---

## 第四部分：Helm Charts 与 GitOps

### 4.1 Helm 基础

Helm 是 Kubernetes 的包管理器。

**Helm Chart 结构**:
```
my-app/
├── Chart.yaml          # Chart 元数据
├── values.yaml         # 默认配置值
├── charts/             # 依赖的子 Chart
├── templates/          # Kubernetes 资源模板
│   ├── deployment.yaml
│   ├── service.yaml
│   ├── ingress.yaml
│   ├── _helpers.tpl   # 模板辅助函数
│   └── NOTES.txt      # 安装后的提示信息
└── .helmignore         # 忽略的文件
```

**Chart.yaml**:
```yaml
apiVersion: v2
name: my-app
description: A Helm chart for my application
type: application
version: 1.0.0      # Chart 版本
appVersion: "2.1.0" # 应用版本

dependencies:
- name: postgresql
  version: 10.x.x
  repository: https://charts.bitnami.com/bitnami
  condition: postgresql.enabled

- name: redis
  version: 15.x.x
  repository: https://charts.bitnami.com/bitnami
  condition: redis.enabled
```

**values.yaml**:
```yaml
# 默认配置值
replicaCount: 3

image:
  repository: myapp
  pullPolicy: IfNotPresent
  tag: ""  # 默认使用 appVersion

service:
  type: ClusterIP
  port: 80
  targetPort: 8080

ingress:
  enabled: false
  className: nginx
  annotations: {}
  hosts:
    - host: myapp.example.com
      paths:
        - path: /
          pathType: Prefix
  tls: []

resources:
  limits:
    cpu: 1000m
    memory: 1Gi
  requests:
    cpu: 500m
    memory: 512Mi

autoscaling:
  enabled: false
  minReplicas: 2
  maxReplicas: 10
  targetCPUUtilizationPercentage: 80

postgresql:
  enabled: true
  auth:
    username: myapp
    password: secret
    database: myapp_db

redis:
  enabled: true
  auth:
    enabled: false
```

**templates/deployment.yaml**:
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ include "my-app.fullname" . }}
  labels:
    {{- include "my-app.labels" . | nindent 4 }}
spec:
  {{- if not .Values.autoscaling.enabled }}
  replicas: {{ .Values.replicaCount }}
  {{- end }}
  selector:
    matchLabels:
      {{- include "my-app.selectorLabels" . | nindent 6 }}
  template:
    metadata:
      labels:
        {{- include "my-app.selectorLabels" . | nindent 8 }}
    spec:
      containers:
      - name: {{ .Chart.Name }}
        image: "{{ .Values.image.repository }}:{{ .Values.image.tag | default .Chart.AppVersion }}"
        imagePullPolicy: {{ .Values.image.pullPolicy }}
        ports:
        - name: http
          containerPort: {{ .Values.service.targetPort }}
          protocol: TCP
        livenessProbe:
          httpGet:
            path: /healthz
            port: http
          initialDelaySeconds: 30
        readinessProbe:
          httpGet:
            path: /ready
            port: http
          initialDelaySeconds: 5
        resources:
          {{- toYaml .Values.resources | nindent 10 }}
        env:
        {{- if .Values.postgresql.enabled }}
        - name: DATABASE_URL
          value: "postgresql://{{ .Values.postgresql.auth.username }}:{{ .Values.postgresql.auth.password }}@{{ include "my-app.fullname" . }}-postgresql:5432/{{ .Values.postgresql.auth.database }}"
        {{- end }}
        {{- if .Values.redis.enabled }}
        - name: REDIS_URL
          value: "redis://{{ include "my-app.fullname" . }}-redis-master:6379"
        {{- end }}
```

**templates/_helpers.tpl**:
```yaml
{{/*
生成 Chart 的完整名称
*/}}
{{- define "my-app.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
通用标签
*/}}
{{- define "my-app.labels" -}}
helm.sh/chart: {{ include "my-app.chart" . }}
{{ include "my-app.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
选择器标签
*/}}
{{- define "my-app.selectorLabels" -}}
app.kubernetes.io/name: {{ include "my-app.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}
```

### 4.2 Helm 高级特性

#### 条件和循环

```yaml
# templates/configmap.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: {{ include "my-app.fullname" . }}-config
data:
  {{- range $key, $value := .Values.config }}
  {{ $key }}: {{ $value | quote }}
  {{- end }}

  {{- if .Values.feature.enabled }}
  feature-flag: "true"
  {{- end }}
```

#### Hooks

在安装/升级的特定阶段执行任务。

```yaml
# templates/db-migration-job.yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: {{ include "my-app.fullname" . }}-db-migration
  annotations:
    "helm.sh/hook": pre-upgrade  # 升级前执行
    "helm.sh/hook-weight": "-5"  # 权重(执行顺序)
    "helm.sh/hook-delete-policy": hook-succeeded  # 成功后删除
spec:
  template:
    spec:
      restartPolicy: Never
      containers:
      - name: migration
        image: "{{ .Values.image.repository }}:{{ .Values.image.tag }}"
        command: ["./migrate.sh"]
        env:
        - name: DATABASE_URL
          value: "{{ .Values.database.url }}"
```

**Hook 类型**:
- `pre-install`: 安装前
- `post-install`: 安装后
- `pre-upgrade`: 升级前
- `post-upgrade`: 升级后
- `pre-delete`: 删除前
- `post-delete`: 删除后
- `pre-rollback`: 回滚前
- `post-rollback`: 回滚后

### 4.3 Helm 命令实战

```bash
# 创建新 Chart
helm create my-app

# 验证 Chart
helm lint my-app/

# 渲染模板（不安装）
helm template my-app ./my-app \
  --values custom-values.yaml \
  --set replicaCount=5

# 安装 Chart
helm install my-release ./my-app \
  --namespace prod \
  --create-namespace \
  --values prod-values.yaml \
  --set image.tag=v1.2.3

# 升级 Release
helm upgrade my-release ./my-app \
  --values prod-values.yaml \
  --set image.tag=v1.2.4 \
  --reuse-values  # 保留之前的值

# 回滚
helm rollback my-release 3  # 回滚到版本 3

# 查看历史
helm history my-release

# 卸载
helm uninstall my-release --namespace prod

# 打包 Chart
helm package my-app/ --destination ./charts/

# 推送到仓库
helm push my-app-1.0.0.tgz oci://registry.example.com/charts
```

### 4.4 GitOps 与 ArgoCD

GitOps 使用 Git 作为单一事实来源，自动部署应用。

**GitOps 工作流**:
```
┌─────────────┐
│ Developer   │
│             │
│ 1. git push │
└──────┬──────┘
       │
       ▼
┌─────────────────────┐
│   Git Repository    │
│  ┌───────────────┐  │
│  │ manifests/    │  │
│  │ - app.yaml    │  │
│  │ - service.yaml│  │
│  └───────────────┘  │
└──────┬──────────────┘
       │
       │ 2. ArgoCD 监听
       │
       ▼
┌─────────────────────┐
│     ArgoCD          │
│                     │
│ 3. 检测到变化       │
│ 4. 同步到集群       │
└──────┬──────────────┘
       │
       ▼
┌─────────────────────┐
│ Kubernetes Cluster  │
│  ┌───┐ ┌───┐ ┌───┐ │
│  │Pod│ │Pod│ │Pod│ │
│  └───┘ └───┘ └───┘ │
└─────────────────────┘
```

**安装 ArgoCD**:
```bash
# 创建命名空间
kubectl create namespace argocd

# 安装 ArgoCD
kubectl apply -n argocd -f \
  https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# 获取初始密码
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d

# 暴露 ArgoCD UI
kubectl port-forward svc/argocd-server -n argocd 8080:443
```

**创建 ArgoCD Application**:
```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: my-app
  namespace: argocd
spec:
  project: default

  # Git 仓库配置
  source:
    repoURL: https://github.com/myorg/myapp.git
    targetRevision: main
    path: k8s/overlays/production  # Kustomize 或 Helm path

    # 如果是 Helm Chart
    helm:
      valueFiles:
      - values-prod.yaml
      parameters:
      - name: image.tag
        value: v1.2.3
      - name: replicaCount
        value: "5"

  # 目标集群和命名空间
  destination:
    server: https://kubernetes.default.svc
    namespace: production

  # 同步策略
  syncPolicy:
    automated:
      prune: true      # 自动删除 Git 中不存在的资源
      selfHeal: true   # 自动修复漂移(drift)
      allowEmpty: false
    syncOptions:
    - CreateNamespace=true
    retry:
      limit: 5
      backoff:
        duration: 5s
        factor: 2
        maxDuration: 3m
```

**使用 Kustomize 的示例**:
```
my-app/
├── base/
│   ├── kustomization.yaml
│   ├── deployment.yaml
│   └── service.yaml
└── overlays/
    ├── development/
    │   ├── kustomization.yaml
    │   └── patch-replicas.yaml
    └── production/
        ├── kustomization.yaml
        ├── patch-replicas.yaml
        └── patch-resources.yaml
```

**base/kustomization.yaml**:
```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
- deployment.yaml
- service.yaml

commonLabels:
  app: my-app
```

**overlays/production/kustomization.yaml**:
```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

bases:
- ../../base

namespace: production

replicas:
- name: my-app
  count: 5

images:
- name: my-app
  newTag: v1.2.3

patches:
- path: patch-resources.yaml
```

**overlays/production/patch-resources.yaml**:
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-app
spec:
  template:
    spec:
      containers:
      - name: my-app
        resources:
          requests:
            cpu: 1000m
            memory: 2Gi
          limits:
            cpu: 2000m
            memory: 4Gi
```

### 4.5 GitOps 最佳实践

**1. 环境分离**:
```
git-repo/
├── apps/
│   └── my-app/
│       ├── base/
│       └── overlays/
│           ├── dev/
│           ├── staging/
│           └── prod/
└── infrastructure/
    ├── base/
    └── overlays/
        ├── cluster-1/
        └── cluster-2/
```

**2. 应用分层管理**:
```yaml
# Application of Applications 模式
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: root-app
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/myorg/k8s-apps.git
    targetRevision: main
    path: apps/production
  destination:
    server: https://kubernetes.default.svc
    namespace: argocd
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

**apps/production/kustomization.yaml**:
```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
- app-1.yaml
- app-2.yaml
- app-3.yaml
```

**3. 机密管理**:
```yaml
# 使用 Sealed Secrets
apiVersion: bitnami.com/v1alpha1
kind: SealedSecret
metadata:
  name: db-credentials
  namespace: production
spec:
  encryptedData:
    password: AgBvYW1...  # 加密后的密码
    username: AgCdfs...  # 加密后的用户名
```

```bash
# 创建 Sealed Secret
kubectl create secret generic db-credentials \
  --from-literal=username=admin \
  --from-literal=password=secret123 \
  --dry-run=client -o yaml | \
kubeseal -o yaml > sealed-secret.yaml

# 提交加密后的 sealed-secret.yaml 到 Git
git add sealed-secret.yaml
git commit -m "Add database credentials"
git push
```

**4. Progressive Delivery (渐进式交付)**:
```yaml
# 使用 Argo Rollouts 实现金丝雀发布
apiVersion: argoproj.io/v1alpha1
kind: Rollout
metadata:
  name: my-app
spec:
  replicas: 10
  strategy:
    canary:
      steps:
      - setWeight: 10   # 10% 流量到新版本
      - pause: {duration: 5m}  # 暂停 5 分钟观察
      - setWeight: 30
      - pause: {duration: 5m}
      - setWeight: 50
      - pause: {duration: 10m}
      - setWeight: 100  # 全部流量到新版本

      # 金丝雀分析
      analysis:
        templates:
        - templateName: success-rate
        startingStep: 2
        args:
        - name: service-name
          value: my-app

  template:
    metadata:
      labels:
        app: my-app
    spec:
      containers:
      - name: my-app
        image: myapp:v2.0
```

**AnalysisTemplate - 自动化金丝雀分析**:
```yaml
apiVersion: argoproj.io/v1alpha1
kind: AnalysisTemplate
metadata:
  name: success-rate
spec:
  args:
  - name: service-name
  metrics:
  - name: success-rate
    interval: 1m
    successCondition: result[0] >= 0.95  # 成功率 >= 95%
    failureLimit: 3  # 失败 3 次回滚
    provider:
      prometheus:
        address: http://prometheus:9090
        query: |
          sum(rate(
            http_requests_total{
              service="{{ args.service-name }}",
              status!~"5.."
            }[1m]
          )) /
          sum(rate(
            http_requests_total{
              service="{{ args.service-name }}"
            }[1m]
          ))
```

---

## 第五部分：高级主题与最佳实践

### 5.1 自定义资源 (CRD)

扩展 Kubernetes API。

**定义 CRD**:
```yaml
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata:
  name: gpujobs.ml.example.com
spec:
  group: ml.example.com
  versions:
  - name: v1
    served: true
    storage: true
    schema:
      openAPIV3Schema:
        type: object
        properties:
          spec:
            type: object
            properties:
              image:
                type: string
              gpuCount:
                type: integer
                minimum: 1
                maximum: 8
              script:
                type: string
              env:
                type: object
                additionalProperties:
                  type: string
            required:
            - image
            - gpuCount
            - script
          status:
            type: object
            properties:
              phase:
                type: string
              startTime:
                type: string
                format: date-time
              completionTime:
                type: string
                format: date-time
    additionalPrinterColumns:
    - name: GPU
      type: integer
      jsonPath: .spec.gpuCount
    - name: Status
      type: string
      jsonPath: .status.phase
    - name: Age
      type: date
      jsonPath: .metadata.creationTimestamp
  scope: Namespaced
  names:
    plural: gpujobs
    singular: gpujob
    kind: GPUJob
    shortNames:
    - gj
```

**使用自定义资源**:
```yaml
apiVersion: ml.example.com/v1
kind: GPUJob
metadata:
  name: training-job
spec:
  image: pytorch/pytorch:1.9.0-cuda11.1
  gpuCount: 4
  script: |
    python train.py \
      --model resnet50 \
      --epochs 100 \
      --batch-size 256
  env:
    DATA_PATH: /data/imagenet
    OUTPUT_PATH: /output/models
```

### 5.2 Operator 模式

**Operator = CRD + Controller**

```go
// 简化的 Operator Controller 逻辑
package controller

import (
    mlv1 "example.com/gpu-operator/api/v1"
    corev1 "k8s.io/api/core/v1"
    batchv1 "k8s.io/api/batch/v1"
)

func (r *GPUJobReconciler) Reconcile(ctx context.Context, req ctrl.Request) (ctrl.Result, error) {
    // 1. 获取 GPUJob 资源
    gpuJob := &mlv1.GPUJob{}
    err := r.Get(ctx, req.NamespacedName, gpuJob)
    if err != nil {
        return ctrl.Result{}, err
    }

    // 2. 检查是否已创建 Job
    job := &batchv1.Job{}
    err = r.Get(ctx, types.NamespacedName{
        Name:      gpuJob.Name,
        Namespace: gpuJob.Namespace,
    }, job)

    if err != nil && errors.IsNotFound(err) {
        // 3. 创建 Kubernetes Job
        job = r.constructJobForGPUJob(gpuJob)
        err = r.Create(ctx, job)
        if err != nil {
            return ctrl.Result{}, err
        }

        // 4. 更新状态
        gpuJob.Status.Phase = "Running"
        gpuJob.Status.StartTime = &metav1.Time{Time: time.Now()}
        r.Status().Update(ctx, gpuJob)

        return ctrl.Result{}, nil
    }

    // 5. 监控 Job 状态
    if job.Status.Succeeded > 0 {
        gpuJob.Status.Phase = "Completed"
        gpuJob.Status.CompletionTime = job.Status.CompletionTime
    } else if job.Status.Failed > 0 {
        gpuJob.Status.Phase = "Failed"
    }

    r.Status().Update(ctx, gpuJob)
    return ctrl.Result{}, nil
}

func (r *GPUJobReconciler) constructJobForGPUJob(gpuJob *mlv1.GPUJob) *batchv1.Job {
    return &batchv1.Job{
        ObjectMeta: metav1.ObjectMeta{
            Name:      gpuJob.Name,
            Namespace: gpuJob.Namespace,
            OwnerReferences: []metav1.OwnerReference{
                *metav1.NewControllerRef(gpuJob, mlv1.GroupVersion.WithKind("GPUJob")),
            },
        },
        Spec: batchv1.JobSpec{
            Template: corev1.PodTemplateSpec{
                Spec: corev1.PodSpec{
                    RestartPolicy: corev1.RestartPolicyNever,
                    Containers: []corev1.Container{
                        {
                            Name:    "training",
                            Image:   gpuJob.Spec.Image,
                            Command: []string{"/bin/sh", "-c", gpuJob.Spec.Script},
                            Resources: corev1.ResourceRequirements{
                                Limits: corev1.ResourceList{
                                    "nvidia.com/gpu": resource.MustParse(
                                        fmt.Sprintf("%d", gpuJob.Spec.GPUCount),
                                    ),
                                },
                            },
                            Env: envVarsFromMap(gpuJob.Spec.Env),
                        },
                    },
                },
            },
        },
    }
}
```

### 5.3 集群监控

**Prometheus + Grafana 部署**:
```bash
# 使用 kube-prometheus-stack
helm repo add prometheus-community \
  https://prometheus-community.github.io/helm-charts

helm install kube-prometheus prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --create-namespace \
  --set prometheus.prometheusSpec.retention=30d \
  --set prometheus.prometheusSpec.storageSpec.volumeClaimTemplate.spec.resources.requests.storage=100Gi \
  --set grafana.adminPassword=admin123
```

**自定义 ServiceMonitor**:
```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: my-app-metrics
  namespace: monitoring
spec:
  selector:
    matchLabels:
      app: my-app
  endpoints:
  - port: metrics
    interval: 30s
    path: /metrics
```

---

## 总结与参考资源

### 核心要点

1. **架构理解**: 深入理解 Control Plane 和 Node 组件的职责
2. **GPU 调度**: 掌握 Device Plugin、时间片、MIG 等技术
3. **多租户**: 使用 Namespace、ResourceQuota、NetworkPolicy、RBAC 实现隔离
4. **GitOps**: 使用 Helm + ArgoCD 实现声明式部署
5. **扩展性**: 通过 CRD 和 Operator 扩展 Kubernetes

### 权威资源

- **Kubernetes 官方文档**: https://kubernetes.io/docs/
- **NVIDIA GPU Operator**: https://docs.nvidia.com/datacenter/cloud-native/gpu-operator/
- **Istio 服务网格**: https://istio.io/latest/docs/
- **Helm 文档**: https://helm.sh/docs/
- **ArgoCD 文档**: https://argo-cd.readthedocs.io/
- **CNCF Landscape**: https://landscape.cncf.io/

### 推荐学习路径

1. **第 1-2 周**: Kubernetes 架构与核心概念
2. **第 3 周**: GPU 资源管理
3. **第 4 周**: 多租户隔离实践
4. **第 5-6 周**: Helm Charts 开发
5. **第 7-8 周**: GitOps 与 ArgoCD
6. **第 9-10 周**: 综合项目实践
