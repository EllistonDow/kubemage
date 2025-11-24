# Phase 1：集群引导操作手册

## 前置条件
1. bm-a 已按 `scripts/host-init.sh` 初始化完毕（关闭 swap、安装 containerd/kubeadm、配置 ZFS）。
2. VIP/FQDN 与 Failover IP 解析完成。
3. `kubemage/cluster/phase1/kubeadm-config.yaml` 中的占位符（FQDN/IP）已替换。

## 步骤
### 1. kubeadm init
```bash
sudo kubeadm init --config kubeadm-config.yaml --upload-certs
mkdir -p ~/.kube
sudo cp /etc/kubernetes/admin.conf ~/.kube/config
sudo chown $(id -u):$(id -g) ~/.kube/config
```

### 2. 部署 kube-vip（control-plane 高可用）
```bash
export VIP=51.51.51.50   # Failover IP
export INTERFACE=eno1    # 出口网卡
kubectl apply -f https://kube-vip.io/manifests/rbac.yaml
alias kube-vip='docker run --network host --rm plndr/kube-vip:v0.7.1'
kube-vip manifest daemonset \
  --interface $INTERFACE \
  --vip $VIP \
  --controlplane \
  --inCluster \
  --taint \
  --services | kubectl apply -f -
```
> 未来 bm-b 加入后，无需修改 kube-vip；它会在 control-plane 节点间漂移。

### 3. 安装 Cilium
```bash
helm repo add cilium https://helm.cilium.io/
helm install cilium cilium/cilium \
  --namespace kube-system \
  --version 1.15.5 \
  -f cilium-values.yaml
```

### 4. 部署 MetalLB
```bash
kubectl create namespace metallb-system
helm repo add metallb https://metallb.github.io/metallb
helm install metallb metallb/metallb -n metallb-system --version 0.14.5
kubectl apply -f metallb-config.yaml
```

### 5. 部署 metrics-server + kube-state-metrics（可选 Helmfile）
```bash
helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server/
helm install metrics-server metrics-server/metrics-server -n kube-system \
  --version 3.12.1 \
  --set args={--kubelet-insecure-tls}
```

### 6. 安装 OpenEBS ZFS-LocalPV
```bash
helm repo add openebs https://openebs.github.io/charts
helm install openebs openebs/openebs -n openebs --create-namespace \
  --version 3.10.0 \
  -f openebs-values.yaml
```

### 7. 验证
```bash
kubectl get nodes -o wide
kubectl get pods -A
kubectl get storageclass
sonobuoy run --mode=quick
sonobuoy retrieve . && tar -xf *.tar.gz
```

## 产出
- 一个可用的单节点 K8s 集群，具备：kube-vip、Cilium、MetalLB、metrics-server、OpenEBS。
- 生成的 `admin.conf` 存入安全仓库（Vault/SOPS）。
- `sonobuoy` 报告归档在 `artifacts/phase1/`。

## 下一步
完成 Phase 1 后即可进入 Phase 2，开始部署 GitOps/监控/安全组件。
