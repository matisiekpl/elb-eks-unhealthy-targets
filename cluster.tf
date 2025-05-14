provider "aws" {
  region = "us-west-1"
}

# Network Resources
resource "aws_vpc" "vpc" {
  cidr_block           = "10.1.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags = {
    Name                                = "vpc-bug"
    "kubernetes.io/cluster/cluster-bug" = "shared"
  }
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_subnet" "public_subnet_1" {
  vpc_id                  = aws_vpc.vpc.id
  cidr_block              = "10.1.1.0/24"
  availability_zone       = "us-west-1a"
  map_public_ip_on_launch = true
  tags = {
    Name                                = "public-subnet-1-bug"
    "kubernetes.io/role/elb"            = "1"
    "kubernetes.io/cluster/cluster-bug" = "shared"
  }
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_subnet" "public_subnet_2" {
  vpc_id                  = aws_vpc.vpc.id
  cidr_block              = "10.1.2.0/24"
  availability_zone       = "us-west-1b"
  map_public_ip_on_launch = true
  tags = {
    Name                                = "public-subnet-2-bug"
    "kubernetes.io/role/elb"            = "1"
    "kubernetes.io/cluster/cluster-bug" = "shared"
  }
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_subnet" "private_subnet_1" {
  vpc_id            = aws_vpc.vpc.id
  cidr_block        = "10.1.3.0/24"
  availability_zone = "us-west-1a"
  tags = {
    Name                                = "private-subnet-1-bug"
    "kubernetes.io/role/internal-elb"   = "1"
    "kubernetes.io/cluster/cluster-bug" = "shared"
  }
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_subnet" "private_subnet_2" {
  vpc_id            = aws_vpc.vpc.id
  cidr_block        = "10.1.4.0/24"
  availability_zone = "us-west-1b"
  tags = {
    Name                                = "private-subnet-2-bug"
    "kubernetes.io/role/internal-elb"   = "1"
    "kubernetes.io/cluster/cluster-bug" = "shared"
  }
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.vpc.id
  tags = {
    Name = "igw-bug"
  }
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.vpc.id

  tags = {
    Name = "public-route-table-bug"
  }
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route" "public_internet_gateway" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.igw.id
}

resource "aws_route_table_association" "public_1" {
  subnet_id      = aws_subnet.public_subnet_1.id
  route_table_id = aws_route_table.public.id
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route_table_association" "public_2" {
  subnet_id      = aws_subnet.public_subnet_2.id
  route_table_id = aws_route_table.public.id
  lifecycle {
    create_before_destroy = true
  }
}

locals {
  main_node_group = {
    main = {
      instance_types = ["t3.xlarge"]

      min_size     = 3
      max_size     = 3
      desired_size = 3

      disk_size = 100

      iam_role_additional_policies = {
        AmazonEBSCSIDriverPolicy = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
      }
    }
  }
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = "cluster-bug"
  cluster_version = "1.31"

  cluster_endpoint_public_access = true

  cluster_addons = {
    coredns = {}
    eks-pod-identity-agent = {}
    kube-proxy = {}
    vpc-cni = {}
    aws-ebs-csi-driver = {}
  }

  cluster_enabled_log_types = [
    "api",
    "audit",
    "authenticator",
    "controllerManager",
    "scheduler"
  ]

  vpc_id = aws_vpc.vpc.id
  subnet_ids = [aws_subnet.public_subnet_1.id, aws_subnet.public_subnet_2.id]
  control_plane_subnet_ids = [aws_subnet.public_subnet_1.id, aws_subnet.public_subnet_2.id]

  eks_managed_node_group_defaults = {
    instance_types = ["t3.2xlarge"]
  }

  eks_managed_node_groups = local.main_node_group

  enable_cluster_creator_admin_permissions = true

  access_entries = {
    main = {
      kubernetes_groups = []
      principal_arn = aws_iam_role.cluster_role.arn

      policy_associations = {
        example = {
          policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSViewPolicy"
          access_scope = {
            namespaces = ["default"]
            type = "namespace"
          }
        }
      }
    }
  }
}

resource "aws_iam_role" "cluster_role" {
  name               = "cluster-role-bug"
  assume_role_policy = data.aws_iam_policy_document.assume_role.json
}

data "aws_iam_policy_document" "assume_role" {
  statement {
    effect = "Allow"

    principals {
      type = "Service"
      identifiers = ["eks.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "eks_services_access" {
  name = "eks-services-access-bug"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = "sts:AssumeRoleWithWebIdentity"
        Principal = {
          Federated = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/${module.eks.oidc_provider}"
        }
      }
    ]
  })
}

resource "aws_iam_policy" "eks_services_access" {
  name        = "eks-services-access-bug"
  description = "IAM policy for pods"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "kms:DescribeCustomKeyStores",
          "kms:ListKeys",
          "kms:ListAliases",
          "kms:Decrypt",
          "kms:GetKeyRotationStatus",
          "kms:GetKeyPolicy",
          "kms:DescribeKey"
        ]
        Effect   = "Allow"
        Resource = "*"
      },
      {
        Action = [
          "textract:DetectDocumentText",
        ]
        Effect   = "Allow"
        Resource = "*"
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "eks_services_policy_attachment" {
  role       = aws_iam_role.eks_services_access.name
  policy_arn = aws_iam_policy.eks_services_access.arn
}

data "aws_caller_identity" "current" {}
data "aws_ecr_authorization_token" "token" {}
