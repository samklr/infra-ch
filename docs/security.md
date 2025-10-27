# ClickHouse on EKS Security Guide

This guide covers security best practices, configurations, and compliance considerations for running ClickHouse on AWS EKS.

## Table of Contents

1. [Security Overview](#security-overview)
2. [Infrastructure Security](#infrastructure-security)
3. [Authentication & Authorization](#authentication--authorization)
4. [Network Security](#network-security)
5. [Data Encryption](#data-encryption)
6. [Secrets Management](#secrets-management)
7. [Access Control](#access-control)
8. [Audit & Compliance](#audit--compliance)
9. [Security Hardening](#security-hardening)
10. [Incident Response](#incident-response)

---

## Security Overview

### Security Principles

1. **Defense in Depth**: Multiple layers of security controls
2. **Least Privilege**: Minimal permissions for all entities
3. **Zero Trust**: Verify everything, trust nothing
4. **Encryption Everywhere**: Data at rest and in transit
5. **Audit Everything**: Comprehensive logging and monitoring

### Current Security Posture

✅ **Implemented**:
- IRSA (IAM Roles for Service Accounts)
- Encrypted EBS volumes (AWS KMS)
- Encrypted S3 backups
- Private subnets for all workloads
- Security groups and network isolation
- Pod Security Standards (baseline)
- No hardcoded credentials

⚠️ **Recommended for Production**:
- TLS for ClickHouse client connections
- TLS for inter-node communication
- Network policies (Calico/Cilium)
- Pod Security Standards (restricted)
- AWS Secrets Manager integration
- GuardDuty and Security Hub
- VPC Flow Logs
- WAF for load balancers

---

## Infrastructure Security

### VPC Security

**Private Subnets**:
```
All ClickHouse, Keeper, and application pods run in private subnets with no direct internet access.
```

**NAT Gateways**:
```
Outbound internet access (for pulling images, AWS API calls) via NAT gateways in public subnets.
```

**VPC Endpoints**:
```hcl
# S3 VPC Endpoint (already configured)
resource "aws_vpc_endpoint" "s3" {
  vpc_id       = aws_vpc.main.id
  service_name = "com.amazonaws.${var.region}.s3"
}

# Add ECR endpoints for private image pulling
resource "aws_vpc_endpoint" "ecr_api" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.region}.ecr.api"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = var.private_subnet_ids
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
}

resource "aws_vpc_endpoint" "ecr_dkr" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.region}.ecr.dkr"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = var.private_subnet_ids
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
}
```

### EKS Security

**Control Plane**:
- Kubernetes secrets encrypted at rest using AWS KMS
- Control plane logs enabled (API, audit, authenticator)
- Public endpoint with IP allowlist (optional):

```hcl
resource "aws_eks_cluster" "main" {
  # ...
  vpc_config {
    endpoint_public_access  = true
    public_access_cidrs     = ["YOUR_OFFICE_IP/32"]  # Restrict access
  }
}
```

**Node Groups**:
- All nodes in private subnets
- IMDSv2 required (Instance Metadata Service):

```hcl
resource "aws_eks_node_group" "clickhouse" {
  # ...

  # Enable IMDSv2
  launch_template {
    metadata_options {
      http_endpoint               = "enabled"
      http_tokens                 = "required"  # IMDSv2
      http_put_response_hop_limit = 1
    }
  }
}
```

**Pod Security**:

Enable Pod Security Standards:

```yaml
# k8s/manifests/namespace.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: clickhouse
  labels:
    pod-security.kubernetes.io/enforce: restricted  # Most restrictive
    pod-security.kubernetes.io/audit: restricted
    pod-security.kubernetes.io/warn: restricted
```

Update ClickHouse pods to meet restricted PSS:

```yaml
# k8s/manifests/clickhouse-chi.yaml
spec:
  securityContext:
    runAsNonRoot: true
    runAsUser: 101
    fsGroup: 101
    seccompProfile:
      type: RuntimeDefault

  containers:
    - name: clickhouse
      securityContext:
        allowPrivilegeEscalation: false
        capabilities:
          drop:
            - ALL
        readOnlyRootFilesystem: false  # ClickHouse needs writable /tmp
```

---

## Authentication & Authorization

### ClickHouse Users

**Change default passwords immediately**:

```yaml
# k8s/manifests/clickhouse-chi.yaml
configuration:
  users:
    # Admin user
    admin/password_sha256_hex: "HASHED_PASSWORD"  # Use SHA256 hash
    admin/networks/ip: ["10.0.0.0/8"]  # Restrict to VPC

    # Application user (least privilege)
    app_user/password_sha256_hex: "HASHED_PASSWORD"
    app_user/profile: "app_profile"
    app_user/quota: "app_quota"
    app_user/networks/ip: ["10.0.0.0/8"]

    # Read-only user
    readonly_user/password_sha256_hex: "HASHED_PASSWORD"
    readonly_user/profile: "readonly"
    readonly_user/readonly: "1"
```

Generate SHA256 password hash:

```bash
echo -n 'your_password' | sha256sum | tr -d '-'
```

**User Profiles** (resource limits):

```yaml
profiles:
  app_profile/max_memory_usage: "10000000000"  # 10GB
  app_profile/max_execution_time: "300"  # 5 minutes
  app_profile/max_concurrent_queries_for_user: "10"
  app_profile/readonly: "0"

  readonly/readonly: "1"
  readonly/max_execution_time: "60"
```

**Quotas**:

```yaml
quotas:
  app_quota/interval/duration: "3600"
  app_quota/interval/queries: "1000"
  app_quota/interval/errors: "100"
  app_quota/interval/result_rows: "10000000000"
  app_quota/interval/read_rows: "10000000000"
  app_quota/interval/execution_time: "3600"
```

### Kubernetes RBAC

**Service Account for Applications**:

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: clickhouse-app
  namespace: clickhouse

---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: clickhouse-app-role
  namespace: clickhouse
rules:
  - apiGroups: [""]
    resources: ["services"]
    resourceNames: ["clickhouse-cluster"]
    verbs: ["get"]

---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: clickhouse-app-binding
  namespace: clickhouse
subjects:
  - kind: ServiceAccount
    name: clickhouse-app
    namespace: clickhouse
roleRef:
  kind: Role
  name: clickhouse-app-role
  apiGroup: rbac.authorization.k8s.io
```

---

## Network Security

### Security Groups

EKS automatically creates security groups. Verify they follow least privilege:

```bash
# Check EKS cluster security group
aws ec2 describe-security-groups \
  --filters "Name=tag:aws:eks:cluster-name,Values=YOUR_CLUSTER_NAME"
```

**Recommended rules**:
- Cluster SG: Allow 443 (HTTPS) from trusted CIDRs only
- Node SG: Allow required ports only (10250, 53, etc.)
- ClickHouse pods: Restrict to VPC CIDR + load balancer SG

### Network Policies

Install Calico or Cilium for network policies:

```bash
# Install Calico
kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.26.1/manifests/calico.yaml
```

**Deny all by default**:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: deny-all
  namespace: clickhouse
spec:
  podSelector: {}
  policyTypes:
    - Ingress
    - Egress
```

**Allow ClickHouse ingress**:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: clickhouse-ingress
  namespace: clickhouse
spec:
  podSelector:
    matchLabels:
      app: clickhouse
  policyTypes:
    - Ingress
  ingress:
    # Allow from load balancer
    - from:
        - namespaceSelector:
            matchLabels:
              name: kube-system
      ports:
        - protocol: TCP
          port: 8123
        - protocol: TCP
          port: 9000
    # Allow from same namespace (inter-pod)
    - from:
        - namespaceSelector:
            matchLabels:
              name: clickhouse
      ports:
        - protocol: TCP
          port: 9000
        - protocol: TCP
          port: 9009  # Interserver
```

**Allow ClickHouse egress**:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: clickhouse-egress
  namespace: clickhouse
spec:
  podSelector:
    matchLabels:
      app: clickhouse
  policyTypes:
    - Egress
  egress:
    # Allow DNS
    - to:
        - namespaceSelector:
            matchLabels:
              name: kube-system
      ports:
        - protocol: UDP
          port: 53
    # Allow Keeper
    - to:
        - podSelector:
            matchLabels:
              app: clickhouse-keeper
      ports:
        - protocol: TCP
          port: 2181
    # Allow other ClickHouse nodes
    - to:
        - podSelector:
            matchLabels:
              app: clickhouse
      ports:
        - protocol: TCP
          port: 9000
        - protocol: TCP
          port: 9009
    # Allow S3 (via VPC endpoint or NAT)
    - to:
        - namespaceSelector: {}
      ports:
        - protocol: TCP
          port: 443
```

### Load Balancer Security

**Restrict NLB access**:

```yaml
# k8s/manifests/svc-nlb-clickhouse.yaml
metadata:
  annotations:
    # Make internal only
    service.beta.kubernetes.io/aws-load-balancer-scheme: "internal"

    # Or restrict source IPs
    service.beta.kubernetes.io/load-balancer-source-ranges: "YOUR_VPN_CIDR/24,YOUR_OFFICE_IP/32"
```

**Enable access logs**:

```yaml
metadata:
  annotations:
    service.beta.kubernetes.io/aws-load-balancer-access-log-enabled: "true"
    service.beta.kubernetes.io/aws-load-balancer-access-log-s3-bucket-name: "your-logs-bucket"
    service.beta.kubernetes.io/aws-load-balancer-access-log-s3-bucket-prefix: "nlb-logs"
```

---

## Data Encryption

### Encryption at Rest

**EBS Volumes** (already configured):

```yaml
# k8s/manifests/storageclass-gp3.yaml
parameters:
  encrypted: "true"  # Uses AWS default KMS key
  # Or specify custom key:
  # kmsKeyId: "arn:aws:kms:region:account-id:key/key-id"
```

**S3 Backups** (already configured):

```hcl
# terraform/main.tf
resource "aws_s3_bucket_server_side_encryption_configuration" "clickhouse_backups" {
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
      # Or use KMS:
      # sse_algorithm     = "aws:kms"
      # kms_master_key_id = aws_kms_key.s3.arn
    }
  }
}
```

### Encryption in Transit

**TLS for Client Connections**:

1. Generate certificates (use cert-manager):

```yaml
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: clickhouse-tls
  namespace: clickhouse
spec:
  secretName: clickhouse-tls-secret
  issuerRef:
    name: letsencrypt-prod
    kind: ClusterIssuer
  dnsNames:
    - clickhouse.example.com
    - "*.clickhouse.example.com"
```

2. Configure ClickHouse to use TLS:

```yaml
# Add to CHI
spec:
  configuration:
    files:
      config.d/ssl.xml: |
        <clickhouse>
          <openSSL>
            <server>
              <certificateFile>/etc/clickhouse-server/certs/tls.crt</certificateFile>
              <privateKeyFile>/etc/clickhouse-server/certs/tls.key</privateKeyFile>
              <verificationMode>none</verificationMode>
              <loadDefaultCAFile>true</loadDefaultCAFile>
              <cacheSessions>true</cacheSessions>
              <disableProtocols>sslv2,sslv3</disableProtocols>
              <preferServerCiphers>true</preferServerCiphers>
            </server>
          </openSSL>
          <https_port>8443</https_port>
          <tcp_port_secure>9440</tcp_port_secure>
        </clickhouse>

  templates:
    podTemplates:
      - name: clickhouse-pod
        spec:
          containers:
            - name: clickhouse
              volumeMounts:
                - name: tls-secret
                  mountPath: /etc/clickhouse-server/certs
                  readOnly: true
          volumes:
            - name: tls-secret
              secret:
                secretName: clickhouse-tls-secret
```

3. Update load balancer to use HTTPS:

```yaml
# k8s/manifests/svc-nlb-clickhouse.yaml
spec:
  ports:
    - name: https
      port: 8443
      targetPort: 8443
    - name: tcp-secure
      port: 9440
      targetPort: 9440
```

**TLS for Inter-node Communication**:

```yaml
# Add to CHI config
files:
  config.d/interserver.xml: |
    <clickhouse>
      <interserver_https_port>9010</interserver_https_port>
      <interserver_http_credentials>
        <user>interserver</user>
        <password_sha256_hex>HASHED_PASSWORD</password_sha256_hex>
      </interserver_http_credentials>
    </clickhouse>
```

---

## Secrets Management

### Current Implementation (Kubernetes Secrets)

Passwords are stored in CHI manifest (not ideal):

```yaml
users:
  admin/password: "changeme"  # ❌ Plain text in manifest
```

### Recommended: AWS Secrets Manager

1. **Store secrets in AWS Secrets Manager**:

```bash
aws secretsmanager create-secret \
  --name clickhouse/admin-password \
  --secret-string "your-secure-password"
```

2. **Install External Secrets Operator**:

```bash
helm repo add external-secrets https://charts.external-secrets.io
helm install external-secrets \
  external-secrets/external-secrets \
  -n external-secrets-system \
  --create-namespace
```

3. **Create SecretStore**:

```yaml
apiVersion: external-secrets.io/v1beta1
kind: SecretStore
metadata:
  name: aws-secrets-manager
  namespace: clickhouse
spec:
  provider:
    aws:
      service: SecretsManager
      region: us-west-2
      auth:
        jwt:
          serviceAccountRef:
            name: clickhouse-operator
```

4. **Create ExternalSecret**:

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: clickhouse-passwords
  namespace: clickhouse
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: aws-secrets-manager
    kind: SecretStore
  target:
    name: clickhouse-passwords
    creationPolicy: Owner
  data:
    - secretKey: admin-password
      remoteRef:
        key: clickhouse/admin-password
```

5. **Update CHI to use secret**:

```yaml
users:
  admin/password:
    valueFrom:
      secretKeyRef:
        name: clickhouse-passwords
        key: admin-password
```

---

## Access Control

### IAM Roles (IRSA)

**Principle**: Each service account has dedicated IAM role with minimal permissions.

**Current roles**:
- `clickhouse-operator`: CloudWatch logs
- `clickhouse-backup`: S3 backup bucket access only
- `aws-load-balancer-controller`: ELB management
- `ebs-csi-driver`: EBS volume management

**Verify IRSA**:

```bash
# Check service account annotation
kubectl get sa -n clickhouse clickhouse-backup -o yaml

# Verify pod has AWS credentials
kubectl exec -n clickhouse <backup-pod> -- env | grep AWS

# Test S3 access
kubectl exec -n clickhouse <backup-pod> -- \
  aws s3 ls s3://your-backup-bucket/
```

### ClickHouse Access Control

**Row-level security** (example):

```sql
-- Create access control table
CREATE TABLE users.access_control
(
    user_id UInt64,
    department String
) ENGINE = Memory;

-- Create view with RLS
CREATE VIEW users.orders_restricted AS
SELECT * FROM users.orders
WHERE department = currentUser();

-- Grant access
GRANT SELECT ON users.orders_restricted TO app_user;
REVOKE SELECT ON users.orders FROM app_user;
```

**Column-level security**:

```sql
-- Create role
CREATE ROLE sensitive_data_reader;

-- Grant specific columns
GRANT SELECT(id, name, created_at) ON users.customers TO sensitive_data_reader;

-- Deny access to sensitive columns (email, phone)
```

---

## Audit & Compliance

### AWS CloudTrail

Enable CloudTrail for all API calls:

```hcl
resource "aws_cloudtrail" "main" {
  name                          = "${var.cluster_name}-trail"
  s3_bucket_name                = aws_s3_bucket.cloudtrail.id
  include_global_service_events = true
  is_multi_region_trail         = true
  enable_log_file_validation    = true

  event_selector {
    read_write_type           = "All"
    include_management_events = true

    data_resource {
      type   = "AWS::S3::Object"
      values = ["arn:aws:s3:::${aws_s3_bucket.clickhouse_backups.id}/*"]
    }
  }
}
```

### ClickHouse Query Logging

Enable query logging:

```yaml
# Add to CHI
configuration:
  settings:
    log_queries: "1"
    log_query_threads: "1"
```

Query audit logs:

```sql
SELECT
    type,
    event_time,
    user,
    query_id,
    query,
    exception
FROM system.query_log
WHERE event_date = today()
  AND type IN ('QueryStart', 'QueryFinish', 'ExceptionWhileProcessing')
ORDER BY event_time DESC
LIMIT 100;
```

### VPC Flow Logs

```hcl
resource "aws_flow_log" "main" {
  vpc_id               = module.vpc.vpc_id
  traffic_type         = "ALL"
  log_destination_type = "s3"
  log_destination      = aws_s3_bucket.flow_logs.arn

  tags = var.tags
}
```

### Compliance Reports

**SOC 2 / ISO 27001 checklist**:

- [ ] Encryption at rest (EBS, S3)
- [ ] Encryption in transit (TLS)
- [ ] Access control (RBAC, IAM)
- [ ] Audit logging (CloudTrail, query logs)
- [ ] Backup and retention policies
- [ ] Incident response procedures
- [ ] Vulnerability scanning
- [ ] Penetration testing
- [ ] Change management process

---

## Security Hardening

### Pod Security

**Run as non-root**:

```yaml
securityContext:
  runAsNonRoot: true
  runAsUser: 101
  fsGroup: 101
```

**Read-only root filesystem** (where possible):

```yaml
securityContext:
  readOnlyRootFilesystem: true

volumeMounts:
  - name: tmp
    mountPath: /tmp
  - name: var-run
    mountPath: /var/run

volumes:
  - name: tmp
    emptyDir: {}
  - name: var-run
    emptyDir: {}
```

### Image Security

**Use minimal base images**:

```dockerfile
# Use Alpine or distroless
FROM clickhouse/clickhouse-server:23.8-alpine
```

**Scan images regularly**:

```bash
# Using Trivy
trivy image clickhouse/clickhouse-server:23.8

# Using AWS ECR scanning
aws ecr start-image-scan --repository-name clickhouse --image-id imageTag=23.8
```

### Kubernetes Hardening

**Disable service account token auto-mount**:

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: default
  namespace: clickhouse
automountServiceAccountToken: false
```

**Limit service account permissions**:

```bash
# Remove default SA permissions
kubectl annotate sa -n clickhouse default \
  "kubernetes.io/enforce-mountable-secrets=true"
```

---

## Incident Response

### Security Incident Playbook

**1. Detection**:
- Monitor GuardDuty findings
- Review CloudTrail anomalies
- Check ClickHouse query logs for suspicious activity

**2. Containment**:

```bash
# Isolate compromised pod
kubectl label pod -n clickhouse <pod-name> quarantine=true

# Update NetworkPolicy to block traffic
kubectl apply -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: quarantine
  namespace: clickhouse
spec:
  podSelector:
    matchLabels:
      quarantine: "true"
  policyTypes:
    - Ingress
    - Egress
  # No rules = deny all
EOF

# Revoke IAM credentials if compromised
aws iam update-access-key --access-key-id <key-id> --status Inactive
```

**3. Investigation**:

```bash
# Collect pod logs
kubectl logs -n clickhouse <pod-name> --previous > pod-logs.txt

# Get pod events
kubectl describe pod -n clickhouse <pod-name> > pod-describe.txt

# Analyze query logs
kubectl exec -n clickhouse <pod-name> -- clickhouse-client -q "
  SELECT * FROM system.query_log
  WHERE event_time > now() - interval 1 hour
  ORDER BY event_time DESC
" > query-logs.txt

# Check network connections
kubectl exec -n clickhouse <pod-name> -- netstat -tuln
```

**4. Eradication**:

```bash
# Delete compromised pod
kubectl delete pod -n clickhouse <pod-name>

# Rotate credentials
./scripts/rotate-credentials.sh

# Update security rules
kubectl apply -f k8s/manifests/network-policies/
```

**5. Recovery**:

```bash
# Restore from known-good backup
./scripts/restore-backup.sh <backup-date>

# Verify integrity
./scripts/smoke-test.sh

# Monitor for 24 hours
```

**6. Lessons Learned**:
- Document incident
- Update runbooks
- Improve detections

---

## Security Checklist

### Pre-Production

- [ ] Change all default passwords
- [ ] Enable TLS for client connections
- [ ] Enable TLS for inter-node communication
- [ ] Configure network policies
- [ ] Restrict load balancer access
- [ ] Enable audit logging
- [ ] Set up alerting for security events
- [ ] Perform vulnerability scan
- [ ] Review IAM policies (least privilege)
- [ ] Enable MFA for AWS console access
- [ ] Document security procedures

### Post-Deployment

- [ ] Regular security audits (quarterly)
- [ ] Penetration testing (annually)
- [ ] Rotate credentials (quarterly)
- [ ] Review access logs (monthly)
- [ ] Update dependencies (monthly)
- [ ] Test incident response (quarterly)
- [ ] Backup testing (monthly)

---

*This security guide should be reviewed quarterly and updated based on new threats and best practices.*
