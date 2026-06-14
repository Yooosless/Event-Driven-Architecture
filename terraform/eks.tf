resource "aws_iam_role" "eks_nodes" {
  name = "afridi-eks-worker-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "worker" {
  role       = aws_iam_role.eks_nodes.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "cni" {
  role       = aws_iam_role.eks_nodes.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role_policy_attachment" "ecr" {
  role       = aws_iam_role.eks_nodes.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_eks_cluster" "eks_worker_cluster" {
  name     = "afridi-eks-worker-cluster"
  role_arn = "arn:aws:iam::589118303122:role/interns-test-universe-eks-cluster-role"

  vpc_config {
    subnet_ids = data.aws_subnets.public.ids
  }
}

resource "aws_eks_node_group" "eks_worker_nodes" {
  cluster_name    = aws_eks_cluster.eks_worker_cluster.name
  node_group_name = "worker-node-pool"
  node_role_arn   = aws_iam_role.eks_nodes.arn
  subnet_ids      = data.aws_subnets.public.ids
  instance_types  = ["t3.medium"]


  scaling_config {
    desired_size = var.sleep_mode ? 0 : 2
    max_size     = var.sleep_mode ? 1 : 4 
    min_size     = var.sleep_mode ? 0 : 1
  }

  remote_access {
    ec2_ssh_key = aws_key_pair.ec2_key.key_name
  }

  depends_on = [
    aws_eks_cluster.eks_worker_cluster,
    aws_iam_role_policy_attachment.worker,
    aws_iam_role_policy_attachment.cni,
    aws_iam_role_policy_attachment.ecr
  ]
}

resource "aws_iam_role_policy" "eks_s3_access" {
  name = "afridi-eks-s3-access"
  role = aws_iam_role.eks_nodes.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "s3:PutObject",
        "s3:GetObject",
        "s3:ListBucket"
      ]
      Resource = [
        "arn:aws:s3:::afridi-poc-bucket",
        "arn:aws:s3:::afridi-poc-bucket/*"
      ]
    }]
  })
}