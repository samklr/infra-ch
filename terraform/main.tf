locals {
  cluster_name           = "${var.cluster_name}-${var.environment}"
  backup_s3_bucket_name  = var.backup_s3_bucket_name != "" ? var.backup_s3_bucket_name : "${local.cluster_name}-clickhouse-backups-${data.aws_caller_identity.current.account_id}"

  common_tags = merge(
    var.tags,
    {
      Environment = var.environment
      Cluster     = local.cluster_name
    }
  )
}

data "aws_caller_identity" "current" {}

################################################################################
# VPC Module
################################################################################

module "vpc" {
  source = "./modules/vpc"

  cluster_name       = local.cluster_name
  vpc_cidr           = var.vpc_cidr
  availability_zones = var.availability_zones
  environment        = var.environment
  tags               = local.common_tags
}

################################################################################
# IAM Module
################################################################################

module "iam" {
  source = "./modules/iam"

  cluster_name          = local.cluster_name
  cluster_oidc_issuer   = module.eks_cluster.cluster_oidc_issuer_url
  backup_s3_bucket_name = local.backup_s3_bucket_name
  environment           = var.environment
  tags                  = local.common_tags
}

################################################################################
# EKS Cluster Module
################################################################################

module "eks_cluster" {
  source = "./modules/eks-cluster"

  cluster_name                     = local.cluster_name
  cluster_version                  = var.cluster_version
  vpc_id                           = module.vpc.vpc_id
  private_subnet_ids               = module.vpc.private_subnet_ids

  # Node groups configuration
  clickhouse_node_instance_type    = var.clickhouse_node_instance_type
  clickhouse_node_count            = var.clickhouse_node_count
  keeper_node_instance_type        = var.keeper_node_instance_type
  keeper_node_count                = var.keeper_node_count
  general_node_instance_type       = var.general_node_instance_type
  general_node_count               = var.general_node_count

  # IAM roles
  ebs_csi_driver_role_arn          = module.iam.ebs_csi_driver_role_arn
  aws_load_balancer_controller_role_arn = module.iam.aws_load_balancer_controller_role_arn
  cluster_autoscaler_role_arn      = module.iam.cluster_autoscaler_role_arn

  enable_cluster_autoscaler        = var.enable_cluster_autoscaler

  environment                      = var.environment
  tags                             = local.common_tags
}

################################################################################
# S3 Backup Bucket
################################################################################

resource "aws_s3_bucket" "clickhouse_backups" {
  bucket = local.backup_s3_bucket_name
  tags   = local.common_tags
}

resource "aws_s3_bucket_versioning" "clickhouse_backups" {
  bucket = aws_s3_bucket.clickhouse_backups.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "clickhouse_backups" {
  bucket = aws_s3_bucket.clickhouse_backups.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "clickhouse_backups" {
  bucket = aws_s3_bucket.clickhouse_backups.id

  rule {
    id     = "delete-old-backups"
    status = "Enabled"

    expiration {
      days = var.backup_retention_days
    }

    noncurrent_version_expiration {
      noncurrent_days = 7
    }
  }
}

resource "aws_s3_bucket_public_access_block" "clickhouse_backups" {
  bucket = aws_s3_bucket.clickhouse_backups.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

################################################################################
# EBS CSI Driver Add-on
################################################################################

resource "aws_eks_addon" "ebs_csi_driver" {
  cluster_name             = module.eks_cluster.cluster_name
  addon_name               = "aws-ebs-csi-driver"
  addon_version            = "v1.26.1-eksbuild.1"
  service_account_role_arn = module.iam.ebs_csi_driver_role_arn

  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  tags = local.common_tags

  depends_on = [
    module.eks_cluster
  ]
}

################################################################################
# AWS Load Balancer Controller (Helm)
################################################################################

resource "helm_release" "aws_load_balancer_controller" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  version    = "1.6.2"
  namespace  = "kube-system"

  set {
    name  = "clusterName"
    value = module.eks_cluster.cluster_name
  }

  set {
    name  = "serviceAccount.create"
    value = "true"
  }

  set {
    name  = "serviceAccount.name"
    value = "aws-load-balancer-controller"
  }

  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = module.iam.aws_load_balancer_controller_role_arn
  }

  set {
    name  = "region"
    value = var.aws_region
  }

  set {
    name  = "vpcId"
    value = module.vpc.vpc_id
  }

  depends_on = [
    module.eks_cluster,
    aws_eks_addon.ebs_csi_driver
  ]
}

################################################################################
# Cluster Autoscaler (Optional)
################################################################################

resource "helm_release" "cluster_autoscaler" {
  count = var.enable_cluster_autoscaler ? 1 : 0

  name       = "cluster-autoscaler"
  repository = "https://kubernetes.github.io/autoscaler"
  chart      = "cluster-autoscaler"
  version    = "9.34.0"
  namespace  = "kube-system"

  set {
    name  = "autoDiscovery.clusterName"
    value = module.eks_cluster.cluster_name
  }

  set {
    name  = "awsRegion"
    value = var.aws_region
  }

  set {
    name  = "rbac.serviceAccount.create"
    value = "true"
  }

  set {
    name  = "rbac.serviceAccount.name"
    value = "cluster-autoscaler"
  }

  set {
    name  = "rbac.serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = module.iam.cluster_autoscaler_role_arn
  }

  depends_on = [
    module.eks_cluster,
    helm_release.aws_load_balancer_controller
  ]
}
