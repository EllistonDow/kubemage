# 裸机 K8s 拓扑（无 PVE）

## 1. 节点规划
| 节点 | 角色 | 说明 |
| --- | --- | --- |
| `bm-a` | control-plane + worker | 当前唯一服务器，运行 etcd + API server + 所有工作负载；预留 kube-vip 虚拟 IP。 |
| `bm-b`（未来） | control-plane + worker | 第二台服务器到位后加入集群，迁移 kube-vip keepalived，复制 StatefulSet 副本。 |

- 公网：OVH 提供主 IP + Failover IP，用于 MetalLB/kube-vip。
- 内网：vRack（或本地 VLAN）用于节点互联、存储同步、备份。若暂时没有 vRack，使用 WireGuard 先打通，等 vRack 下发后切换。
- 控制面高可用：初期为 stacked etcd 单节点；bm-b 就绪后执行 `kubeadm join --control-plane`，再通过 `kubeadm init phase etcd local` 扩容 etcd，最终形成双节点 stacked etcd + kube-vip 虚 IP。

## 2. kube-vip / MetalLB 策略
- kube-vip：
  - VIP 选择 OVH Failover IP（例如 `51.x.x.x`）。
  - 先在 bm-a 部署 DaemonSet 模式的 kube-vip（只调度 control-plane 节点）。
  - 待 bm-b 上线后，kube-vip 会在节点之间漂移，无需额外 VRRP。若短期只一台，VIP 仍指向 bm-a，便于后续平滑过渡。
- MetalLB：
  - L2 模式，地址池使用剩余的 Failover IP 段。
  - Kubernetes `LoadBalancer` Service 出口由 MetalLB 分配，结合 OVH 的 `ip route add` 允许回程。

## 3. 存储布局
- ZFS mirror（`/dev/nvme0n1`, `/dev/nvme1n1`）
  - `rpool/ubuntu`：系统
  - `rpool/containerd`
  - `rpool/k8s/pv`
- StorageClass：OpenEBS ZFS-LocalPV -> `fast-local-zfs`；未来引入 Longhorn，用 `slow-replicated` 覆盖跨节点场景。
- 备份：ZFS snapshot 每小时/每日滚动，并同步到 OVH Cloud Object Storage。

## 4. kubeadm 配置要点
```yaml
apiVersion: kubeadm.k8s.io/v1beta4
kind: ClusterConfiguration
kubernetesVersion: v1.30.2
controlPlaneEndpoint: "k8s-vip.example.com:6443" # 解析到 Failover IP
networking:
  podSubnet: 10.42.0.0/16
  serviceSubnet: 10.43.0.0/16
  dnsDomain: cluster.local
controllerManager:
  extraArgs:
    bind-address: 0.0.0.0
scheduler:
  extraArgs:
    bind-address: 0.0.0.0
etcd:
  local:
    dataDir: /var/lib/etcd
    extraArgs:
      listen-metrics-urls: http://0.0.0.0:2381
---
apiVersion: kubelet.config.k8s.io/v1beta1
kind: KubeletConfiguration
cgroupDriver: systemd
---
apiVersion: kubeproxy.config.k8s.io/v1alpha1
kind: KubeProxyConfiguration
mode: "none" # 由 Cilium kube-proxy replacement 接管
```

- kubeadm init 后立刻安装 Cilium（启用 kube-proxy replacement）。
- kube-vip 清单可通过 `kube-vip manifest daemonset ...` 生成后纳入 GitOps。

## 5. 未来第二台加入步骤
1. 按 Phase 0 checklist 初始化 bm-b（同样的内核、ZFS、containerd）。
2. `kubeadm join <VIP>:6443 --token ... --discovery-token-ca-cert-hash ... --control-plane`。
3. kubeadm 会自动在 bm-b 创建 etcd 成员，完成后运行：
   ```bash
   kubectl get nodes
   kubectl get pods -n kube-system -l component=kube-apiserver
   ```
4. 为 StatefulSet/DaemonSet 设置：
   - `podAntiAffinity` 避免两个副本落在同一节点。
   - `topologySpreadConstraints` 对 `kubernetes.io/hostname` 做均衡。
5. MetalLB 地址池保持不变；kube-vip 将根据 leader 选举漂移。

## 6. 无虚拟化时的风险控制
- 单节点期间任何内核升级都必须在维护窗口执行，并在升级前完成 `etcdctl snapshot save` + PVC 备份。
- 建议在 bm-a 启动额外 systemd 服务，监控 NVMe SMART、内存 ECC 统计，一旦出现异常及时触发 failover 预案。
- 在 kube-system 命名空间部署 `node-problem-detector` 以捕获内核/硬件事件，联动 Alertmanager。

完成本文件中的准备即可在 bm-a 上直接执行 Phase 1 的 kubeadm init。未来扩展只需按第 5 节流程处理。
