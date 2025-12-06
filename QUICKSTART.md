# ClickHouse on Kubernetes - Quick Start Guide

Get a production-ready ClickHouse cluster running on AWS EKS or GCP GKE in under 30 minutes.

## Prerequisites

### Common Tools
```bash
terraform --version # >= 1.5.0
kubectl version     # >= 1.28
helm version        # >= 3.12
```

### Provider Specific
- **AWS**: `aws` CLI v2 configured
- **GCP**: `gcloud` CLI configured

## Step 1: Choose Your Cloud Provider

### Option A: AWS EKS

1. **Configure Credentials**:
   ```bash
   aws configure
   ```

2. **Clone and Configure**:
   ```bash
   git clone <repo-url>
   cd clickhouse-eks-deploy
   
   # Configure Terraform
   cat > terraform/terraform.tfvars <<EOF
   aws_region                     = "us-west-2"
   environment                    = "prod"
   cluster_name                   = "clickhouse-eks"
   availability_zones             = ["us-west-2a", "us-west-2b", "us-west-2c"]
   
   # Node configuration
   clickhouse_node_instance_type  = "r5.2xlarge"
   clickhouse_node_count          = 6
   EOF
   ```

3. **Deploy Infrastructure**:
   ```bash
   cd terraform
   terraform init
   terraform apply
   ```

4. **Bootstrap Kubernetes**:
   ```bash
   cd ..
   ./scripts/bootstrap.sh
   ```

### Option B: GCP GKE

1. **Configure Credentials**:
   ```bash
   gcloud auth login
   gcloud auth application-default login
   ```

2. **Clone and Configure**:
   ```bash
   git clone <repo-url>
   cd clickhouse-eks-deploy
   
   # Configure Terraform
   cd terraform-gke
   cp terraform.tfvars.example terraform.tfvars
   
   # Edit terraform.tfvars
   # Set project_id, region, etc.
   # Optional: Set regional = false for single-zone cluster
   ```

3. **Deploy Infrastructure**:
   ```bash
   terraform init
   terraform apply
   ```

4. **Deploy ClickHouse**:
   ```bash
   # Get Cluster Credentials
   gcloud container clusters get-credentials $(terraform output -raw cluster_name) --region $(terraform output -raw region)
   
   # Install ClickHouse Operator
   kubectl apply -f https://github.com/Altinity/clickhouse-operator/raw/master/deploy/operator/clickhouse-operator-install-bundle.yaml
   
   # Install ClickHouse Cluster
   cd ..
   helm install clickhouse k8s/charts/clickhouse-gke
   ```

## Step 2: Verify Installation

```bash
./scripts/smoke-test.sh
```

Expected output: All tests pass ✓

## Step 3: Access ClickHouse

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
# Note: On GKE, this might be an IP address instead of a hostname

# HTTP query
curl "http://${LB}:8123?query=SELECT%20version()"
```

## Step 4: Access Grafana

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
```

## Next Steps

### 📚 **Start Here: [Getting Started Tutorial](docs/getting-started-tutorial.md)**

Complete tutorial covering:
- All connection methods
- Creating databases and tables
- Inserting and querying data
- Best practices

### Cleanup

```bash
# Delete Kubernetes resources
kubectl delete chi -n clickhouse clickhouse-cluster
kubectl delete ns clickhouse monitoring

# Wait for load balancers to be deleted
sleep 120

# Destroy infrastructure
# For AWS:
cd terraform && terraform destroy
# For GCP:
cd terraform-gke && terraform destroy
```

