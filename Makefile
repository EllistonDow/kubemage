.PHONY: phase1 phase2 phase3 phase4 phase5 artifacts

KUBECONFIG ?= ~/.kube/config

phase1:
	@echo "[Phase1] 初始化 kubeadm + Cilium + MetalLB + OpenEBS"
	@./scripts/phase1-deploy.sh

phase2:
	@echo "[Phase2] 部署 GitOps/监控/安全"
	@./scripts/phase2-deploy.sh

phase3:
	@echo "[Phase3] 部署依赖服务"
	@./scripts/phase3-deploy.sh

phase4:
	@echo "[Phase4] 部署 Magento 站点 (请在 charts/values 中配置)"
	@./scripts/phase4-deploy.sh

phase5:
	@echo "[Phase5] 执行扩容/灾备任务"
	@./scripts/phase5-ops.sh

artifacts:
	@mkdir -p artifacts/phase1 artifacts/phase2 artifacts/phase3 artifacts/phase4 artifacts/phase5
