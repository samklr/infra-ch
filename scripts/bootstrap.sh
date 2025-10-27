#!/bin/bash
set -euo pipefail

# Bootstrap script for ClickHouse on EKS
# This script installs all necessary Kubernetes components after Terraform has provisioned the infrastructure

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."

    local missing_tools=()

    for tool in kubectl helm aws terraform; do
        if ! command -v "$tool" &> /dev/null; then
            missing_tools+=("$tool")
        fi
    done

    if [ ${#missing_tools[@]} -ne 0 ]; then
        log_error "Missing required tools: ${missing_tools[*]}"
        log_error "Please install them before running this script"
        exit 1
    fi

    log_info "All prerequisites are installed"
}

# Get Terraform outputs
get_terraform_outputs() {
    log_info "Retrieving Terraform outputs..."

    cd "${PROJECT_ROOT}/terraform"

    CLUSTER_NAME=$(terraform output -raw cluster_name)
    AWS_REGION=$(terraform output -raw configure_kubectl | grep -oP 'region \K\S+')
    BACKUP_BUCKET=$(terraform output -raw backup_s3_bucket_name)
    BACKUP_ROLE_ARN=$(terraform output -raw clickhouse_backup_role_arn)
    OPERATOR_ROLE_ARN=$(terraform output -raw clickhouse_operator_role_arn)
    ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    VPC_ID=$(terraform output -raw vpc_id)

    log_info "Cluster Name: ${CLUSTER_NAME}"
    log_info "AWS Region: ${AWS_REGION}"
    log_info "Backup Bucket: ${BACKUP_BUCKET}"

    cd "${PROJECT_ROOT}"
}

# Configure kubectl
configure_kubectl() {
    log_info "Configuring kubectl..."
    aws eks update-kubeconfig --region "${AWS_REGION}" --name "${CLUSTER_NAME}"

    # Wait for cluster to be ready
    log_info "Waiting for cluster to be ready..."
    kubectl wait --for=condition=Ready nodes --all --timeout=300s || true
}

# Install cert-manager (required for webhooks)
install_cert_manager() {
    log_info "Installing cert-manager..."

    if kubectl get namespace cert-manager &> /dev/null; then
        log_warn "cert-manager namespace already exists, skipping installation"
        return
    fi

    kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.3/cert-manager.yaml

    log_info "Waiting for cert-manager to be ready..."
    kubectl wait --for=condition=Available --timeout=300s \
        deployment/cert-manager \
        deployment/cert-manager-cainjector \
        deployment/cert-manager-webhook \
        -n cert-manager
}

# Install ClickHouse Operator
install_clickhouse_operator() {
    log_info "Installing ClickHouse Operator..."

    # Create namespace
    kubectl apply -f "${PROJECT_ROOT}/k8s/manifests/namespace.yaml"

    # Update Helm values with actual ARNs
    local values_file="${PROJECT_ROOT}/k8s/helm-values/clickhouse-operator-values.yaml"
    sed -i.bak "s|ACCOUNT_ID|${ACCOUNT_ID}|g" "$values_file"
    sed -i.bak "s|CLUSTER_NAME|${CLUSTER_NAME}|g" "$values_file"

    # Add Altinity Helm repo
    helm repo add altinity https://docs.altinity.com/clickhouse-operator/
    helm repo update

    # Install or upgrade
    helm upgrade --install clickhouse-operator altinity/altinity-clickhouse-operator \
        --namespace clickhouse \
        --values "$values_file" \
        --version 0.23.4 \
        --wait \
        --timeout 10m

    log_info "ClickHouse Operator installed successfully"
}

# Apply StorageClass
apply_storageclass() {
    log_info "Applying StorageClass..."
    kubectl apply -f "${PROJECT_ROOT}/k8s/manifests/storageclass-gp3.yaml"
}

# Deploy ClickHouse Keeper
deploy_keeper() {
    log_info "Deploying ClickHouse Keeper..."
    kubectl apply -f "${PROJECT_ROOT}/k8s/manifests/keeper-config.yaml"

    log_info "Waiting for Keeper pods to be ready..."
    kubectl wait --for=condition=Ready pod -l app=clickhouse-keeper -n clickhouse --timeout=600s
}

# Deploy ClickHouse cluster
deploy_clickhouse() {
    log_info "Deploying ClickHouse cluster..."
    kubectl apply -f "${PROJECT_ROOT}/k8s/manifests/clickhouse-chi.yaml"

    log_info "Waiting for ClickHouse pods to be ready (this may take 10-15 minutes)..."
    # Wait for the CHI to be created first
    sleep 30

    # Check if pods are being created
    log_info "ClickHouse pods are being provisioned. This may take several minutes..."
    kubectl get pods -n clickhouse -l app=clickhouse -w --timeout=900s || true
}

# Deploy load balancers
deploy_load_balancers() {
    log_info "Deploying load balancers..."
    kubectl apply -f "${PROJECT_ROOT}/k8s/manifests/svc-nlb-clickhouse.yaml"

    log_info "Waiting for load balancers to be provisioned..."
    sleep 60

    # Get load balancer endpoints
    log_info "Load Balancer Endpoints:"
    kubectl get svc -n clickhouse -l app=clickhouse -o wide
}

# Deploy backup CronJob
deploy_backup() {
    log_info "Deploying backup CronJob..."

    # Update backup config with actual values
    local backup_file="${PROJECT_ROOT}/k8s/manifests/clickhouse-backup-cronjob.yaml"
    sed -i.bak "s|ACCOUNT_ID|${ACCOUNT_ID}|g" "$backup_file"
    sed -i.bak "s|CLUSTER_NAME|${CLUSTER_NAME}|g" "$backup_file"
    sed -i.bak "s|BACKUP_BUCKET_NAME|${BACKUP_BUCKET}|g" "$backup_file"

    kubectl apply -f "$backup_file"

    log_info "Backup CronJob deployed successfully"
}

# Install monitoring
install_monitoring() {
    log_info "Installing monitoring stack (Prometheus + Grafana)..."

    # Add Prometheus community Helm repo
    helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
    helm repo update

    # Install kube-prometheus-stack
    helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
        --namespace monitoring \
        --create-namespace \
        --values "${PROJECT_ROOT}/k8s/manifests/prometheus-operator-values.yaml" \
        --version 55.5.0 \
        --wait \
        --timeout 10m

    log_info "Monitoring stack installed successfully"

    # Get Grafana endpoint
    log_info "Waiting for Grafana load balancer..."
    sleep 30
    GRAFANA_ENDPOINT=$(kubectl get svc -n monitoring kube-prometheus-stack-grafana -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
    log_info "Grafana URL: http://${GRAFANA_ENDPOINT}"
    log_info "Grafana admin password: admin_changeme (CHANGE THIS IN PRODUCTION!)"
}

# Print summary
print_summary() {
    log_info "========================================"
    log_info "Bootstrap completed successfully!"
    log_info "========================================"
    log_info ""
    log_info "Cluster Name: ${CLUSTER_NAME}"
    log_info "Namespace: clickhouse"
    log_info ""
    log_info "ClickHouse Endpoints:"
    kubectl get svc -n clickhouse
    log_info ""
    log_info "Next steps:"
    log_info "1. Run ./scripts/smoke-test.sh to verify the installation"
    log_info "2. Change default passwords in production!"
    log_info "3. Configure TLS for production use"
    log_info "4. Review and update backup schedule"
    log_info ""
    log_info "Useful commands:"
    log_info "  kubectl get pods -n clickhouse"
    log_info "  kubectl logs -n clickhouse -l app=clickhouse"
    log_info "  kubectl exec -it -n clickhouse clickhouse-cluster-0-0-0 -- clickhouse-client"
}

# Main execution
main() {
    log_info "Starting ClickHouse on EKS bootstrap..."

    check_prerequisites
    get_terraform_outputs
    configure_kubectl
    apply_storageclass
    install_cert_manager
    install_clickhouse_operator
    deploy_keeper
    deploy_clickhouse
    deploy_load_balancers
    deploy_backup
    install_monitoring
    print_summary

    log_info "Bootstrap complete!"
}

# Run main function
main "$@"
