# ClickHouse on EKS - Quick Start Guide

Get a production-ready ClickHouse cluster running on AWS EKS in under 30 minutes.

## Prerequisites

```bash
# Check you have all required tools
aws --version       # AWS CLI v2
terraform --version # >= 1.5.0
kubectl version     # >= 1.28
helm version        # >= 3.12
```

## Step 1: Configure AWS Credentials

```bash
aws configure
# Enter your AWS Access Key ID, Secret Access Key, and Region
```

## Step 2: Clone and Configure

```bash
# Clone this repository
git clone <repo-url>
cd clickhouse-eks-deploy

# Create Terraform variables file
cat > terraform/terraform.tfvars <<EOF
aws_region                     = "us-west-2"
environment                    = "prod"
cluster_name                   = "clickhouse-eks"
availability_zones             = ["us-west-2a", "us-west-2b", "us-west-2c"]

# Node configuration (adjust for your needs)
clickhouse_node_instance_type  = "r5.2xlarge"
clickhouse_node_count          = 6
keeper_node_instance_type      = "t3.medium"
keeper_node_count              = 3
general_node_instance_type     = "t3.large"
general_node_count             = 2

# Backups
backup_retention_days          = 30
enable_cluster_autoscaler      = true
EOF
```

## Step 3: Deploy Infrastructure (~15-20 minutes)

```bash
cd terraform
terraform init
terraform plan    # Review changes
terraform apply   # Type 'yes' to confirm
```

This creates:
- VPC with 3 AZs
- EKS cluster
- 3 node groups (ClickHouse, Keeper, General)
- IAM roles
- S3 backup bucket
- EBS CSI driver & Load Balancer Controller

## Step 4: Bootstrap Kubernetes (~10-15 minutes)

```bash
cd ..
./scripts/bootstrap.sh
```

This installs:
- ClickHouse Operator
- ClickHouse Keeper (3 nodes)
- ClickHouse Cluster (6 nodes)
- Network Load Balancer
- Prometheus + Grafana
- Backup CronJob

## Step 5: Verify Installation

```bash
./scripts/smoke-test.sh
```

Expected output: All 13 tests pass ✓

## Step 6: Access ClickHouse

### Get Connection Info

```bash
# Get ClickHouse pods
kubectl get pods -n clickhouse -l app=clickhouse

# Get load balancer endpoint
kubectl get svc -n clickhouse clickhouse-http-nlb
```

### Connect via kubectl

```bash
# Get pod name
POD=$(kubectl get pods -n clickhouse -l app=clickhouse -o jsonpath='{.items[0].metadata.name}')

# Connect with clickhouse-client
kubectl exec -it -n clickhouse $POD -- clickhouse-client

# Try a query
SELECT version();
```

### Connect via Load Balancer

```bash
# Get endpoint
LB=$(kubectl get svc -n clickhouse clickhouse-http-nlb -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

# HTTP query
curl "http://${LB}:8123?query=SELECT%20version()"

# Or use clickhouse-client (install locally first)
clickhouse-client --host $LB --port 9000
```

## Step 7: Access Grafana

```bash
# Get Grafana URL
GRAFANA=$(kubectl get svc -n monitoring kube-prometheus-stack-grafana -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
echo "Grafana: http://${GRAFANA}"

# Default credentials
# Username: admin
# Password: admin_changeme
```

## Quick Commands

```bash
# View all pods
kubectl get pods -n clickhouse

# View logs
kubectl logs -n clickhouse -l app=clickhouse --tail=100

# Check cluster status
kubectl get chi -n clickhouse

# Run a query
kubectl exec -n clickhouse $POD -- clickhouse-client -q "SELECT * FROM system.clusters"

# Check backups
kubectl get cronjob -n clickhouse

# Manual backup
kubectl create job -n clickhouse manual-backup-$(date +%s) --from=cronjob/clickhouse-backup

# View metrics
kubectl top pods -n clickhouse
kubectl top nodes
```

## Next Steps

### 📚 **Start Here: [Getting Started Tutorial](docs/getting-started-tutorial.md)**

Complete tutorial covering:
- All connection methods (kubectl, load balancer, GUI tools)
- Creating databases and tables
- Inserting data (single rows, bulk, from files)
- Querying data (filtering, aggregations, joins, time-series)
- Advanced features (arrays, JSON, window functions)
- Best practices and troubleshooting

### Other Important Tasks

1. **Change Default Passwords** (Important!)
   ```bash
   # Edit CHI manifest
   kubectl edit chi -n clickhouse clickhouse-cluster
   # Update users/admin/password and users/default/password
   ```

2. **Try the Quick Example**
   ```sql
   kubectl exec -it -n clickhouse $POD -- clickhouse-client

   CREATE DATABASE mydb;

   CREATE TABLE mydb.events (
       event_date Date,
       event_time DateTime,
       user_id UInt64,
       event_type String
   ) ENGINE = MergeTree()
   PARTITION BY toYYYYMM(event_date)
   ORDER BY (event_date, user_id);

   INSERT INTO mydb.events VALUES
       ('2024-01-01', '2024-01-01 12:00:00', 1, 'login'),
       ('2024-01-01', '2024-01-01 12:05:00', 2, 'signup');

   SELECT * FROM mydb.events;
   ```

3. **Set Up TLS** (Production)
   - See [docs/security.md](docs/security.md)

4. **Configure Monitoring Alerts**
   - See [docs/runbook.md](docs/runbook.md)

5. **Test Backups**
   ```bash
   # Run manual backup
   kubectl create job -n clickhouse test-backup --from=cronjob/clickhouse-backup

   # Check backup in S3
   aws s3 ls s3://$(terraform output -raw backup_s3_bucket_name)/
   ```

## Cleanup (When Done Testing)

```bash
# Delete Kubernetes resources first
kubectl delete chi -n clickhouse clickhouse-cluster
kubectl delete ns clickhouse monitoring

# Wait for load balancers to be deleted (~2 minutes)
sleep 120

# Destroy infrastructure
cd terraform
terraform destroy  # Type 'yes' to confirm
```

**Warning**: This deletes everything including backups (unless you configure S3 bucket retention).

## Troubleshooting

### Pods Not Starting

```bash
kubectl describe pod -n clickhouse <pod-name>
kubectl logs -n clickhouse <pod-name>
kubectl get events -n clickhouse --sort-by='.lastTimestamp'
```

### Can't Connect

```bash
# Check service status
kubectl get svc -n clickhouse

# Check if load balancer is provisioned
kubectl describe svc -n clickhouse clickhouse-http-nlb

# Test from within cluster
kubectl run -it --rm debug --image=busybox --restart=Never -- sh
wget -O- http://clickhouse-cluster:8123
```

### Terraform Errors

```bash
# If terraform state is corrupted
cd terraform
terraform state list
terraform state rm <resource>  # If needed

# If resources already exist
terraform import <resource> <id>
```

## Cost Estimate

Monthly costs for the default configuration (us-west-2):

| Resource | Cost |
|----------|------|
| EKS Control Plane | $73 |
| EC2 Instances (6× r5.2xlarge) | ~$2,016 |
| EC2 Instances (3× t3.medium) | ~$91 |
| EC2 Instances (2× t3.large) | ~$121 |
| NAT Gateways (3) | ~$97 |
| EBS Volumes (3TB total) | ~$300 |
| Load Balancers | ~$20 |
| **Total** | **~$2,700/month** |

**Cost Optimization Tips**:
- Use Spot instances for non-critical workloads
- Use single NAT gateway for dev/staging
- Reduce node count for smaller workloads
- Enable EBS autoscaling to avoid over-provisioning

## Support

- **Documentation**: See [docs/](docs/) directory
- **Issues**: Report at [GitHub Issues]
- **Community**: [ClickHouse Slack]
- **Professional**: [Altinity Support](https://altinity.com/support/)

## Resources

- [ClickHouse Documentation](https://clickhouse.com/docs)
- [Altinity Operator Docs](https://docs.altinity.com/clickhouseoperator/)
- [AWS EKS Best Practices](https://aws.github.io/aws-eks-best-practices/)
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)

---

**Ready to Deploy?** Start with Step 1! 🚀
