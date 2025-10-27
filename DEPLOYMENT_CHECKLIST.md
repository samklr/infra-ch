# Deployment Checklist

Use this checklist to ensure a successful deployment of ClickHouse on EKS.

## Pre-Deployment

### Prerequisites
- [ ] AWS account with appropriate permissions
- [ ] AWS CLI installed and configured (`aws --version`)
- [ ] Terraform >= 1.5.0 installed (`terraform --version`)
- [ ] kubectl >= 1.28 installed (`kubectl version`)
- [ ] Helm >= 3.12 installed (`helm version`)
- [ ] Sufficient AWS service limits:
  - [ ] VPCs (need 1)
  - [ ] Elastic IPs (need 3 for NAT gateways)
  - [ ] EC2 instances (need 11 total)
  - [ ] EBS volumes (need ~15)

### Configuration
- [ ] Review and customize `terraform/terraform.tfvars`
- [ ] Choose appropriate instance types for your workload
- [ ] Select AWS region and availability zones
- [ ] Review estimated costs (~$2,700/month for defaults)
- [ ] Plan backup retention policy
- [ ] Decide on autoscaling configuration

### Security Planning
- [ ] Identify who needs access to ClickHouse
- [ ] Plan network access (VPN, bastion, direct)
- [ ] Prepare password policy for ClickHouse users
- [ ] Review compliance requirements (SOC2, HIPAA, etc.)
- [ ] Plan secret management strategy

## Deployment Steps

### Phase 1: Infrastructure (Terraform)
- [ ] Navigate to `terraform/` directory
- [ ] Run `terraform init`
- [ ] Run `terraform plan` and review output
- [ ] Run `terraform apply`
- [ ] Verify outputs:
  - [ ] Cluster name
  - [ ] VPC ID
  - [ ] S3 backup bucket name
  - [ ] IAM role ARNs
- [ ] Configure kubectl: `aws eks update-kubeconfig --region <region> --name <cluster-name>`
- [ ] Test kubectl access: `kubectl get nodes`

**Expected Duration**: 15-20 minutes

**Rollback**: `terraform destroy` (if issues occur)

### Phase 2: Kubernetes Bootstrap
- [ ] Run `./scripts/bootstrap.sh`
- [ ] Monitor script output for errors
- [ ] Verify components deployed:
  - [ ] cert-manager (3 pods)
  - [ ] ClickHouse operator (1 pod)
  - [ ] ClickHouse Keeper (3 pods)
  - [ ] ClickHouse cluster (6 pods)
  - [ ] Prometheus stack (multiple pods)
- [ ] Check all pods are Running: `kubectl get pods -n clickhouse`
- [ ] Check all PVCs are Bound: `kubectl get pvc -n clickhouse`

**Expected Duration**: 10-15 minutes

**Rollback**: Delete namespace and rerun bootstrap

### Phase 3: Verification
- [ ] Run `./scripts/smoke-test.sh`
- [ ] Verify all 13 tests pass
- [ ] Check specific components:
  - [ ] ClickHouse pods healthy
  - [ ] Keeper quorum established
  - [ ] Load balancer provisioned
  - [ ] Backup CronJob created
  - [ ] Monitoring stack operational

**Expected Duration**: 2-3 minutes

## Post-Deployment

### Immediate Actions (Within 1 Hour)
- [ ] **Change default passwords**:
  ```bash
  kubectl edit chi -n clickhouse clickhouse-cluster
  # Update users/admin/password and users/default/password
  ```
- [ ] Save load balancer endpoints:
  ```bash
  kubectl get svc -n clickhouse > endpoints.txt
  ```
- [ ] Access Grafana and verify dashboards load
- [ ] Test external connectivity to ClickHouse
- [ ] Create first test database and table
- [ ] Run manual backup to test backup system:
  ```bash
  kubectl create job -n clickhouse test-backup --from=cronjob/clickhouse-backup
  ```
- [ ] Verify backup appears in S3

### First Day
- [ ] Document access procedures for team
- [ ] Configure monitoring alerts destinations (PagerDuty, Slack, etc.)
- [ ] Set up VPN or bastion access (if using internal load balancer)
- [ ] Create application-specific ClickHouse users with limited permissions
- [ ] Test application connectivity
- [ ] Review and adjust resource requests/limits if needed
- [ ] Set up log aggregation (CloudWatch, Datadog, etc.)

### First Week
- [ ] Monitor resource usage patterns (CPU, memory, disk)
- [ ] Adjust pod resources if needed
- [ ] Test backup restore procedure
- [ ] Review and tune ClickHouse settings for your workload
- [ ] Set up additional Grafana dashboards for your use case
- [ ] Configure network policies for pod-to-pod access
- [ ] Review CloudWatch logs and metrics
- [ ] Test cluster autoscaler (if enabled)
- [ ] Document any custom configurations
- [ ] Train team on operational procedures

### First Month
- [ ] Perform capacity planning based on actual usage
- [ ] Review and optimize query performance
- [ ] Test scaling procedures (add shard, add replica)
- [ ] Conduct security review
- [ ] Review costs and optimize if needed
- [ ] Test disaster recovery procedure
- [ ] Update runbooks based on learnings
- [ ] Schedule regular maintenance windows

## Production Readiness Checklist

### Security
- [ ] All default passwords changed
- [ ] TLS enabled for client connections (recommended)
- [ ] Network policies configured
- [ ] IRSA configured for all service accounts
- [ ] Secrets stored in AWS Secrets Manager (recommended)
- [ ] VPC Flow Logs enabled (recommended)
- [ ] GuardDuty enabled (recommended)
- [ ] IAM policies follow least-privilege principle
- [ ] Pod Security Standards set to "restricted" (recommended)
- [ ] Security scanning enabled for container images

### High Availability
- [ ] ClickHouse pods distributed across 3 AZs
- [ ] Keeper quorum established (3 nodes minimum)
- [ ] PodDisruptionBudgets configured
- [ ] Pod anti-affinity rules in place
- [ ] Multiple replicas per shard (2 minimum)
- [ ] Load balancer health checks configured
- [ ] Cluster Autoscaler enabled and tested

### Backup & Recovery
- [ ] Daily backups scheduled and running
- [ ] Backup retention policy configured
- [ ] S3 bucket lifecycle policies set
- [ ] Backup restore tested successfully
- [ ] RPO and RTO documented and acceptable
- [ ] Disaster recovery procedure documented
- [ ] Backup monitoring and alerting configured

### Monitoring & Alerting
- [ ] Prometheus collecting metrics
- [ ] Grafana dashboards accessible
- [ ] Key alerts configured:
  - [ ] Pod down
  - [ ] High CPU/memory
  - [ ] Disk space warnings
  - [ ] Replication lag
  - [ ] Backup failures
- [ ] Alert destinations configured (PagerDuty, Slack, email)
- [ ] On-call rotation established
- [ ] Runbooks accessible to on-call team

### Documentation
- [ ] Architecture diagram updated
- [ ] Access procedures documented
- [ ] Runbook reviewed and updated
- [ ] Scaling procedures documented
- [ ] Security procedures documented
- [ ] Disaster recovery plan documented
- [ ] Team trained on operations
- [ ] Escalation procedures documented

### Compliance
- [ ] Data encryption at rest verified
- [ ] Data encryption in transit configured (if required)
- [ ] Audit logging enabled
- [ ] Compliance requirements documented
- [ ] Regular security audits scheduled
- [ ] Data retention policies implemented
- [ ] Access control policies documented

## Common Issues & Solutions

### Issue: Pods stuck in Pending
**Cause**: Insufficient cluster capacity
**Solution**:
```bash
kubectl describe pod -n clickhouse <pod-name>
# Check events for "Insufficient cpu/memory"
# Increase node count or upgrade instance types
```

### Issue: Keeper pods not reaching quorum
**Cause**: Pod anti-affinity or network issues
**Solution**:
```bash
kubectl logs -n clickhouse clickhouse-keeper-0
kubectl exec -n clickhouse clickhouse-keeper-0 -- bash -c 'echo ruok | nc localhost 2181'
# Should return "imok"
```

### Issue: ClickHouse pods crash with OOM
**Cause**: Insufficient memory allocation
**Solution**:
```bash
# Increase memory limits in CHI manifest
kubectl edit chi -n clickhouse clickhouse-cluster
# Update resources.limits.memory
```

### Issue: Load balancer not provisioned
**Cause**: AWS Load Balancer Controller not ready
**Solution**:
```bash
kubectl logs -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller
# Check for errors
# Verify IAM role has correct permissions
```

### Issue: Backup job fails
**Cause**: S3 permissions or ClickHouse connectivity
**Solution**:
```bash
kubectl logs -n clickhouse -l app=clickhouse-backup
# Check IRSA annotation on service account
kubectl describe sa -n clickhouse clickhouse-backup
# Test S3 access
kubectl exec -n clickhouse <backup-pod> -- aws s3 ls
```

## Rollback Procedures

### Rollback Infrastructure
```bash
cd terraform
terraform destroy
# Confirm with 'yes'
```

### Rollback ClickHouse Version
```bash
kubectl edit chi -n clickhouse clickhouse-cluster
# Change image back to previous version
# Operator will perform rolling update
```

### Emergency Restore
```bash
# If cluster is completely broken
# 1. Deploy new cluster
# 2. Restore from last known good backup
./scripts/bootstrap.sh
kubectl exec -n clickhouse <pod> -- clickhouse-backup list remote
kubectl exec -n clickhouse <pod> -- clickhouse-backup restore <backup-name>
```

## Success Criteria

Deployment is considered successful when:

- [ ] All 13 smoke tests pass
- [ ] ClickHouse is accessible via load balancer
- [ ] Queries execute successfully
- [ ] Replication is working (no lag)
- [ ] Backups are running and succeeding
- [ ] Monitoring dashboards show healthy metrics
- [ ] No critical alerts firing
- [ ] Documentation is complete
- [ ] Team is trained and confident

## Next Steps After Successful Deployment

1. **Performance Tuning**: Optimize for your specific workload
2. **Cost Optimization**: Review and adjust resources based on actual usage
3. **Security Hardening**: Implement TLS, network policies, secrets management
4. **Capacity Planning**: Monitor growth and plan for future scaling
5. **Automation**: Set up CI/CD for schema changes and application deployments
6. **Integration**: Connect applications and ETL pipelines
7. **Advanced Features**: Implement materialized views, projections, etc.

## Support Contacts

- **Internal**: [Your team contact info]
- **AWS Support**: https://console.aws.amazon.com/support/
- **Altinity Support**: https://altinity.com/support/
- **Community**: ClickHouse Slack / GitHub Discussions

---

**Remember**: Always test in a non-production environment first!

Last Updated: 2024-01-27
Version: 1.0
