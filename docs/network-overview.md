# Kubemage 网络分配概览

## 裸机节点 (bm-a)
- **主 IP**：`51.222.241.152/32`（netplan 接口 `ens2f0`，DHCPv4=true）
- **IPv6 前缀**：`2607:5300:203:8f98::/64`（缺省网关 `2607:5300:203:8fff:ff:ff:ff:ff`）

## OVH Failover IP（可在节点之间漂移）
读取 `/etc/netplan/50-cloud-init.yaml`，当前挂载的 `/32` 列表如下，可用于 kube-vip + MetalLB：

| 地址 | 备注（netplan 注释） |
| --- | --- |
| `192.99.177.222/32` | 第一个 IP |
| `144.217.149.203/32` | bdgyoo.com |
| `149.56.244.16/32` | savageneedles.com |
| `149.56.123.163/32` | hawktattoo.com |
| `66.70.152.224/32` | papatattoo.com |
| `142.44.177.171/32` | ipowerwatch.com |
| `66.70.159.109/32` | ambitiontattoosupply.com |
| `51.161.21.62/32` | nucleartattooca.com |

建议：
- **kube-vip（control-plane endpoint）**：从上表挑选一个 Failover IP（例如 `192.99.177.222`）。
- **MetalLB Pool**：使用其余 Failover IP 组成地址池，例如 `144.217.149.203/32,149.56.244.16/32,...`。

## Phase 1 渲染建议
在 `phase1.env` 中设置：
```env
PHASE1_CONTROL_PLANE_ENDPOINT=192.99.177.222:6443
PHASE1_METALLB_ADDRESSES=144.217.149.203/32,149.56.244.16/32,149.56.123.163/32,66.70.152.224/32,142.44.177.171/32,66.70.159.109/32,51.161.21.62/32
```
这样 kube-vip 与 MetalLB 就会占用 Failover IP，而宿主机主 IP (`51.222.241.152`) 仍负责默认路由。

## 当前暴露策略（2025-11-30）
- `ingress-nginx` 通过 `hostNetwork + hostPort` 直接监听 `51.222.241.152:80/443`，满足“站点全部迁移完再 MOVE Failover IP”的要求。
- MetalLB `public-pool` 继续保留 7 个 Failover IP（`144.217.149.203/32` 等），为后续切换 LoadBalancer 或第二台裸机扩容做准备。
- `argocd.k8s.bdgyoo.com`、`*.k8s.bdgyoo.com` 的 DNS 需要暂时指向主 IP `51.222.241.152`；等迁移完成后，再按表格执行 OVH MOVE 并将 DNS 改回对应 Failover IP。
