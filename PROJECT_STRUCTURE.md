# Project Structure

Complete production-ready ClickHouse deployment on AWS EKS and GCP GKE.

```
clickhouse-eks-deploy/
├── README.md                          # Main documentation
├── QUICKSTART.md                      # Quick start guide
├── PROJECT_STRUCTURE.md               # This file
├── .gitignore                         # Git ignore rules
│
├── terraform/                         # Infrastructure as Code
│   ├── main.tf                        # Main Terraform configuration
│   ├── variables.tf                   # Input variables
│   ├── outputs.tf                     # Output values
│   ├── versions.tf                    # Provider versions
│   ├── terraform.tfvars.example       # Example variables file
│   │
│   └── modules/                       # Terraform modules
│       ├── vpc/                       # VPC module
│       │   ├── main.tf               # VPC, subnets, NAT gateways
│       │   ├── variables.tf
│       │   └── outputs.tf
│       │
│       ├── eks-cluster/               # EKS cluster module
│       │   ├── main.tf               # EKS cluster, node groups
│       │   ├── variables.tf
│       │   └── outputs.tf
│       │
│       └── iam/                       # IAM roles module
│           ├── main.tf               # IRSA roles for services
│           ├── variables.tf
│           └── outputs.tf
│
├── terraform-gke/                     # GKE Infrastructure
│   ├── main.tf
│   ├── variables.tf
│   ├── outputs.tf
│   └── terraform.tfvars.example
│
├── terraform/modules/gke-cluster/     # GKE Cluster Module
│   ├── main.tf
│   ├── variables.tf
│   └── outputs.tf
│
├── k8s/                               # Kubernetes manifests
│   ├── manifests/                     # Kubernetes YAML files
│   │   ├── namespace.yaml            # ClickHouse namespace
│   │   ├── storageclass-gp3.yaml     # EBS StorageClass
│   │   ├── keeper-config.yaml        # ClickHouse Keeper StatefulSet
│   │   ├── clickhouse-chi.yaml       # ClickHouseInstallation CRD
│   │   ├── svc-nlb-clickhouse.yaml   # Network Load Balancers
│   │   ├── clickhouse-backup-cronjob.yaml  # Backup CronJob
│   │   └── prometheus-operator-values.yaml # Monitoring config
│   │
│   └── helm-values/                   # Helm chart values
│       ├── clickhouse-operator-values.yaml      # Altinity operator
│       └── aws-load-balancer-controller-values.yaml  # AWS LB controller
│
│   └── charts/                        # Helm Charts
│       └── clickhouse-gke/            # GKE ClickHouse Chart
│           ├── Chart.yaml
│           ├── values.yaml
│           └── templates/
│
├── iam-policies/                      # IAM policy documents
│   ├── s3-backup-policy.json         # S3 backup permissions
│   ├── loadbalancer-controller-policy.json  # LB controller permissions
│   └── ebs-csi-policy.json           # EBS CSI driver permissions
│
├── scripts/                           # Automation scripts
│   ├── bootstrap.sh                  # Deploy all K8s components
│   └── smoke-test.sh                 # Verify installation
│
└── docs/                              # Documentation
    ├── runbook.md                    # Operational procedures
    ├── security.md                   # Security best practices
    └── scaling-guide.md              # Scaling strategies
```

## File Descriptions

### Root Level

- **README.md**: Complete documentation with architecture, features, and operations
- **QUICKSTART.md**: Step-by-step guide to deploy in <30 minutes
- **PROJECT_STRUCTURE.md**: This file - project organization
- **.gitignore**: Exclude sensitive files from version control

### Terraform (`terraform/`)

Infrastructure provisioning for AWS resources.

**Root Files**:
- `main.tf`: Orchestrates all modules, creates S3 bucket, installs Helm charts
- `variables.tf`: All configurable parameters
- `outputs.tf`: Important values for K8s setup
- `versions.tf`: Terraform and provider versions
- `terraform.tfvars.example`: Template for your configuration

**Modules**:

1. **VPC Module** (`modules/vpc/`)
   - Creates VPC with 3 AZs
   - Private and public subnets
   - NAT gateways for outbound traffic
   - VPC endpoints for AWS services

2. **EKS Cluster Module** (`modules/eks-cluster/`)
   - EKS control plane with encryption
   - 3 node groups: ClickHouse, Keeper, General
   - CloudWatch logging
   - OIDC provider for IRSA

3. **IAM Module** (`modules/iam/`)
   - IRSA roles for:
     - ClickHouse Operator
     - Backup service
     - EBS CSI Driver
     - Load Balancer Controller
     - Cluster Autoscaler

### Kubernetes (`k8s/`)

Kubernetes configurations for ClickHouse deployment.

**Manifests**:

1. **namespace.yaml**: ClickHouse namespace with pod security standards
2. **storageclass-gp3.yaml**: gp3 EBS volumes with encryption
3. **keeper-config.yaml**: ClickHouse Keeper (3 replicas)
4. **clickhouse-chi.yaml**: Main ClickHouse cluster (3 shards × 2 replicas)
5. **svc-nlb-clickhouse.yaml**: Network Load Balancers for external access
6. **clickhouse-backup-cronjob.yaml**: Daily S3 backups
7. **prometheus-operator-values.yaml**: Monitoring stack configuration

**Helm Values**:

1. **clickhouse-operator-values.yaml**: Altinity operator configuration
2. **aws-load-balancer-controller-values.yaml**: AWS LB controller settings

### IAM Policies (`iam-policies/`)

JSON policy documents for AWS IAM roles.

1. **s3-backup-policy.json**: S3 bucket access for backups
2. **loadbalancer-controller-policy.json**: Full LB controller permissions
3. **ebs-csi-policy.json**: EBS volume management

### Scripts (`scripts/`)

Automation for deployment and testing.

1. **bootstrap.sh**:
   - Configures kubectl
   - Installs cert-manager
   - Installs ClickHouse Operator
   - Deploys Keeper and ClickHouse
   - Sets up monitoring
   - ~10-15 minutes execution time

2. **smoke-test.sh**:
   - 13 comprehensive tests
   - Validates entire stack
   - Connection tests
   - Query execution
   - Replication status

### Documentation (`docs/`)

Operational guides and best practices.

1. **runbook.md**:
   - Daily operations
   - Monitoring & alerting
   - Backup & restore procedures
   - Incident response
   - Maintenance procedures

2. **security.md**:
   - Security architecture
   - Authentication & authorization
   - Network security
   - Data encryption
   - Secrets management
   - Compliance guidelines

3. **scaling-guide.md**:
   - Horizontal scaling (add shards)
   - Vertical scaling (increase resources)
   - Storage expansion
   - Node scaling
   - Auto-scaling configuration
   - Capacity planning

## Usage Flow

```
1. Configure terraform.tfvars
2. terraform apply (creates AWS infrastructure)
3. ./scripts/bootstrap.sh (deploys K8s components)
4. ./scripts/smoke-test.sh (validates deployment)
5. Access ClickHouse via kubectl or load balancer
6. Monitor via Grafana
7. Backups run automatically daily
```

## Key Design Decisions

### Why These Technologies?

- **Altinity Operator**: Industry standard for ClickHouse on K8s
- **ClickHouse Keeper**: Native coordination (no ZooKeeper dependency)
- **EBS gp3**: Best cost/performance for ClickHouse workloads
- **IRSA**: Secure AWS access without credentials
- **Prometheus**: De facto K8s monitoring standard
- **Network Load Balancer**: Layer 4, high performance

### Architecture Choices

- **3 AZs**: High availability across failure domains
- **Dedicated Node Groups**: Isolate workloads, optimize resources
- **Private Subnets**: Security best practice
- **Pod Anti-Affinity**: Distribute replicas across nodes/AZs
- **PodDisruptionBudgets**: Safe during node maintenance

## Resource Allocation

### Default Configuration

| Component | Instances | Instance Type | CPU | Memory | Storage |
|-----------|-----------|---------------|-----|--------|---------|
| ClickHouse | 6 | r5.2xlarge | 8 | 64GB | 500GB each |
| Keeper | 3 | t3.medium | 2 | 4GB | 20GB each |
| General | 2 | t3.large | 2 | 8GB | 50GB each |

### Total Capacity

- **CPU**: 72 vCPUs (48 for ClickHouse)
- **Memory**: 416GB (384GB for ClickHouse)
- **Storage**: 3TB (replicated: 1.5TB usable)

## Security Features

✅ Implemented:
- IRSA for all service accounts
- Encrypted EBS volumes (AWS KMS)
- Encrypted S3 backups
- Private subnets for all pods
- Security groups
- Pod Security Standards (baseline)
- No hardcoded credentials
- CloudWatch audit logs

⚠️ Recommended for Production:
- TLS for ClickHouse connections
- Network policies
- Secrets Manager integration
- VPC Flow Logs
- GuardDuty

## Monitoring

### Grafana Dashboards

1. ClickHouse Overview (GrafanaLabs 14192)
2. Kubernetes Cluster (GrafanaLabs 7249)
3. Node Exporter (GrafanaLabs 1860)

### Pre-configured Alerts

- ClickHouse pod down
- High CPU/memory usage
- Disk space warnings (20% and 10%)
- Replication lag (>300s)
- Read-only replicas

## Cost Breakdown

Default configuration in us-west-2:

| Resource | Monthly Cost |
|----------|--------------|
| EKS Control Plane | $73 |
| EC2 (6× r5.2xlarge) | $2,016 |
| EC2 (3× t3.medium) | $91 |
| EC2 (2× t3.large) | $121 |
| NAT Gateways (3) | $97 |
| EBS (3TB) | $300 |
| S3 + transfer | $50 |
| **Total** | **~$2,750/month** |

## Maintenance

### Regular Tasks

- **Daily**: Check pod health, review logs
- **Weekly**: Review metrics, check backup success
- **Monthly**: Test restore, review capacity, update documentation
- **Quarterly**: Security audit, update versions, cost review
- **Annually**: Disaster recovery drill, architecture review

## Support

- Issues: GitHub Issues
- Community: ClickHouse Slack
- Professional: Altinity Support
- Documentation: This repository

## Version Information

- **Terraform**: >= 1.5.0
- **Kubernetes**: 1.28
- **ClickHouse**: 23.8.9.54
- **ClickHouse Keeper**: 23.8.9.54
- **Altinity Operator**: 0.23.4
- **AWS EBS CSI Driver**: v1.26.1
- **AWS Load Balancer Controller**: v2.6.2
- **Prometheus Stack**: 55.5.0

