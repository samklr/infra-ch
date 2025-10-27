# ClickHouse on EKS Scaling Guide

This guide covers strategies and procedures for scaling your ClickHouse cluster both horizontally and vertically.

## Table of Contents

1. [Scaling Overview](#scaling-overview)
2. [Horizontal Scaling (Shards & Replicas)](#horizontal-scaling-shards--replicas)
3. [Vertical Scaling (Resources)](#vertical-scaling-resources)
4. [Storage Scaling](#storage-scaling)
5. [Node Scaling](#node-scaling)
6. [Auto-Scaling](#auto-scaling)
7. [Performance Optimization](#performance-optimization)
8. [Capacity Planning](#capacity-planning)

---

## Scaling Overview

### When to Scale

**Scale Up (Vertical)**:
- High CPU usage (>80% sustained)
- High memory usage (>85% sustained)
- Query performance degradation
- OOM errors

**Scale Out (Horizontal - Add Shards)**:
- Need more storage capacity
- Need higher query throughput
- Data locality requirements
- Need to distribute hot data

**Add Replicas**:
- Need higher read availability
- Need better query distribution
- Improve fault tolerance
- Reduce single-point-of-failure risk

### Scaling Trade-offs

| Method | Pros | Cons | Downtime |
|--------|------|------|----------|
| Vertical (CPU/RAM) | Simple, no data redistribution | Limited by instance size | Rolling restart (~5-10 min) |
| Horizontal (Shards) | Linear scalability | Data redistribution required | Minimal |
| Add Replicas | Better availability | Storage overhead | None |
| Storage Expansion | Online operation | Can't shrink | None |

---

## Horizontal Scaling (Shards & Replicas)

### Add a New Shard

**Use Case**: Increase write throughput and storage capacity

**Downtime**: Minimal (no downtime for existing data)

**Steps**:

1. **Update CHI manifest**:

```bash
kubectl edit chi -n clickhouse clickhouse-cluster
```

Change:
```yaml
spec:
  configuration:
    clusters:
      - name: clickhouse-cluster
        layout:
          shardsCount: 4  # Increase from 3 to 4
          replicasCount: 2
```

2. **Monitor pod creation**:

```bash
kubectl get pods -n clickhouse -w
```

The operator will create new pods for shard 4 automatically.

3. **Verify new shard**:

```sql
SELECT cluster, shard_num, replica_num, host_name
FROM system.clusters
WHERE cluster = 'clickhouse-cluster'
ORDER BY shard_num, replica_num;
```

4. **Update Distributed tables** (if applicable):

```sql
-- Distributed tables automatically include new shards
-- No action needed if using cluster definition
SELECT * FROM system.tables WHERE engine = 'Distributed';
```

5. **Redistribute data** (optional):

For existing data on specific tables:

```sql
-- Move data to new shard based on sharding key
INSERT INTO distributed_table
SELECT * FROM local_table
WHERE toUInt64(sharding_key) % 4 = 3;  -- New shard (0-indexed: shard 3)

-- Verify distribution
SELECT
    _shard_num,
    count() as row_count
FROM distributed_table
GROUP BY _shard_num
ORDER BY _shard_num;
```

### Add Replicas

**Use Case**: Improve read availability and fault tolerance

**Downtime**: None

**Steps**:

1. **Update CHI manifest**:

```yaml
spec:
  configuration:
    clusters:
      - name: clickhouse-cluster
        layout:
          shardsCount: 3
          replicasCount: 3  # Increase from 2 to 3
```

2. **Apply changes**:

```bash
kubectl apply -f k8s/manifests/clickhouse-chi.yaml
```

3. **Monitor replication**:

```sql
SELECT
    database,
    table,
    total_replicas,
    active_replicas
FROM system.replicas
WHERE active_replicas < total_replicas;
```

Wait until all replicas are active.

4. **Verify data synchronization**:

```sql
SELECT
    database,
    table,
    replica_name,
    absolute_delay
FROM system.replicas
ORDER BY absolute_delay DESC;
```

### Remove a Shard (Decommission)

**⚠️ Caution**: Data must be migrated first

**Steps**:

1. **Stop writes to the shard**:

```sql
-- Mark shard as readonly in load balancer or app config
-- Or use ClickHouse settings:
SYSTEM STOP DISTRIBUTED SENDS;
```

2. **Migrate data**:

```sql
-- For replicated tables, data exists on other shards already
-- For non-replicated, migrate:
INSERT INTO distributed_table SELECT * FROM old_shard.local_table;
```

3. **Verify data migration**:

```sql
SELECT count() FROM old_shard.local_table;  -- Should be 0 or migrated
```

4. **Update CHI**:

```yaml
shardsCount: 2  # Decrease from 3 to 2
```

5. **Operator will remove the shard pods**

---

## Vertical Scaling (Resources)

### Scale CPU and Memory

**Use Case**: Handle larger queries, more concurrent users

**Downtime**: Rolling restart (~5-10 minutes per pod)

**Steps**:

1. **Determine new resource requirements**:

```bash
# Check current usage
kubectl top pods -n clickhouse

# Review historical metrics in Grafana
```

2. **Update CHI manifest**:

```bash
kubectl edit chi -n clickhouse clickhouse-cluster
```

Update resources:
```yaml
spec:
  templates:
    podTemplates:
      - name: clickhouse-pod
        spec:
          containers:
            - name: clickhouse
              resources:
                requests:
                  memory: "32Gi"   # Increased from 16Gi
                  cpu: "8"         # Increased from 4
                limits:
                  memory: "64Gi"   # Increased from 32Gi
                  cpu: "16"        # Increased from 8
```

3. **Operator performs rolling update**:

```bash
kubectl get pods -n clickhouse -w
```

Pods will restart one by one:
- Old pod terminates gracefully
- New pod starts with new resources
- Waits for readiness before proceeding to next pod

4. **Monitor during update**:

```bash
# Check events
kubectl get events -n clickhouse --sort-by='.lastTimestamp'

# Verify resources
kubectl describe pod -n clickhouse <pod-name> | grep -A 10 Requests
```

5. **Verify after update**:

```bash
# All pods running
kubectl get pods -n clickhouse

# Check resource allocation
kubectl top pods -n clickhouse
```

### Recommendations

**Memory Sizing**:
- **Requests**: 50-70% of expected usage
- **Limits**: 1.5-2x requests (allow burst)
- **Rule of thumb**: 1GB RAM per 1 million rows (varies by schema)

**CPU Sizing**:
- **Requests**: Average usage + 20% buffer
- **Limits**: 2-3x requests for burst queries
- **Monitor**: CPU throttling (container_cpu_cfs_throttled_seconds_total)

---

## Storage Scaling

### Expand Volume Size

**Use Case**: Running out of disk space

**Downtime**: None (online operation)

**Steps**:

1. **Check current usage**:

```bash
kubectl get pvc -n clickhouse

kubectl exec -n clickhouse <pod-name> -- df -h /var/lib/clickhouse
```

2. **Edit PVC**:

```bash
kubectl edit pvc -n clickhouse data-volume-clickhouse-cluster-0-0-0
```

Increase size:
```yaml
spec:
  resources:
    requests:
      storage: 1Ti  # Increased from 500Gi
```

3. **Repeat for all PVCs**:

```bash
# List all PVCs
kubectl get pvc -n clickhouse | grep data-volume

# Bulk edit (use with caution)
for pvc in $(kubectl get pvc -n clickhouse -o name | grep data-volume); do
  kubectl patch $pvc -n clickhouse -p '{"spec":{"resources":{"requests":{"storage":"1Ti"}}}}'
done
```

4. **Verify expansion**:

```bash
# Check PVC status
kubectl get pvc -n clickhouse

# Verify in pod
kubectl exec -n clickhouse <pod-name> -- df -h /var/lib/clickhouse
```

**Note**: AWS EBS supports online expansion. Changes take effect within minutes.

### Change Volume Type

If you need higher IOPS or throughput:

**Steps**:

1. **Create new StorageClass**:

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: gp3-high-performance
provisioner: ebs.csi.aws.com
parameters:
  type: gp3
  encrypted: "true"
  iops: "16000"      # Max 16,000
  throughput: "1000" # Max 1,000 MiB/s
volumeBindingMode: WaitForFirstConsumer
allowVolumeExpansion: true
```

2. **Migrate data** (requires downtime):

```bash
# Create snapshot of current volume
kubectl exec -n clickhouse <pod-name> -- clickhouse-client -q "SYSTEM FLUSH LOGS"

# Scale down StatefulSet
kubectl scale sts -n clickhouse clickhouse-cluster-0-0 --replicas=0

# Delete PVC
kubectl delete pvc -n clickhouse data-volume-clickhouse-cluster-0-0-0

# Update CHI to use new StorageClass
kubectl edit chi -n clickhouse clickhouse-cluster

# Scale back up
kubectl scale sts -n clickhouse clickhouse-cluster-0-0 --replicas=1

# Restore from backup
```

**Recommended**: Use gp3 with higher IOPS/throughput for production.

---

## Node Scaling

### Add EKS Nodes

**Use Case**: Need more capacity for pods

**Downtime**: None

**Steps**:

1. **Update Terraform**:

```hcl
# terraform/terraform.tfvars
clickhouse_node_count = 8  # Increased from 6
```

2. **Apply changes**:

```bash
cd terraform
terraform plan
terraform apply
```

3. **Verify new nodes**:

```bash
kubectl get nodes -l role=clickhouse
```

4. **Pods will use new nodes on next scheduling**:

```bash
# Optional: Rebalance pods
kubectl rollout restart sts -n clickhouse clickhouse-cluster-0-0
```

### Change Node Instance Type

**Use Case**: Need more powerful nodes

**Downtime**: Rolling node replacement (~10-15 min per node)

**Steps**:

1. **Update Terraform**:

```hcl
clickhouse_node_instance_type = "r5.4xlarge"  # Increased from r5.2xlarge
```

2. **Apply changes**:

```bash
terraform apply
```

Terraform will:
- Create new launch template
- Update node group
- Gradually replace nodes

3. **Monitor node replacement**:

```bash
kubectl get nodes -l role=clickhouse -w
```

4. **Verify pods are rescheduled**:

```bash
kubectl get pods -n clickhouse -o wide
```

---

## Auto-Scaling

### Cluster Autoscaler

**Already configured** for general and ClickHouse node groups.

**How it works**:
1. Pods can't be scheduled (Pending state)
2. Cluster Autoscaler detects
3. Adds nodes to the node group
4. Pods are scheduled on new nodes

**Configuration**:

```bash
# Check Cluster Autoscaler status
kubectl logs -n kube-system -l app.kubernetes.io/name=aws-cluster-autoscaler

# Check autoscaler configmap
kubectl get cm -n kube-system cluster-autoscaler-status -o yaml
```

**Limits** (configured in Terraform):

```hcl
resource "aws_eks_node_group" "clickhouse" {
  scaling_config {
    desired_size = 6
    max_size     = 12  # Max autoscale limit
    min_size     = 6   # Min nodes
  }
}
```

### Vertical Pod Autoscaler (VPA)

**Use Case**: Automatically adjust pod resources

**⚠️ Note**: Not recommended for ClickHouse (causes pod restarts)

**Alternative**: Use HPA for read replicas (future enhancement)

### Horizontal Pod Autoscaler (HPA)

**Use Case**: Scale read replicas based on load

**Implementation** (for future):

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: clickhouse-read-replica-hpa
  namespace: clickhouse
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: StatefulSet
    name: clickhouse-read-replicas
  minReplicas: 2
  maxReplicas: 10
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: 70
```

**Note**: Requires separate read-replica deployment (not covered in base setup)

---

## Performance Optimization

### Query Optimization

**Before scaling**, optimize queries:

1. **Identify slow queries**:

```sql
SELECT
    query_id,
    user,
    query_duration_ms,
    query
FROM system.query_log
WHERE type = 'QueryFinish'
  AND query_duration_ms > 10000
ORDER BY query_duration_ms DESC
LIMIT 20;
```

2. **Analyze query plan**:

```sql
EXPLAIN SELECT ... ;
```

3. **Add indexes if needed**:

```sql
-- Add skipping index
ALTER TABLE my_table
ADD INDEX idx_column column_name TYPE minmax GRANULARITY 1;

-- Materialize index
ALTER TABLE my_table MATERIALIZE INDEX idx_column;
```

### Table Optimization

**Partitioning**:

```sql
CREATE TABLE events
(
    event_date Date,
    user_id UInt64,
    event_type String
)
ENGINE = MergeTree()
PARTITION BY toYYYYMM(event_date)  -- Monthly partitions
ORDER BY (event_date, user_id);
```

**Compression**:

```sql
CREATE TABLE large_data
(
    id UInt64,
    data String CODEC(ZSTD(3))  -- High compression
)
ENGINE = MergeTree()
ORDER BY id;
```

**Data Distribution**:

```sql
-- Use good sharding key
CREATE TABLE distributed_events AS events
ENGINE = Distributed(
    clickhouse-cluster,
    default,
    events,
    rand()  -- Random distribution
    -- Or: cityHash64(user_id) -- Hash by user_id
);
```

---

## Capacity Planning

### Estimate Storage Requirements

**Formula**:
```
Total Storage = Raw Data Size × Replication Factor × (1 + Overhead)

Where:
- Replication Factor = 2 (default)
- Overhead = 0.3 (30% for indexes, temporary files, merges)
```

**Example**:
- 1TB raw data
- 2 replicas
- Total: 1TB × 2 × 1.3 = **2.6TB**

### Estimate Memory Requirements

**Formula**:
```
Memory per Node = (Query Memory + Buffer Memory + OS)

Where:
- Query Memory = Max concurrent queries × Avg query memory
- Buffer Memory = 10-20% of total memory
- OS = 2-4GB
```

**Example**:
- 10 concurrent queries
- 2GB per query
- Total: (10 × 2GB) + 4GB (buffer) + 2GB (OS) = **26GB**

Recommended instance: r5.2xlarge (64GB RAM)

### Estimate CPU Requirements

**Formula**:
```
CPU per Node = (Queries per Second × CPU per Query) / CPU Cores

Aim for 50-70% average utilization
```

**Example**:
- 100 queries/sec
- 0.1 CPU seconds per query
- Total: 100 × 0.1 = 10 CPUs (peak)
- With 50% target: **20 vCPUs** recommended

### Capacity Planning Table

| Workload Type | Instance Type | Nodes | Total Capacity |
|---------------|---------------|-------|----------------|
| Small (< 1TB) | r5.xlarge | 3 | 384GB RAM, 36 vCPU |
| Medium (1-10TB) | r5.2xlarge | 6 | 768GB RAM, 72 vCPU |
| Large (10-100TB) | r5.4xlarge | 12 | 3TB RAM, 288 vCPU |
| XLarge (>100TB) | r5.8xlarge | 24+ | 6TB+ RAM, 576+ vCPU |

### Growth Planning

**Quarterly review**:

```sql
-- Check data growth rate
SELECT
    toStartOfMonth(event_date) AS month,
    sum(bytes) / 1024 / 1024 / 1024 AS size_gb,
    count() AS rows
FROM system.parts
WHERE active
GROUP BY month
ORDER BY month DESC
LIMIT 12;
```

**Predict future capacity**:
- Current size: 5TB
- Growth rate: 500GB/month
- In 12 months: 5TB + (500GB × 12) = **11TB**
- Plan scaling when reaching 80% capacity

---

## Scaling Checklist

### Before Scaling

- [ ] Review current metrics (CPU, memory, disk, query performance)
- [ ] Identify bottleneck (compute vs. storage vs. network)
- [ ] Optimize queries and tables first
- [ ] Create backup before major changes
- [ ] Plan maintenance window (if downtime required)
- [ ] Update documentation

### During Scaling

- [ ] Monitor pod/node status
- [ ] Watch for errors in logs
- [ ] Verify resource allocation
- [ ] Check replication status
- [ ] Validate query performance

### After Scaling

- [ ] Run smoke tests
- [ ] Verify data integrity
- [ ] Monitor for 24-48 hours
- [ ] Update capacity plan
- [ ] Document changes

---

## Troubleshooting

### Scaling Issues

**Issue**: Pod stuck in Pending state after scaling

```bash
# Check events
kubectl describe pod -n clickhouse <pod-name>

# Common causes:
# 1. Insufficient nodes
kubectl get nodes

# 2. PVC not bound
kubectl get pvc -n clickhouse

# 3. Resource constraints
kubectl describe node <node-name>
```

**Issue**: High replication lag after adding replicas

```sql
-- Check replication queue
SELECT
    database,
    table,
    replica_name,
    queue_size,
    inserts_in_queue,
    merges_in_queue
FROM system.replicas
WHERE queue_size > 0;

-- Clear queue if stuck
SYSTEM RESTART REPLICA database.table;
```

**Issue**: OOM errors after scaling up queries

```bash
# Check memory limits
kubectl describe pod -n clickhouse <pod-name> | grep -A 5 Limits

# Increase max_memory_usage for user
kubectl exec -n clickhouse <pod-name> -- clickhouse-client -q "
  ALTER USER app_user SETTINGS max_memory_usage = 20000000000
"
```

---

*This scaling guide should be reviewed quarterly and updated based on production experience.*
