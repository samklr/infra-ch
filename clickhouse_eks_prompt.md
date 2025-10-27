# Prompt: Deploy production-ready ClickHouse on EKS using Altinity Operator + ClickHouse Keeper

## Goal
Provision a secure, production-ready ClickHouse cluster on AWS EKS using the **Altinity ClickHouse Operator** and **ClickHouse Keeper** (no Zookeeper). Provide automated infrastructure-as-code (Terraform), Kubernetes manifests/Helm values, monitoring, S3 backups, autoscaling, load-balancer external access, and operational runbook.

---

## High-Level Requirements

### 1. AWS Infrastructure (Terraform)
- **VPC**: private subnets across 3 AZs, NAT gateways, route tables.
- **EKS**: managed node groups (3 AZs, multiple node groups for stateful/stateless workloads).
- **IAM roles & policies** for Altinity Operator, Load Balancer Controller, EBS CSI Driver, S3 backup job, CloudWatch/Prometheus.
- **EBS CSI Driver** and **AWS Load Balancer Controller** installation.
- **S3 bucket** for ClickHouse backups (encrypted, lifecycle policies).
- **Autoscaler (Cluster Autoscaler or Karpenter)** setup.

### 2. Kubernetes Components (Helm / Manifests)
- Altinity ClickHouse Operator (Helm or manifests).
- ClickHouse Keeper (instead of Zookeeper).
- Cert-manager, AWS Load Balancer Controller, EBS CSI Driver.
- Prometheus + Grafana for monitoring.
- ClickHouse exporter for Prometheus.
- Backup CronJob using `clickhouse-backup`.
- Optional: ClickHouse client job for smoke tests.

### 3. ClickHouse Cluster Design
- Deployed via `ClickHouseInstallation` CRD (CHI).
- Replicated across **3 AZs** (e.g., 3 shards × 2 replicas).
- Use **ClickHouse Keeper** for quorum and metadata.
- Persistent **EBS gp3 volumes** with encryption.
- Configure **resources, affinity, topology spread**, and **PDBs**.
- TLS for client-server and inter-node traffic.
- NLB (Network Load Balancer) for external access.

### 4. Autoscaling
- **Node autoscaling** via Cluster Autoscaler or Karpenter.
- **ClickHouse scaling** managed manually via Operator (document safe strategy).

### 5. External Access
- Use **AWS Load Balancer Controller** to expose HTTP (8123) and native (9000) ports.
- Configure annotations for cross-zone, internal/external mode.

### 6. Backup & Restore
- Schedule S3 backups using `clickhouse-backup` CronJob.
- Use IRSA for secure S3 access.
- Test restore procedure.

### 7. Security & IAM
- **IRSA** for all service accounts.
- **Encryption in transit and at rest**.
- **NetworkPolicies** limiting pod-to-pod access.

### 8. Observability
- Prometheus + Grafana dashboards.
- CloudWatch integration.
- Alert rules (replica lag, disk pressure, CPU, etc.).

### 9. Best Practices
- Version pinning, immutable deployments.
- PDBs and rolling upgrades.
- Documented scaling and backup runbooks.

---

## Repository Layout

```
clickhouse-eks-deploy/
├── README.md
├── terraform/
│   ├── modules/
│   │   ├── vpc/
│   │   ├── eks-cluster/
│   │   └── iam/
│   ├── main.tf
│   ├── variables.tf
│   ├── outputs.tf
│   └── versions.tf
├── k8s/
│   ├── helm-values/
│   │   ├── clickhouse-operator-values.yaml
│   │   └── aws-load-balancer-controller-values.yaml
│   ├── manifests/
│   │   ├── storageclass-gp3.yaml
│   │   ├── clickhouse-chi.yaml
│   │   ├── keeper-config.yaml
│   │   ├── svc-nlb-clickhouse.yaml
│   │   ├── cert-manager.yaml
│   │   ├── prometheus-operator-values.yaml
│   │   └── clickhouse-backup-cronjob.yaml
│   └── kustomization.yaml
├── iam-policies/
│   ├── s3-backup-policy.json
│   ├── loadbalancer-controller-policy.json
│   └── ebs-csi-policy.json
├── scripts/
│   ├── bootstrap.sh
│   └── smoke-test.sh
└── docs/
    ├── runbook.md
    ├── security.md
    └── scaling-guide.md
```

---

## Deliverables
- Terraform for AWS infra (EKS, VPC, IAM, S3).
- Helm values for Altinity Operator, Load Balancer Controller.
- ClickHouseInstallation manifest (with Keeper).
- Prometheus + Grafana setup.
- Backup CronJob.
- Scripts for bootstrap, testing, teardown.
- Documentation and runbook.

---

## Acceptance Criteria
1. EKS cluster is provisioned with correct IAM roles.
2. Altinity Operator is installed and functional.
3. ClickHouse + Keeper pods are healthy across 3 AZs.
4. Load balancer provides external ClickHouse access.
5. Monitoring and backups are operational.
6. TLS, encryption, and IRSA are correctly configured.
7. Autoscaler responds to workload changes.
8. Smoke tests and S3 restore pass.

---

## Constraints & Security
- Never hardcode AWS credentials.
- No destructive operations without confirmation.
- Use least-privilege IAM roles.
- Document all manual steps (if any).

---

## Execution Steps
1. `terraform init && terraform apply`
2. `./scripts/bootstrap.sh` (installs operator, Helm charts)
3. `kubectl apply -f k8s/manifests/clickhouse-chi.yaml`
4. Wait for pods to be Ready.
5. `./scripts/smoke-test.sh`

---

## Quality Requirements
- Parameterized Terraform variables.
- Safe defaults for production.
- Clear documentation and teardown steps.
- Automated tests for verification.

---

## Final Note for the Agent
- Use pinned versions for all dependencies.
- Follow Altinity and AWS best practices.
- Provide complete IaC and deployment automation.
