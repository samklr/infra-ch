# Production-Ready ClickHouse on AWS EKS and GCP GKE

This repository contains complete Infrastructure-as-Code (IaC) and Kubernetes manifests to deploy a production-ready ClickHouse cluster on AWS EKS and GCP GKE using the Altinity ClickHouse Operator and ClickHouse Keeper.

## Features

- **Production-Ready Infrastructure**: VPC with 3 AZs, private subnets, NAT gateways
- **Managed EKS Cluster**: Kubernetes 1.28 with dedicated node groups
- **ClickHouse Cluster**: 3 shards × 2 replicas across multiple availability zones
- **ClickHouse Keeper**: Native coordination service (no ZooKeeper)
- **High Availability**: Pod anti-affinity, topology spread, and PodDisruptionBudgets
- **Secure by Default**: IRSA, encrypted EBS volumes, encrypted S3 backups
- **Automated Backups**: Daily S3 backups with configurable retention
- **Monitoring**: Prometheus + Grafana with pre-configured dashboards and alerts
- **Autoscaling**: Cluster Autoscaler for dynamic node scaling
- **Load Balancer**: Network Load Balancer for external access

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                         AWS VPC                              │
│  ┌────────────────┬────────────────┬────────────────┐       │
│  │   AZ-1         │   AZ-2         │   AZ-3         │       │
│  │                │                │                │       │
│  │  ┌──────────┐  │  ┌──────────┐  │  ┌──────────┐  │       │
│  │  │PrivSubnet│  │  │PrivSubnet│  │  │PrivSubnet│  │       │
│  │  │          │  │  │          │  │  │          │  │       │
│  │  │ ┌──────┐ │  │  │ ┌──────┐ │  │  │ ┌──────┐ │  │       │
│  │  │ │CH Pod│ │  │  │ │CH Pod│ │  │  │ │CH Pod│ │  │       │
│  │  │ │      │ │  │  │ │      │ │  │  │ │      │ │  │       │
│  │  │ └──────┘ │  │  │ └──────┘ │  │  │ └──────┘ │  │       │
│  │  │ ┌──────┐ │  │  │ ┌──────┐ │  │  │ ┌──────┐ │  │       │
│  │  │ │Keeper│ │  │  │ │Keeper│ │  │  │ │Keeper│ │  │       │
│  │  │ └──────┘ │  │  │ └──────┘ │  │  │ └──────┘ │  │       │
│  │  └──────────┘  │  └──────────┘  │  └──────────┘  │       │
│  └────────────────┴────────────────┴────────────────┘       │
│                                                              │
│  ┌────────────────────────────────────────────┐             │
│  │     Network Load Balancer (NLB)            │             │
│  │  HTTP (8123) + Native (9000)               │             │
│  └────────────────────────────────────────────┘             │
└─────────────────────────────────────────────────────────────┘
```

## Prerequisites

- AWS Account with appropriate permissions
- AWS CLI v2 configured
- Terraform >= 1.5.0
- kubectl >= 1.28
- Helm >= 3.12
- bash
- gcloud CLI (for GKE)

## Quick Start

### 1. Clone and Configure

```bash
git clone <repository-url>
cd clickhouse-eks-deploy
```

### 2. Configure Terraform Variables

Create a `terraform/terraform.tfvars` file:

```hcl
aws_region                     = "us-west-2"
environment                    = "prod"
cluster_name                   = "clickhouse-eks"
cluster_version                = "1.28"
vpc_cidr                       = "10.0.0.0/16"
availability_zones             = ["us-west-2a", "us-west-2b", "us-west-2c"]

# Node configuration
clickhouse_node_instance_type  = "r5.2xlarge"
clickhouse_node_count          = 6  # 2 per AZ for 3 shards × 2 replicas
keeper_node_instance_type      = "t3.medium"
keeper_node_count              = 3
general_node_instance_type     = "t3.large"
general_node_count             = 2

# Backup configuration
backup_s3_bucket_name          = ""  # Auto-generated if empty
backup_retention_days          = 30

# Autoscaling
enable_cluster_autoscaler      = true
```

### 3. Deploy Infrastructure

```bash
cd terraform
terraform init
terraform plan
terraform apply
```

This will create:
- VPC with 3 AZs, private/public subnets, NAT gateways
- EKS cluster with 3 node groups (ClickHouse, Keeper, General)
- IAM roles with IRSA for secure AWS service access
- S3 bucket for backups
- EBS CSI driver and AWS Load Balancer Controller

**Time**: ~15-20 minutes

### 4. Bootstrap Kubernetes Components

```bash
cd ..
./scripts/bootstrap.sh
```

This will:
- Configure kubectl
- Install cert-manager
- Install Altinity ClickHouse Operator
- Deploy ClickHouse Keeper
- Deploy ClickHouse cluster
- Create load balancers
- Set up backup CronJob
- Install Prometheus + Grafana

**Time**: ~10-15 minutes

### 5. Verify Installation

```bash
./scripts/smoke-test.sh
```

This runs 13 comprehensive tests including:
- Pod health checks
- Connectivity tests
- Query execution
- Replication status
- Backup configuration

## GKE Deployment

### 1. Configure Terraform

```bash
cd terraform-gke
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your project details
```

### 2. Deploy Infrastructure

```bash
terraform init
terraform plan
terraform apply
```

### 3. Deploy ClickHouse

```bash
# Get credentials
gcloud container clusters get-credentials $(terraform output -raw cluster_name) --region $(terraform output -raw region)

# Install Operator
kubectl apply -f https://github.com/Altinity/clickhouse-operator/raw/master/deploy/operator/clickhouse-operator-install-bundle.yaml

# Install ClickHouse Chart
helm install clickhouse k8s/charts/clickhouse-gke
```

## Accessing ClickHouse

**See [Getting Started Tutorial](docs/getting-started-tutorial.md) for comprehensive guide on connecting, creating tables, and querying data.**

### Quick Access via kubectl (Internal)

```bash
# Get pod name
POD=$(kubectl get pods -n clickhouse -l app=clickhouse -o jsonpath='{.items[0].metadata.name}')

# Connect with clickhouse-client
kubectl exec -it -n clickhouse $POD -- clickhouse-client

# Run a query
kubectl exec -n clickhouse $POD -- clickhouse-client -q "SELECT version()"
```

### Quick Access via Load Balancer (External)

```bash
# Get load balancer endpoint
LB_ENDPOINT=$(kubectl get svc -n clickhouse clickhouse-http-nlb -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

# HTTP interface
curl "http://${LB_ENDPOINT}:8123?query=SELECT%20version()"

# Native client (install clickhouse-client locally)
clickhouse-client --host $LB_ENDPOINT --port 9000
```

## Monitoring

### Access Grafana

```bash
# Get Grafana endpoint
GRAFANA_URL=$(kubectl get svc -n monitoring kube-prometheus-stack-grafana -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
echo "http://${GRAFANA_URL}"
```

**Default credentials**: `admin` / `admin_changeme` (CHANGE IN PRODUCTION!)

### Pre-configured Dashboards

- ClickHouse Overview (ID: 14192)
- Kubernetes Cluster Monitoring (ID: 7249)
- Node Exporter (ID: 1860)

### Alerts

Pre-configured alerts for:
- ClickHouse down
- High CPU/Memory usage
- Disk space warnings
- Replication lag
- Readonly replicas

## Backup & Restore

### Manual Backup

```bash
# Create a manual backup job
kubectl create job -n clickhouse clickhouse-backup-manual-$(date +%s) \
  --from=cronjob/clickhouse-backup

# Check backup status
kubectl get jobs -n clickhouse
kubectl logs -n clickhouse job/clickhouse-backup-manual-<timestamp>
```

### Restore from Backup

```bash
# List available backups
kubectl exec -n clickhouse $CLICKHOUSE_POD -- clickhouse-backup list remote

# Download and restore a backup
kubectl exec -n clickhouse $CLICKHOUSE_POD -- clickhouse-backup download <backup-name>
kubectl exec -n clickhouse $CLICKHOUSE_POD -- clickhouse-backup restore <backup-name>
```

### Scheduled Backups

Backups run daily at 2 AM UTC (configured via CronJob). Modify the schedule in:
```yaml
k8s/manifests/clickhouse-backup-cronjob.yaml
```

## Scaling

### Horizontal Scaling (Add Nodes)

See [docs/scaling-guide.md](docs/scaling-guide.md) for detailed instructions.

Quick summary:
```bash
# Update node count in Terraform
terraform apply

# Update ClickHouse CHI manifest to add shards/replicas
kubectl edit chi -n clickhouse clickhouse-cluster
```

### Vertical Scaling (Resize Resources)

```bash
# Edit CHI to update resource requests/limits
kubectl edit chi -n clickhouse clickhouse-cluster

# Operator will perform rolling update
kubectl get pods -n clickhouse -w
```

### Storage Expansion

```bash
# EBS volumes support online expansion
kubectl edit pvc -n clickhouse <pvc-name>
# Update storage size, changes apply automatically
```

## Security

See [docs/security.md](docs/security.md) for comprehensive security guide.

Key security features:
- ✅ IRSA for pod-to-AWS authentication
- ✅ Encrypted EBS volumes (gp3 with AWS encryption)
- ✅ Encrypted S3 backups
- ✅ Private subnets for all workloads
- ✅ Security groups and network policies
- ✅ No hardcoded credentials

**Important**: Change default passwords in production:
```yaml
# k8s/manifests/clickhouse-chi.yaml
users:
  default/password: <change-me>
  admin/password: <change-me>
```

## Operations

### View Logs

```bash
# ClickHouse logs
kubectl logs -n clickhouse -l app=clickhouse --tail=100

# Keeper logs
kubectl logs -n clickhouse -l app=clickhouse-keeper --tail=100

# Operator logs
kubectl logs -n clickhouse -l app=clickhouse-operator --tail=100
```

### Check Cluster Status

```bash
# All pods
kubectl get pods -n clickhouse

# ClickHouseInstallation status
kubectl get chi -n clickhouse

# Services and endpoints
kubectl get svc,endpoints -n clickhouse

# PVCs
kubectl get pvc -n clickhouse
```

### Update ClickHouse Version

```bash
# Edit CHI to update image version
kubectl edit chi -n clickhouse clickhouse-cluster

# Change: image: clickhouse/clickhouse-server:23.8.9.54
# To:     image: clickhouse/clickhouse-server:24.1.1.1

# Operator performs rolling update automatically
```

## Troubleshooting

### Pod Not Starting

```bash
# Check pod status
kubectl describe pod -n clickhouse <pod-name>

# Check events
kubectl get events -n clickhouse --sort-by='.lastTimestamp'

# Check operator logs
kubectl logs -n clickhouse -l app=clickhouse-operator
```

### Connectivity Issues

```bash
# Test Keeper connectivity
kubectl exec -n clickhouse $POD -- clickhouse-client -q "SELECT * FROM system.zookeeper WHERE path='/'"

# Test inter-pod connectivity
kubectl exec -n clickhouse $POD -- nc -zv clickhouse-keeper-0.clickhouse-keeper-headless.clickhouse.svc.cluster.local 2181
```

### Backup Failures

```bash
# Check backup logs
kubectl logs -n clickhouse -l app=clickhouse-backup

# Test S3 access
kubectl exec -n clickhouse $BACKUP_POD -- aws s3 ls s3://<bucket-name>

# Verify IRSA configuration
kubectl describe sa -n clickhouse clickhouse-backup
```

## Cost Optimization

Estimated monthly costs (us-west-2):
- EKS cluster: ~$73
- EC2 instances (6× r5.2xlarge): ~$2,016
- NAT gateways (3): ~$97
- EBS volumes (500GB × 6): ~$300
- S3 storage: ~$23/TB
- Data transfer: Variable

**Total**: ~$2,500-3,000/month (depends on storage and traffic)

## Cleanup

```bash
# Delete Kubernetes resources first
kubectl delete chi -n clickhouse clickhouse-cluster
kubectl delete ns clickhouse monitoring

# Delete load balancers (wait for cleanup)
sleep 60

# Destroy infrastructure
cd terraform
terraform destroy
```

**Note**: Persistent volumes with `Retain` policy must be deleted manually if needed.

## Documentation

- **[Getting Started Tutorial](docs/getting-started-tutorial.md)** - Complete guide to connecting and using ClickHouse
- [Runbook](docs/runbook.md) - Operational procedures and incident response
- [Security Guide](docs/security.md) - Security best practices and compliance
- [Scaling Guide](docs/scaling-guide.md) - Horizontal and vertical scaling strategies

## Support

- [Altinity ClickHouse Operator Docs](https://docs.altinity.com/clickhouseoperator/)
- [ClickHouse Documentation](https://clickhouse.com/docs)
- [AWS EKS Best Practices](https://aws.github.io/aws-eks-best-practices/)

## License

This project is provided as-is for reference and educational purposes.

## Contributing

Contributions welcome! Please open an issue or pull request.
