# Documentation Index

Quick reference guide to all documentation in this repository.

## 🚀 Getting Started

### [QUICKSTART.md](QUICKSTART.md)
**Start here if you're deploying for the first time**
- Prerequisites checklist
- Step-by-step deployment (< 30 minutes)
- Initial access and verification
- First database and queries
- Cleanup instructions

### [Getting Started Tutorial](docs/getting-started-tutorial.md) 📚
**Comprehensive guide to using ClickHouse**
- **Connection Methods**: kubectl, load balancer, HTTP, GUI tools
- **Database Operations**: CREATE, DROP, USE
- **Table Creation**: Basic tables, partitions, TTL, replicated, distributed
- **Data Insertion**: Single rows, bulk inserts, CSV, JSON, Parquet
- **Querying**: SELECT, WHERE, JOIN, aggregations, window functions
- **Advanced Features**: Arrays, JSON parsing, materialized views
- **Best Practices**: Performance optimization tips
- **Troubleshooting**: Common issues and solutions

## 📖 Core Documentation

### [README.md](README.md)
**Main project documentation**
- Architecture overview
- Feature list
- Quick start guide
- Accessing ClickHouse
- Monitoring with Grafana
- Backup and restore
- Scaling operations
- Cost estimation
- Cleanup procedures

### [PROJECT_STRUCTURE.md](PROJECT_STRUCTURE.md)
**Understanding the repository**
- Complete file structure
- Explanation of each component
- Terraform modules breakdown
- Kubernetes manifests guide
- Design decisions and rationale
- Resource allocation details

### [DEPLOYMENT_CHECKLIST.md](DEPLOYMENT_CHECKLIST.md)
**Step-by-step deployment validation**
- Pre-deployment checklist
- Phase-by-phase deployment steps
- Post-deployment verification
- Production readiness checklist
- Common issues and solutions
- Rollback procedures
- Success criteria

## 🔧 Operations

### [Runbook](docs/runbook.md)
**Day-to-day operations and incident response**

**Contents**:
1. **Daily Operations**
   - Health checks
   - Query cluster status
   - Log review

2. **Monitoring & Alerting**
   - Key metrics to monitor
   - Alert response procedures
   - Grafana access

3. **Backup & Restore**
   - Manual backup procedures
   - Full cluster restore
   - Single table restore
   - Monthly restore testing

4. **Scaling Operations**
   - Horizontal scaling (add shards)
   - Vertical scaling (resize resources)
   - Storage expansion
   - Node group scaling

5. **Incident Response**
   - Complete cluster outage
   - Data corruption
   - Keeper quorum lost
   - High query latency

6. **Maintenance Procedures**
   - ClickHouse version upgrade
   - Kubernetes version upgrade
   - Certificate rotation

7. **Disaster Recovery**
   - Recovery procedures (RTO: 2 hours)
   - Backup validation
   - DR drills

## 🔒 Security

### [Security Guide](docs/security.md)
**Comprehensive security documentation**

**Contents**:
1. **Security Overview**
   - Security principles
   - Current security posture

2. **Infrastructure Security**
   - VPC configuration
   - EKS security
   - Pod security standards

3. **Authentication & Authorization**
   - ClickHouse users and roles
   - Kubernetes RBAC
   - Password management

4. **Network Security**
   - Security groups
   - Network policies
   - Load balancer security

5. **Data Encryption**
   - Encryption at rest (EBS, S3)
   - Encryption in transit (TLS)

6. **Secrets Management**
   - Current implementation
   - AWS Secrets Manager integration
   - External Secrets Operator

7. **Access Control**
   - IAM roles (IRSA)
   - ClickHouse access control
   - Row and column-level security

8. **Audit & Compliance**
   - CloudTrail configuration
   - Query logging
   - VPC Flow Logs
   - SOC 2 / ISO 27001 checklist

9. **Security Hardening**
   - Pod security
   - Image security
   - Kubernetes hardening

10. **Incident Response**
    - Security incident playbook
    - Containment procedures
    - Investigation steps

## 📈 Scaling

### [Scaling Guide](docs/scaling-guide.md)
**Strategies for growing your cluster**

**Contents**:
1. **Scaling Overview**
   - When to scale
   - Trade-offs comparison

2. **Horizontal Scaling (Shards & Replicas)**
   - Add new shard (increase capacity)
   - Add replicas (improve availability)
   - Remove/decommission shard

3. **Vertical Scaling (Resources)**
   - Scale CPU and memory
   - Memory sizing guidelines
   - CPU sizing guidelines

4. **Storage Scaling**
   - Expand volume size (online)
   - Change volume type
   - Storage recommendations

5. **Node Scaling**
   - Add EKS nodes
   - Change node instance type

6. **Auto-Scaling**
   - Cluster Autoscaler configuration
   - VPA considerations
   - HPA for read replicas

7. **Performance Optimization**
   - Query optimization
   - Table optimization
   - Index strategies

8. **Capacity Planning**
   - Storage estimation
   - Memory estimation
   - CPU estimation
   - Growth planning

9. **Troubleshooting**
   - Common scaling issues
   - Resolution procedures

## 🏗️ Infrastructure Code

### Terraform (`terraform/`)

**Main Files**:
- `main.tf` - Root configuration
- `variables.tf` - Input variables
- `outputs.tf` - Output values
- `versions.tf` - Provider versions
- `terraform.tfvars.example` - Configuration template

**Modules**:

#### VPC Module (`modules/vpc/`)
- Creates VPC with 3 AZs
- Private and public subnets
- NAT gateways
- VPC endpoints

#### EKS Cluster Module (`modules/eks-cluster/`)
- EKS control plane
- 3 node groups (ClickHouse, Keeper, General)
- KMS encryption
- OIDC provider

#### IAM Module (`modules/iam/`)
- IRSA roles for:
  - ClickHouse Operator
  - Backup service
  - EBS CSI Driver
  - Load Balancer Controller
  - Cluster Autoscaler

### Kubernetes (`k8s/`)

**Manifests** (`manifests/`):
- `namespace.yaml` - ClickHouse namespace
- `storageclass-gp3.yaml` - EBS storage class
- `keeper-config.yaml` - ClickHouse Keeper StatefulSet
- `clickhouse-chi.yaml` - Main ClickHouse cluster (CHI)
- `svc-nlb-clickhouse.yaml` - Network Load Balancers
- `clickhouse-backup-cronjob.yaml` - Backup CronJob
- `prometheus-operator-values.yaml` - Monitoring configuration

**Helm Values** (`helm-values/`):
- `clickhouse-operator-values.yaml` - Altinity operator
- `aws-load-balancer-controller-values.yaml` - AWS LB controller

### Scripts (`scripts/`)

**bootstrap.sh**:
- Deploys all Kubernetes components
- Installs operators and monitoring
- ~10-15 minutes execution time

**smoke-test.sh**:
- 13 comprehensive validation tests
- Tests pods, services, connectivity, queries
- ~2-3 minutes execution time

## 📋 IAM Policies

### `iam-policies/`

- `s3-backup-policy.json` - S3 backup bucket permissions
- `loadbalancer-controller-policy.json` - ELB management permissions
- `ebs-csi-policy.json` - EBS volume management permissions

## 🎯 Quick Reference

### Common Tasks

| Task | Documentation |
|------|---------------|
| Deploy cluster | [QUICKSTART.md](QUICKSTART.md) |
| Connect to ClickHouse | [Getting Started Tutorial](docs/getting-started-tutorial.md#connection-methods) |
| Create tables | [Getting Started Tutorial](docs/getting-started-tutorial.md#creating-tables) |
| Insert data | [Getting Started Tutorial](docs/getting-started-tutorial.md#inserting-data) |
| Query data | [Getting Started Tutorial](docs/getting-started-tutorial.md#querying-data) |
| Add shards | [Scaling Guide](docs/scaling-guide.md#horizontal-scaling-shards--replicas) |
| Increase resources | [Scaling Guide](docs/scaling-guide.md#vertical-scaling-resources) |
| Backup/restore | [Runbook](docs/runbook.md#backup--restore) |
| Handle incidents | [Runbook](docs/runbook.md#incident-response) |
| Security setup | [Security Guide](docs/security.md) |
| Monitor cluster | [Runbook](docs/runbook.md#monitoring--alerting) |

### Quick Commands

```bash
# Deploy
cd terraform && terraform apply
./scripts/bootstrap.sh

# Verify
./scripts/smoke-test.sh

# Connect
kubectl exec -it -n clickhouse $POD -- clickhouse-client

# Monitor
kubectl get pods -n clickhouse
kubectl logs -n clickhouse -l app=clickhouse
kubectl top pods -n clickhouse

# Scale
kubectl edit chi -n clickhouse clickhouse-cluster

# Backup
kubectl create job -n clickhouse backup-$(date +%s) --from=cronjob/clickhouse-backup
```

## 🆘 Troubleshooting Guides

| Issue | Reference |
|-------|-----------|
| Connection problems | [Getting Started Tutorial - Troubleshooting](docs/getting-started-tutorial.md#troubleshooting) |
| Query performance | [Getting Started Tutorial - Best Practices](docs/getting-started-tutorial.md#best-practices) |
| Pod not starting | [DEPLOYMENT_CHECKLIST.md - Common Issues](DEPLOYMENT_CHECKLIST.md#common-issues--solutions) |
| Replication lag | [Runbook - Alert Response](docs/runbook.md#alert-replication-lag) |
| Storage issues | [Getting Started Tutorial - Storage Issues](docs/getting-started-tutorial.md#storage-issues) |
| Security incident | [Security Guide - Incident Response](docs/security.md#incident-response) |
| Scaling issues | [Scaling Guide - Troubleshooting](docs/scaling-guide.md#troubleshooting) |

## 📞 Support Resources

- **Internal Documentation**: This repository
- **Official ClickHouse Docs**: https://clickhouse.com/docs
- **Altinity Operator Docs**: https://docs.altinity.com/clickhouseoperator/
- **AWS EKS Best Practices**: https://aws.github.io/aws-eks-best-practices/
- **Community**: ClickHouse Slack - https://clickhouse.com/slack
- **Professional Support**: Altinity - https://altinity.com/support/

## 🔄 Documentation Updates

This documentation should be reviewed and updated:
- **After incidents**: Update runbook with lessons learned
- **After scaling**: Update capacity planning estimates
- **Quarterly**: Review all documentation for accuracy
- **Before major changes**: Ensure procedures are current

---

**Last Updated**: 2025-01-27

**Version**: 1.0

**Maintainers**: Platform Engineering Team
