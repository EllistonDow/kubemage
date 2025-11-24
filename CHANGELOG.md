# Changelog

## [0.1.0] - 2025-11-24
### Added
- Initial Kubernetes-ready Magento 2.4.8 stack with Docker/Helm assets, GitOps manifests, and infra scripts.
- Multi-site layout under `app/sites/<site>` with demo store sample data, including custom `Kubemage_MenuFix` module to keep navigation stable behind Varnish.
- Reference docs covering platform phases, container images, and local compose workflows.
- Preconfigured ModSecurity/Nginx, Varnish VCL, and dependency services (Percona, OpenSearch, RabbitMQ, Valkey) for local and cluster deployments.

### Fixed
- Resolved top navigation loss under Varnish by clearing TTL hints so menus render inline even when FPC is cached externally.
