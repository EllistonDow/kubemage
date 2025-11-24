# Phase 0 Checklist（宿主机与基础假设）

## 1. 资源盘点
- [ ] OVH 裸金属：CPU/内存/磁盘/带宽/附加 IP（Failover IP、vRack）记录
- [ ] 未来第二台服务器 ETA 与网络拓扑确认
- [ ] 外部依赖：对象存储（OVH Cloud Object Storage）、CI/CD 平台、DNS/CDN 提供商

## 2. Ubuntu 24.04 LTS 初始化
- [ ] PXE/ISO 安装最小化系统（只含 `openssh-server`、`curl`、`jq` 等基础包）
- [ ] 创建 `devops`/`ci` 等运维账号，启用 yubikey/OTP 登录策略
- [ ] 配置时区 UTC、`chrony` 同步 OVH NTP
- [ ] `apt-mark hold linux-image-generic linux-headers-generic`（保留 GA 6.8 内核）
- [ ] 清理不必要的 `snapd`/cloud-init 模块，保留 `network-config`、`set-passwords` 等必要功能
- [ ] `systemd-resolved` 设置 `DNSStubListener=no` 并重启，预留 53 端口给 CoreDNS
- [ ] 开启 AppArmor/SELinux（Ubuntu 默认 AppArmor），加载 Kubelet/Cilium 建议 profile
- [ ] 启用 `ufw`/`nftables` 基线（只放行 SSH+K8s 控制面端口）

## 3. 存储与文件系统
- [ ] 两块 NVMe 以 ZFS RAID1（mirror）形式创建 `rpool`
- [ ] 划分 dataset：`rpool/os`, `rpool/containerd`, `rpool/k8s/pv`
- [ ] 预创建 snapshot/backup 策略（zfs auto-snapshot + S3 复制脚本）
- [ ] 为 OpenEBS ZFS-LocalPV 预置 dataset 并记录 `mountpoint`

## 4. 虚拟化/节点布局决策
- [ ] 评估“直接裸跑单节点” vs “Proxmox/KVM 拆分控制面”的利弊
- [ ] 若采用虚拟化：
  - [ ] 设计 control-plane VM（3×2 vCPU / 6 GB RAM）和 worker VM（2×6 vCPU / 32 GB RAM）
  - [ ] 配置 bridge 网络（一个公网、一个 vRack）
  - [ ] 设置 HugePages/CPU pinning 减少噪声
- [ ] 若裸跑：规划 `systemd-nspawn` 或 `kube-vip` 方案保障控制面高可用

## 5. Kubernetes 先决条件
- [ ] 安装 containerd 1.7+，配置 `SystemdCgroup=true`
- [ ] 预安装 kubeadm/kubelet/kubectl（与目标 Kubernetes 版本匹配）
- [ ] 生成 kube-vip/MetalLB 需要的 VIP 列表
- [ ] 准备 Cilium 安装值文件（启用 Hubble、eBPF host-routing、TProxy）

## 6. 安全与合规准备
- [ ] 生成集群 CA/etcd 证书保管策略（离线加密存储）
- [ ] 明确 Secrets 管理流（SOPS + age key + Vault/ESO）
- [ ] 制定补丁/重启窗口与 kured 配置（label 控制）
- [ ] 记录所有默认密码、API 密钥的保管方式

完成上述清单即可进入 Phase 1（kubeadm 引导）。
