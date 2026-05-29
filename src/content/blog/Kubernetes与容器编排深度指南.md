---
title: 'Kubernetes 与容器编排：现代生产指南'
description: '面向生产环境梳理 Kubernetes 架构、CRI/containerd、CNI/CSI、Pod Security Admission、GPU Operator、升级、etcd 备份恢复与故障排查。'
pubDate: 2026-03-23
tags: ['云原生架构']
---

# Kubernetes 与容器编排：现代生产指南

**学习深度**: ⭐⭐⭐⭐⭐

这篇文章不追求罗列所有 API，而是把容易过期或容易误导的 Kubernetes 知识更新为生产可用的判断框架。重点是运行时、安全、网络、存储、GPU、升级、备份恢复和故障排查。

---

## 目录

1. [架构与术语](#架构与术语)
2. [容器运行时：Docker、CRI 与 containerd](#容器运行时dockercri-与-containerd)
3. [调度、网络与存储](#调度网络与存储)
4. [安全：从 PSP 到 PSS/PSA](#安全从-psp-到-psspsa)
5. [GPU 与异构资源](#gpu-与异构资源)
6. [升级、备份与恢复](#升级备份与恢复)
7. [生产故障排查](#生产故障排查)
8. [参考来源](#参考来源)

---

## 架构与术语

Kubernetes 是一个声明式控制系统。用户把期望状态写入 API Server，控制器、调度器、kubelet、网络和存储组件不断把实际状态收敛到期望状态。

现代文档应使用 **control plane** 和 **worker node**，避免沿用早期文档中的主从式称呼。

| 层级 | 组件 | 生产关注点 |
| --- | --- | --- |
| Control plane | kube-apiserver | 认证、授权、准入控制、限流、审计、可用性 |
| Control plane | etcd | quorum、磁盘延迟、备份、恢复演练、加密 |
| Control plane | kube-scheduler | 资源请求、亲和性、污点容忍、拓扑分布 |
| Control plane | controller-manager | 控制循环、leader election、对象状态收敛 |
| Node | kubelet | Pod 生命周期、探针、CRI、cgroup、节点状态 |
| Node | container runtime | containerd/CRI-O/cri-dockerd、镜像拉取、sandbox |
| Node/cluster | CNI、CSI | 网络连通、Service、NetworkPolicy、卷挂载 |

理解 Kubernetes 的关键不是记住组件列表，而是理解几条链路：

- **声明链路**: `kubectl` 或控制器写 API Server，状态持久化到 etcd。
- **调度链路**: scheduler 为 Pending Pod 选择节点并绑定。
- **节点链路**: kubelet 通过 CRI 调用运行时创建 Pod sandbox 和容器。
- **网络链路**: CNI 插件实现 Pod 网络模型，Service 由 kube-proxy 或 eBPF 数据面实现。
- **存储链路**: CSI 驱动处理卷的供应、挂载、扩容和快照。

---

## 容器运行时：Docker、CRI 与 containerd

需要区分两个问题：

- 用 Docker/BuildKit/Podman 构建镜像。
- Kubernetes 节点用什么运行时启动 Pod。

Kubernetes 通过 **Container Runtime Interface (CRI)** 与节点运行时通信。Kubernetes v1.24 起，内置 dockershim 已移除；Docker Engine 本身不实现 CRI。如果仍要使用 Docker Engine 作为节点运行时，需要额外的 `cri-dockerd` 适配层。生产集群更常见的选择是 containerd 或 CRI-O。

| 选择 | 适合 | 注意点 |
| --- | --- | --- |
| containerd | 大多数通用 Kubernetes 集群 | 配置 cgroup driver、镜像仓库、sandbox image、日志和 GC |
| CRI-O | 偏 Kubernetes 原生、OpenShift 等场景 | 版本兼容和发行版集成 |
| Docker Engine + cri-dockerd | 历史集群迁移或特殊依赖 | 需要额外适配层，不应再写成默认方案 |

生产检查：

- kubelet 与运行时使用一致的 cgroup driver，常见生产选择是 `systemd`。
- 节点上不要让业务 Pod 依赖 `docker ps`、`/var/run/docker.sock` 或 Docker 特有路径。
- 镜像构建链路与运行链路解耦，镜像符合 OCI 规范即可被多种运行时运行。
- 升级前检查 CRI API 版本、containerd 主版本和 kubelet 兼容性。

---

## 调度、网络与存储

### 调度

调度不是简单“找一台空机器”。scheduler 先过滤不可用节点，再按资源、亲和性、拓扑、污点容忍、插件打分选择节点。

生产中最常见的问题是资源请求不准确：

- `requests` 决定调度和容量规划。
- `limits` 影响 CPU throttling 和内存 OOM。
- 没有 request 的工作负载会污染集群装箱结果。
- 只设置 CPU limit 而不了解应用行为，可能引入尾延迟。

建议把调度策略写成可审计的规则：

- 基础服务使用 PodDisruptionBudget、拓扑分布约束和反亲和。
- 批处理使用优先级、污点容忍和独立节点池。
- 有状态服务明确存储拓扑和故障域。
- GPU、RDMA、本地盘等资源单独建节点池和准入规则。

### CNI

Kubernetes 要求使用兼容的 CNI 插件实现 Pod 网络模型。CNI 选择会影响 NetworkPolicy、性能、可观测性、双栈、eBPF、加密和跨集群能力。

| 关注点 | 需要验证 |
| --- | --- |
| Pod 到 Pod | 跨节点连通、MTU、封装或路由模式 |
| Service | kube-proxy iptables/ipvs 或 eBPF 替代方案 |
| NetworkPolicy | 插件是否真正支持，默认拒绝策略是否生效 |
| DNS | CoreDNS 延迟、上游解析、ndots、缓存 |
| 可观测性 | flow log、drop reason、连接追踪、策略审计 |

### CSI

CSI 把存储能力从 Kubernetes 核心中解耦。生产集群要关注：

- StorageClass 的 reclaim policy、volume binding mode、拓扑感知。
- 动态供应、在线扩容、快照、克隆是否被具体 CSI 驱动支持。
- 卷挂载失败时，问题可能在云盘、节点权限、CSI controller、CSI node、kubelet 或 attach/detach controller。
- 有状态服务升级前验证存储快照和恢复流程，而不是只相信 PVC 存在。

---

## 安全：从 PSP 到 PSS/PSA

PodSecurityPolicy 已在 Kubernetes v1.21 废弃，并在 v1.25 移除。现代集群不应再把 PSP 当作主线方案。

Kubernetes 内置的 **Pod Security Admission (PSA)** 可以按命名空间执行 **Pod Security Standards (PSS)**。PSS 分为：

- `privileged`: 基本不限制，适合受控的系统命名空间或特权组件。
- `baseline`: 阻止明显危险的权限提升，适合作为多数应用最低线。
- `restricted`: 更严格，适合安全敏感工作负载，但需要镜像和运行参数配合。

PSA 支持 `enforce`、`audit`、`warn` 三种模式。生产迁移通常先用 `audit`/`warn` 观察，再逐步切到 `enforce`。

安全基线不应只靠 PSA：

- RBAC 最小权限，禁止默认 ServiceAccount 过大权限。
- 镜像签名、漏洞扫描、准入校验和私有镜像仓库策略。
- Secret 加密、外部密钥管理、定期轮转。
- NetworkPolicy 默认拒绝，再按服务放通。
- 禁止不必要的 privileged、hostNetwork、hostPID、hostPath。
- 审计日志、准入 webhook 和运行时安全监控。

---

## GPU 与异构资源

旧文章常把 GPU 部署写成安装 Docker 时代的 NVIDIA 运行时组件。现代 Kubernetes 生产主线已经转向 CRI、device plugin 和 Operator 化管理。

Kubernetes 通过 device plugin framework 暴露 GPU 等特殊硬件。NVIDIA 的推荐生产路径通常是 **NVIDIA GPU Operator**，它用 Operator 管理驱动、NVIDIA Container Toolkit、device plugin、GPU Feature Discovery、DCGM 监控等组件。

GPU 生产设计要明确：

- 节点运行时是 containerd、CRI-O 还是其他 CRI 实现。
- 驱动由宿主机预装，还是由 GPU Operator 管理。
- 是否使用 MIG、time-slicing、MPS、CDI 或 RuntimeClass。
- GPU 节点是否独立污点，普通工作负载是否禁止调度上去。
- 监控是否覆盖 GPU 利用率、显存、ECC、温度、XID 错误和 DCGM 指标。
- 升级驱动、CUDA 基础镜像和 Kubernetes 版本时是否有兼容矩阵。

---

## 升级、备份与恢复

### Kubernetes 升级

升级不是简单替换镜像。生产升级建议遵循：

1. 读目标版本 release notes，检查弃用 API、移除功能和组件兼容性。
2. 先升级测试集群或非关键节点池。
3. 备份 etcd，并确认备份文件可恢复。
4. 逐个 control plane 节点升级，再升级 worker 节点。
5. 每批升级后检查 API Server、controller、scheduler、CNI、CSI、CoreDNS、Ingress、监控。
6. 对关键业务执行发布、扩缩容、重启、PVC 挂载和故障演练。

kubeadm 升级会在本地生成部分备份目录，但这不能替代长期、加密、异地保存、定期演练的 etcd 备份策略。

### etcd 备份恢复

etcd 保存 Kubernetes 所有对象状态。丢失 etcd 或恢复错误，会影响整个集群。

关键原则：

- 定期用 etcd 原生命令或底层卷快照备份。
- 备份文件包含敏感数据，必须加密、限权、异地保存。
- 备份后记录 revision、hash、大小和来源节点。
- 恢复演练要在隔离环境完成，避免旧成员误加入。
- etcd v3.5 起恢复工具链逐步转向 `etcdutl`；不同版本细节要按实际 etcd 文档执行。
- Kubernetes 场景恢复旧 revision 后，控制器 informer 缓存可能出现问题；新版 etcd 文档建议使用 revision bump 和 mark compacted 等机制处理这类风险。

恢复不是“把快照拷回去”这么简单。恢复计划应写清：

- control plane 是否全损，还是单成员损坏。
- 使用 stacked etcd 还是 external etcd。
- 证书、静态 Pod manifest、数据目录和成员拓扑如何重建。
- 恢复后如何验证 API 对象、核心组件、业务控制器和数据面。

---

## 生产故障排查

### 排查原则

Kubernetes 故障排查先分层，不要一上来重启组件：

1. API 是否可用：`kubectl get --raw=/readyz?verbose`、审计和 apiserver 日志。
2. 对象状态是否正确：Deployment、ReplicaSet、Pod、Event、Condition。
3. 调度是否卡住：资源不足、污点、亲和性、PVC 未绑定、配额。
4. 节点是否健康：kubelet、运行时、磁盘、PID、内存、网络。
5. 网络是否异常：DNS、Service endpoints、NetworkPolicy、CNI 日志、MTU。
6. 存储是否异常：PVC/PV、CSI controller/node、云盘事件、挂载点。
7. 应用是否异常：探针、配置、Secret、镜像、依赖服务。

### 常见症状表

| 症状 | 优先检查 |
| --- | --- |
| Pod 一直 Pending | `describe pod` 事件、资源 requests、污点容忍、PVC、配额 |
| Pod CrashLoopBackOff | 容器日志、退出码、启动探针、配置、依赖服务 |
| ImagePullBackOff | 镜像名、tag、仓库权限、节点到仓库网络、镜像拉取 Secret |
| Service 不通 | EndpointSlice、Pod readiness、Service selector、kube-proxy/eBPF、NetworkPolicy |
| DNS 慢或失败 | CoreDNS 日志、上游 DNS、ndots、缓存、节点网络 |
| PVC 挂载失败 | StorageClass、PV 事件、CSI 日志、节点权限、云盘状态 |
| 节点 NotReady | kubelet、container runtime、CNI、磁盘压力、证书、系统资源 |
| API Server 慢 | etcd 延迟、watch 数量、LIST 大对象、webhook 超时、审计后端 |

### Webhook 与准入控制风险

生产事故里，准入 webhook 经常成为隐藏单点：

- `failurePolicy: Fail` 会在 webhook 不可用时阻断创建或更新。
- webhook 超时时间过长会拖慢 API Server。
- webhook 自身依赖集群内 DNS、Service、证书和网络。
- 升级前要检查 webhook 支持的 API 版本和证书有效期。

建议把关键 webhook 做高可用，限制作用范围，设置合理 timeout，并在事故预案里写清如何临时降级。

---

## 参考来源

- Kubernetes Container Runtimes: https://kubernetes.io/docs/setup/production-environment/container-runtimes/
- Kubernetes Container Runtime Interface: https://kubernetes.io/docs/concepts/architecture/cri/
- Kubernetes Dockershim migration: https://kubernetes.io/docs/tasks/administer-cluster/migrating-from-dockershim/
- Kubernetes Network Plugins: https://kubernetes.io/docs/concepts/extend-kubernetes/compute-storage-net/network-plugins/
- Kubernetes Storage / CSI API reference: https://kubernetes.io/docs/reference/kubernetes-api/storage/
- Kubernetes Pod Security Admission: https://kubernetes.io/docs/concepts/security/pod-security-admission/
- Kubernetes PodSecurityPolicy removal: https://kubernetes.io/docs/concepts/policy/pod-security-policy/
- Kubernetes Operating etcd clusters: https://kubernetes.io/docs/tasks/administer-cluster/configure-upgrade-etcd/
- etcd Disaster Recovery: https://etcd.io/docs/v3.6/op-guide/recovery/
- NVIDIA GPU Operator: https://docs.nvidia.com/datacenter/cloud-native/gpu-operator/latest/
