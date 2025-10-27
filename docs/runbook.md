# ClickHouse on EKS Operational Runbook

This runbook provides step-by-step procedures for common operational tasks and incident response.

## Table of Contents

1. [Daily Operations](#daily-operations)
2. [Monitoring & Alerting](#monitoring--alerting)
3. [Backup & Restore](#backup--restore)
4. [Scaling Operations](#scaling-operations)
5. [Incident Response](#incident-response)
6. [Maintenance Procedures](#maintenance-procedures)
7. [Disaster Recovery](#disaster-recovery)

---

## Daily Operations

### Health Checks

Run these checks daily to ensure cluster health:

```bash
# 1. Check all pods are running
kubectl get pods -n clickhouse

# 2. Check ClickHouseInstallation status
kubectl get chi -n clickhouse clickhouse-cluster -o wide

# 3. Check node health
kubectl get nodes

# 4. Check PVC status
kubectl get pvc -n clickhouse

# 5. Check load balancer health
kubectl get svc -n clickhouse
```

### Query Cluster Status

```bash
# Get cluster topology
kubectl exec -n clickhouse $POD -- clickhouse-client -q "
SELECT
    cluster,
    shard_num,
    replica_num,
    host_name,
    port
FROM system.clusters
WHERE cluster = 'clickhouse-cluster'
ORDER BY shard_num, replica_num
"

# Check replication status
kubectl exec -n clickhouse $POD -- clickhouse-client -q "
SELECT
    database,
    table,
    is_leader,
    is_readonly,
    absolute_delay,
    queue_size,
    inserts_in_queue,
    merges_in_queue
FROM system.replicas
"

# Check disk usage
kubectl exec -n clickhouse $POD -- clickhouse-client -q "
SELECT
    name,
    path,
    formatReadableSize(free_space) AS free,
    formatReadableSize(total_space) AS total,
    formatReadableSize(keep_free_space) AS reserved
FROM system.disks
"
```

### Review Logs

```bash
# Recent ClickHouse errors
kubectl logs -n clickhouse -l app=clickhouse --tail=500 | grep -i error

# Operator logs
kubectl logs -n clickhouse -l app=clickhouse-operator --tail=100

# Recent events
kubectl get events -n clickhouse --sort-by='.lastTimestamp' | tail -20
```

---

## Monitoring & Alerting

### Access Grafana

```bash
# Get Grafana URL
kubectl get svc -n monitoring kube-prometheus-stack-grafana \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
```

Login: `admin` / `admin_changeme`

### Key Metrics to Monitor

1. **CPU Usage**
   - Alert threshold: >80% for 10 minutes
   - Action: Consider vertical or horizontal scaling

2. **Memory Usage**
   - Alert threshold: >85% for 10 minutes
   - Action: Review queries, increase memory limits

3. **Disk Usage**
   - Warning: <20% free space
   - Critical: <10% free space
   - Action: Expand volumes or clean old data

4. **Replication Lag**
   - Alert threshold: >300 seconds
   - Action: Check network, Keeper connectivity

5. **Query Performance**
   - Monitor slow queries (>10s)
   - Review query logs in system.query_log

### Alert Response

#### Alert: ClickHouse Pod Down

```bash
# 1. Check pod status
kubectl describe pod -n clickhouse <pod-name>

# 2. Check logs
kubectl logs -n clickhouse <pod-name> --previous

# 3. Check events
kubectl get events -n clickhouse --field-selector involvedObject.name=<pod-name>

# 4. If pod is crashlooping, check:
kubectl exec -n clickhouse <pod-name> -- df -h
kubectl exec -n clickhouse <pod-name> -- ps aux

# 5. Restart if needed (operator will recreate)
kubectl delete pod -n clickhouse <pod-name>
```

#### Alert: High Disk Usage

```bash
# 1. Check current usage
kubectl exec -n clickhouse $POD -- clickhouse-client -q "
SELECT
    database,
    table,
    formatReadableSize(sum(bytes)) AS size
FROM system.parts
WHERE active
GROUP BY database, table
ORDER BY sum(bytes) DESC
LIMIT 20
"

# 2. Drop old partitions if applicable
kubectl exec -n clickhouse $POD -- clickhouse-client -q "
ALTER TABLE database.table DROP PARTITION 'partition_id'
"

# 3. Or expand volume (see Scaling Operations)
```

#### Alert: Replication Lag

```bash
# 1. Check replication status
kubectl exec -n clickhouse $POD -- clickhouse-client -q "
SELECT * FROM system.replicas WHERE absolute_delay > 60
"

# 2. Check Keeper connectivity
kubectl exec -n clickhouse $POD -- clickhouse-client -q "
SELECT * FROM system.zookeeper WHERE path = '/'
"

# 3. Check network between pods
kubectl exec -n clickhouse $POD -- ping -c 3 <other-pod-ip>

# 4. Restart replica if stuck
kubectl exec -n clickhouse $POD -- clickhouse-client -q "
SYSTEM RESTART REPLICA database.table
"
```

---

## Backup & Restore

### Manual Backup

```bash
# 1. Trigger manual backup
kubectl create job -n clickhouse manual-backup-$(date +%s) \
  --from=cronjob/clickhouse-backup

# 2. Monitor backup progress
kubectl logs -n clickhouse job/manual-backup-<id> -f

# 3. Verify backup in S3
aws s3 ls s3://<bucket-name>/clickhouse-backups/
```

### Restore Full Cluster

```bash
# 1. List available backups
kubectl exec -n clickhouse $POD -- clickhouse-backup list remote

# 2. Download backup
kubectl exec -n clickhouse $POD -- clickhouse-backup download <backup-name>

# 3. Stop writes (set cluster readonly)
kubectl exec -n clickhouse $POD -- clickhouse-client -q "
SYSTEM STOP DISTRIBUTED SENDS;
SET readonly = 1;
"

# 4. Restore
kubectl exec -n clickhouse $POD -- clickhouse-backup restore <backup-name>

# 5. Verify data
kubectl exec -n clickhouse $POD -- clickhouse-client -q "
SELECT database, table, count() FROM system.tables GROUP BY database, table
"

# 6. Resume writes
kubectl exec -n clickhouse $POD -- clickhouse-client -q "
SET readonly = 0;
SYSTEM START DISTRIBUTED SENDS;
"
```

### Restore Single Table

```bash
# 1. Download backup
kubectl exec -n clickhouse $POD -- clickhouse-backup download <backup-name>

# 2. Restore specific table
kubectl exec -n clickhouse $POD -- clickhouse-backup restore --table=database.table <backup-name>

# 3. Verify
kubectl exec -n clickhouse $POD -- clickhouse-client -q "SELECT count() FROM database.table"
```

### Test Restore (Monthly)

Schedule monthly restore tests:

```bash
# 1. Create test namespace
kubectl create namespace clickhouse-restore-test

# 2. Deploy minimal ClickHouse instance
# (Use simplified CHI manifest)

# 3. Restore latest backup
# 4. Run validation queries
# 5. Clean up test environment
```

---

## Scaling Operations

### Horizontal Scaling (Add Shards)

**Downtime**: Minimal (read-only during schema migration)

```bash
# 1. Update CHI manifest
kubectl edit chi -n clickhouse clickhouse-cluster

# Increment shardsCount:
#   shardsCount: 4  # was 3

# 2. Operator will create new pods automatically
kubectl get pods -n clickhouse -w

# 3. Verify new shard
kubectl exec -n clickhouse $POD -- clickhouse-client -q "
SELECT * FROM system.clusters WHERE cluster = 'clickhouse-cluster'
"

# 4. Redistribute data (if using Distributed tables)
# Run manual INSERT INTO SELECT with sharding key
```

### Vertical Scaling (Resize Pods)

**Downtime**: Rolling restart (~5-10 min per pod)

```bash
# 1. Update CHI manifest resources
kubectl edit chi -n clickhouse clickhouse-cluster

# Update under podTemplates -> resources:
#   requests:
#     memory: "32Gi"
#     cpu: "8"
#   limits:
#     memory: "64Gi"
#     cpu: "16"

# 2. Operator performs rolling update
kubectl get pods -n clickhouse -w

# 3. Monitor during update
kubectl logs -n clickhouse -l app=clickhouse-operator -f
```

### Storage Expansion

**Downtime**: None (online operation)

```bash
# 1. Edit PVC
kubectl edit pvc -n clickhouse data-volume-clickhouse-cluster-0-0-0

# Increase storage:
#   storage: 1Ti  # was 500Gi

# 2. Repeat for all PVCs

# 3. Verify expansion
kubectl get pvc -n clickhouse

# 4. ClickHouse will automatically detect new space
kubectl exec -n clickhouse $POD -- df -h /var/lib/clickhouse
```

### Node Group Scaling (Add Nodes)

```bash
# 1. Update Terraform variables
cd terraform
# Edit terraform.tfvars:
#   clickhouse_node_count = 8  # was 6

# 2. Apply
terraform apply

# 3. Verify new nodes
kubectl get nodes -l role=clickhouse

# 4. No action needed - pods will use new nodes on next restart
```

---

## Incident Response

### Scenario: Complete Cluster Outage

**Symptoms**: All ClickHouse pods down, no connectivity

**Response**:

```bash
# 1. Assess situation
kubectl get pods -n clickhouse
kubectl get nodes
kubectl get events -n clickhouse --sort-by='.lastTimestamp'

# 2. Check control plane
kubectl get pods -n kube-system

# 3. Check Keeper (critical for recovery)
kubectl get pods -n clickhouse -l app=clickhouse-keeper

# 4. If Keeper is down, restore it first
kubectl delete pod -n clickhouse -l app=clickhouse-keeper
# Wait for Keeper quorum (2/3 pods minimum)

# 5. Once Keeper is healthy, ClickHouse pods should recover
kubectl delete pod -n clickhouse -l app=clickhouse

# 6. Monitor recovery
kubectl get pods -n clickhouse -w

# 7. Verify data integrity
./scripts/smoke-test.sh
```

### Scenario: Data Corruption

**Symptoms**: Query errors, inconsistent results

**Response**:

```bash
# 1. Identify affected table
kubectl exec -n clickhouse $POD -- clickhouse-client -q "
CHECK TABLE database.table
"

# 2. Try to repair
kubectl exec -n clickhouse $POD -- clickhouse-client -q "
OPTIMIZE TABLE database.table FINAL
"

# 3. If repair fails, restore from backup
# See "Restore Single Table" above

# 4. Verify data
# Run validation queries
```

### Scenario: Keeper Quorum Lost

**Symptoms**: ClickHouse readonly, "No active session with Keeper"

**Response**:

```bash
# 1. Check Keeper pod status
kubectl get pods -n clickhouse -l app=clickhouse-keeper

# 2. Check Keeper logs
kubectl logs -n clickhouse clickhouse-keeper-0

# 3. Restart Keeper pods one by one
kubectl delete pod -n clickhouse clickhouse-keeper-0
# Wait for pod to be Running
kubectl delete pod -n clickhouse clickhouse-keeper-1
# Wait...
kubectl delete pod -n clickhouse clickhouse-keeper-2

# 4. Verify quorum restored
kubectl exec -n clickhouse clickhouse-keeper-0 -- \
  bash -c 'echo ruok | nc localhost 2181'
# Expected: imok

# 5. Restart ClickHouse replicas if needed
kubectl rollout restart statefulset -n clickhouse
```

### Scenario: High Query Latency

**Symptoms**: Slow queries, timeouts

**Response**:

```bash
# 1. Identify slow queries
kubectl exec -n clickhouse $POD -- clickhouse-client -q "
SELECT
    query_id,
    user,
    query_duration_ms,
    query
FROM system.query_log
WHERE type = 'QueryFinish'
  AND query_duration_ms > 10000
ORDER BY query_duration_ms DESC
LIMIT 10
"

# 2. Kill long-running query if needed
kubectl exec -n clickhouse $POD -- clickhouse-client -q "
KILL QUERY WHERE query_id = '<query_id>'
"

# 3. Check resource usage
kubectl top pods -n clickhouse
kubectl top nodes

# 4. Review query and add indexes if needed
# Check execution plan:
kubectl exec -n clickhouse $POD -- clickhouse-client -q "
EXPLAIN SELECT ...
"
```

---

## Maintenance Procedures

### ClickHouse Version Upgrade

**Frequency**: Quarterly (or as needed for security patches)

**Downtime**: ~10-15 minutes (rolling update)

```bash
# 1. Review release notes
# https://clickhouse.com/docs/en/whats-new/changelog/

# 2. Test in staging environment first

# 3. Backup before upgrade
kubectl create job -n clickhouse pre-upgrade-backup-$(date +%s) \
  --from=cronjob/clickhouse-backup

# 4. Update CHI manifest
kubectl edit chi -n clickhouse clickhouse-cluster
# Change image version:
#   image: clickhouse/clickhouse-server:24.1.1.1

# 5. Monitor rolling update
kubectl get pods -n clickhouse -w

# 6. Verify each pod after restart
kubectl exec -n clickhouse $POD -- clickhouse-client -q "SELECT version()"

# 7. Run smoke tests
./scripts/smoke-test.sh

# 8. Monitor for 24 hours
# Check error logs, query performance, replication
```

### Kubernetes Version Upgrade

**Frequency**: Annually (or as needed)

**Downtime**: Minimal (rolling node upgrades)

```bash
# 1. Review EKS upgrade guide
# https://docs.aws.amazon.com/eks/latest/userguide/update-cluster.html

# 2. Upgrade control plane (in Terraform)
# Edit terraform.tfvars:
#   cluster_version = "1.29"

cd terraform
terraform plan
terraform apply

# 3. Upgrade node groups
# Terraform will create new launch templates
# Then manually upgrade each node group or use Terraform

# 4. Drain and upgrade nodes one by one
kubectl drain <node-name> --ignore-daemonsets --delete-emptydir-data
# Wait for pods to reschedule
# Terminate old node in AWS console
# New node will be created by autoscaling group

# 5. Verify cluster health
kubectl get nodes
kubectl get pods --all-namespaces
./scripts/smoke-test.sh
```

### Certificate Rotation

**Frequency**: Automatic (cert-manager handles renewal)

```bash
# Verify cert-manager is running
kubectl get pods -n cert-manager

# Check certificate status
kubectl get certificates --all-namespaces

# Manual renewal if needed
kubectl delete secret -n clickhouse <cert-secret-name>
# cert-manager will recreate
```

---

## Disaster Recovery

### Recovery Time Objective (RTO): 2 hours

### Recovery Point Objective (RPO): 24 hours (daily backups)

### DR Procedure

**Scenario**: Complete AWS region failure

**Prerequisites**:
- S3 backups replicated to another region
- Terraform code stored in version control
- DNS/load balancer failover configured

**Steps**:

```bash
# 1. Deploy infrastructure in DR region
cd terraform
# Update region in terraform.tfvars
terraform apply -var="aws_region=us-east-1"

# 2. Bootstrap Kubernetes
./scripts/bootstrap.sh

# 3. Restore from S3 backup
# List backups from primary region bucket
aws s3 ls s3://<primary-bucket>/clickhouse-backups/ --region us-west-2

# 4. Download and restore
kubectl exec -n clickhouse $POD -- clickhouse-backup download <backup-name>
kubectl exec -n clickhouse $POD -- clickhouse-backup restore <backup-name>

# 5. Update DNS to point to new region
# (Manual step or automated with Route53)

# 6. Verify application connectivity
./scripts/smoke-test.sh

# 7. Monitor for issues
```

### Backup Validation

**Frequency**: Monthly

```bash
# 1. List recent backups
aws s3 ls s3://<bucket>/clickhouse-backups/

# 2. Restore to test environment
# 3. Verify data integrity
# 4. Document results
```

---

## Contact Information

**On-Call Rotation**: PagerDuty / Opsgenie

**Escalation Path**:
1. Platform Engineer (L1)
2. Senior Platform Engineer (L2)
3. Platform Engineering Manager (L3)

**Vendor Support**:
- Altinity Support: https://altinity.com/support/
- AWS Support: https://console.aws.amazon.com/support/

---

## Useful Commands Reference

```bash
# Get a shell in ClickHouse pod
kubectl exec -it -n clickhouse $POD -- bash

# Run clickhouse-client
kubectl exec -it -n clickhouse $POD -- clickhouse-client

# Watch operator reconciliation
kubectl logs -n clickhouse -l app=clickhouse-operator -f

# Port-forward to local machine
kubectl port-forward -n clickhouse svc/clickhouse-cluster 8123:8123 9000:9000

# Get all resources in namespace
kubectl get all -n clickhouse

# Describe CHI for full status
kubectl describe chi -n clickhouse clickhouse-cluster

# Check pod resource usage
kubectl top pods -n clickhouse

# View persistent volume claims
kubectl get pvc -n clickhouse

# Force pod restart
kubectl rollout restart statefulset -n clickhouse <statefulset-name>
```

---

*This runbook should be reviewed and updated quarterly or after major incidents.*
