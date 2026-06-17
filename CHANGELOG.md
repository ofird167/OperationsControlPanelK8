# Changelog

All notable changes to this project will be documented in this file.

## [2.0.0] - 2026-06-17
### Added
- **High Availability (HA) Control Plane:** Migrated from single node to 3-node HA quorum using K3s embedded etcd.
- **Argo Rollouts:** Replaced manual Deployments with automated progressive delivery (canary pausing and NGINX injection).
- **Network Policies:** Implemented strict Zero-Trust pod isolation.
- **Velero Backups:** Integrated automated backups to Google Cloud Storage.
- **Security Scanning:** Added Trivy to automatically scan Docker images during build.
- **Service Mesh:** Added Linkerd for automatic mTLS sidecar injection.
- **AIO Script:** Created a unified `aio.sh` entrypoint for one-click setup.
- **CI Pipeline:** Added GitHub Actions workflow.

## [1.0.0] - 2026-06-15
### Added
- Initial setup and planning artifacts (`implementation_plan.md`, `task.md`).
- Environment templates and gitignore configurations (`example.env`, `.gitignore`, `LICENSE`).
