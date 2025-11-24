# Kubemage GitOps Skeleton

```
gitops/
├── clusters/
│   └── kubemage-prod/
│       └── kustomization.yaml
├── infra/
│   ├── base/
│   │   ├── cilium.yaml
│   │   ├── metallb.yaml
│   │   └── openebs.yaml
│   └── overlays/
│       └── prod/
│           └── kustomization.yaml
├── platform/
│   ├── gitops/argocd.yaml
│   ├── monitoring/kube-prometheus.yaml
│   └── security/gatekeeper.yaml
└── tenants/
    ├── store1/
    │   ├── kustomization.yaml
    │   └── values-store1.yaml.enc
    ├── demo/
    │   ├── kustomization.yaml
    │   └── values-demo.yaml (需 SOPS 加密)
    └── bdgy/
        ├── kustomization.yaml
        └── values-bdgy.yaml (需 SOPS 加密)
```

- `clusters/kubemage-prod/kustomization.yaml` 引用 `infra/overlays/prod`, `platform/*`, `tenants/<store>`（store1/demo/bdgy）。
- 每个目录可进一步拆成 HelmRelease/HelmChart CR 或 Argo Application。
- secrets 使用 SOPS 加密（`.enc.yaml`）。
