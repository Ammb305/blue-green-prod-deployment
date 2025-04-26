resource "aws_security_group" "eks-sg" {
  vpc_id = data.aws_vpc.selected.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "eks-cluster-sg"
  }
}

resource "aws_security_group" "eks_node_sg" {
  vpc_id = data.aws_vpc.selected.id

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "eks-node-sg"
  }
}

# EKS Cluster
resource "aws_eks_cluster" "blue_green_cluster" {
  name     = "blue-green-cluster"
  role_arn = aws_iam_role.blue_green_cluster_role.arn

  vpc_config {
    subnet_ids         = concat(aws_subnet.public_subnets[*].id, aws_subnet.private_subnets[*].id)
    security_group_ids = [aws_security_group.eks-sg.id]
  }

  tags = {
    Name = "blue-green-cluster"
  }
}

# EKS Node Group
resource "aws_eks_node_group" "blue_green_node_group" {
  cluster_name    = aws_eks_cluster.blue_green_cluster.name
  node_group_name = "blue-green-node-group"
  node_role_arn   = aws_iam_role.blue_green_node_group_role.arn
  subnet_ids      = aws_subnet.public_subnets[*].id

  scaling_config {
    desired_size = 3
    max_size     = 3
    min_size     = 1
  }

  instance_types = ["t2.medium"]

  remote_access {
    ec2_ssh_key = var.key_name
    source_security_group_ids = [aws_security_group.eks-sg.id]
  }

  tags = {
    Name = "blue-green-node-group"
  }
}

# IAM Role for EKS Cluster
resource "aws_iam_role" "blue_green_cluster_role" {
  name = "blue-green-cluster-role"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "eks.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "blue_green_cluster_role_policy" {
  role       = aws_iam_role.blue_green_cluster_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

# IAM Role for EKS Node Group
resource "aws_iam_role" "blue_green_node_group_role" {
  name = "blue-green-node-group-role"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "blue_green_node_group_role_policy" {
  role       = aws_iam_role.blue_green_node_group_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "blue_green_node_group_cni_policy" {
  role       = aws_iam_role.blue_green_node_group_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role_policy_attachment" "blue_green_node_group_registry_policy" {
  role       = aws_iam_role.blue_green_node_group_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

# Outputs
output "eks_cluster_id" {
  value = aws_eks_cluster.blue_green_cluster.id
}

output "eks_node_group_id" {
  value = aws_eks_node_group.blue_green_node_group.id
}

output "eks_vpc_id" {
  value = aws_vpc.main.id
}

output "eks_subnet_ids" {
  value = concat(aws_subnet.public_subnets[*].id, aws_subnet.private_subnets[*].id)
}