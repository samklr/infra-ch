################################################################################
# EKS Cluster
################################################################################

resource "aws_eks_cluster" "main" {
  name     = var.cluster_name
  version  = var.cluster_version
  role_arn = aws_iam_role.cluster.arn

  vpc_config {
    subnet_ids              = var.private_subnet_ids
    endpoint_private_access = true
    endpoint_public_access  = true
    public_access_cidrs     = ["0.0.0.0/0"]
  }

  encryption_config {
    provider {
      key_arn = aws_kms_key.eks.arn
    }
    resources = ["secrets"]
  }

  enabled_cluster_log_types = [
    "api",
    "audit",
    "authenticator",
    "controllerManager",
    "scheduler"
  ]

  tags = var.tags

  depends_on = [
    aws_iam_role_policy_attachment.cluster_AmazonEKSClusterPolicy,
    aws_iam_role_policy_attachment.cluster_AmazonEKSVPCResourceController,
    aws_cloudwatch_log_group.eks
  ]
}

################################################################################
# KMS Key for EKS Encryption
################################################################################

resource "aws_kms_key" "eks" {
  description             = "EKS Secret Encryption Key for ${var.cluster_name}"
  deletion_window_in_days = 10
  enable_key_rotation     = true

  tags = merge(
    var.tags,
    {
      Name = "${var.cluster_name}-eks-encryption-key"
    }
  )
}

resource "aws_kms_alias" "eks" {
  name          = "alias/${var.cluster_name}-eks"
  target_key_id = aws_kms_key.eks.key_id
}

################################################################################
# CloudWatch Log Group
################################################################################

resource "aws_cloudwatch_log_group" "eks" {
  name              = "/aws/eks/${var.cluster_name}/cluster"
  retention_in_days = 7

  tags = var.tags
}

################################################################################
# IAM Role for EKS Cluster
################################################################################

resource "aws_iam_role" "cluster" {
  name = "${var.cluster_name}-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "eks.amazonaws.com"
      }
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "cluster_AmazonEKSClusterPolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.cluster.name
}

resource "aws_iam_role_policy_attachment" "cluster_AmazonEKSVPCResourceController" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSVPCResourceController"
  role       = aws_iam_role.cluster.name
}

################################################################################
# OIDC Provider
################################################################################

data "tls_certificate" "cluster" {
  url = aws_eks_cluster.main.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "cluster" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.cluster.certificates[0].sha1_fingerprint]
  url             = aws_eks_cluster.main.identity[0].oidc[0].issuer

  tags = var.tags
}

################################################################################
# Node Groups - ClickHouse
################################################################################

resource "aws_eks_node_group" "clickhouse" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "${var.cluster_name}-clickhouse"
  node_role_arn   = aws_iam_role.node.arn
  subnet_ids      = var.private_subnet_ids
  version         = var.cluster_version

  scaling_config {
    desired_size = var.clickhouse_node_count
    max_size     = var.clickhouse_node_count * 2
    min_size     = var.clickhouse_node_count
  }

  update_config {
    max_unavailable_percentage = 33
  }

  instance_types = [var.clickhouse_node_instance_type]
  capacity_type  = "ON_DEMAND"
  disk_size      = 100

  labels = {
    role        = "clickhouse"
    environment = var.environment
  }

  taints {
    key    = "dedicated"
    value  = "clickhouse"
    effect = "NO_SCHEDULE"
  }

  tags = merge(
    var.tags,
    {
      Name                                            = "${var.cluster_name}-clickhouse-node"
      "k8s.io/cluster-autoscaler/${var.cluster_name}" = "owned"
      "k8s.io/cluster-autoscaler/enabled"             = var.enable_cluster_autoscaler ? "true" : "false"
    }
  )

  depends_on = [
    aws_iam_role_policy_attachment.node_AmazonEKSWorkerNodePolicy,
    aws_iam_role_policy_attachment.node_AmazonEKS_CNI_Policy,
    aws_iam_role_policy_attachment.node_AmazonEC2ContainerRegistryReadOnly,
  ]
}

################################################################################
# Node Groups - Keeper
################################################################################

resource "aws_eks_node_group" "keeper" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "${var.cluster_name}-keeper"
  node_role_arn   = aws_iam_role.node.arn
  subnet_ids      = var.private_subnet_ids
  version         = var.cluster_version

  scaling_config {
    desired_size = var.keeper_node_count
    max_size     = var.keeper_node_count
    min_size     = var.keeper_node_count
  }

  update_config {
    max_unavailable = 1
  }

  instance_types = [var.keeper_node_instance_type]
  capacity_type  = "ON_DEMAND"
  disk_size      = 50

  labels = {
    role        = "keeper"
    environment = var.environment
  }

  taints {
    key    = "dedicated"
    value  = "keeper"
    effect = "NO_SCHEDULE"
  }

  tags = merge(
    var.tags,
    {
      Name = "${var.cluster_name}-keeper-node"
    }
  )

  depends_on = [
    aws_iam_role_policy_attachment.node_AmazonEKSWorkerNodePolicy,
    aws_iam_role_policy_attachment.node_AmazonEKS_CNI_Policy,
    aws_iam_role_policy_attachment.node_AmazonEC2ContainerRegistryReadOnly,
  ]
}

################################################################################
# Node Groups - General
################################################################################

resource "aws_eks_node_group" "general" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "${var.cluster_name}-general"
  node_role_arn   = aws_iam_role.node.arn
  subnet_ids      = var.private_subnet_ids
  version         = var.cluster_version

  scaling_config {
    desired_size = var.general_node_count
    max_size     = var.general_node_count * 3
    min_size     = var.general_node_count
  }

  update_config {
    max_unavailable_percentage = 33
  }

  instance_types = [var.general_node_instance_type]
  capacity_type  = "ON_DEMAND"
  disk_size      = 50

  labels = {
    role        = "general"
    environment = var.environment
  }

  tags = merge(
    var.tags,
    {
      Name                                            = "${var.cluster_name}-general-node"
      "k8s.io/cluster-autoscaler/${var.cluster_name}" = "owned"
      "k8s.io/cluster-autoscaler/enabled"             = var.enable_cluster_autoscaler ? "true" : "false"
    }
  )

  depends_on = [
    aws_iam_role_policy_attachment.node_AmazonEKSWorkerNodePolicy,
    aws_iam_role_policy_attachment.node_AmazonEKS_CNI_Policy,
    aws_iam_role_policy_attachment.node_AmazonEC2ContainerRegistryReadOnly,
  ]
}

################################################################################
# IAM Role for Node Groups
################################################################################

resource "aws_iam_role" "node" {
  name = "${var.cluster_name}-node-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "node_AmazonEKSWorkerNodePolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.node.name
}

resource "aws_iam_role_policy_attachment" "node_AmazonEKS_CNI_Policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.node.name
}

resource "aws_iam_role_policy_attachment" "node_AmazonEC2ContainerRegistryReadOnly" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.node.name
}

resource "aws_iam_role_policy_attachment" "node_AmazonSSMManagedInstanceCore" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  role       = aws_iam_role.node.name
}
