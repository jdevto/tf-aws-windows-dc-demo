terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
    http = {
      source  = "hashicorp/http"
      version = ">= 3.4"
    }
  }
}

# Get the VPC and subnets from the main infrastructure
data "aws_vpc" "main" {
  filter {
    name   = "tag:Name"
    values = ["windows-dc-vpc"]
  }
}

data "aws_subnets" "private" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.main.id]
  }
  filter {
    name   = "tag:Type"
    values = ["Private"]
  }
}

# Get the DC security group
data "aws_security_group" "dc" {
  filter {
    name   = "tag:Name"
    values = ["windows-dc-dc-sg"]
  }
  vpc_id = data.aws_vpc.main.id
}


# =============================================================================
# SECURITY GROUP FOR CLIENT
# =============================================================================

resource "aws_security_group" "client" {
  name        = "windows-dc-client-sg"
  description = "Security group for client"
  vpc_id      = data.aws_vpc.main.id

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.tags, {
    Name = "${local.project_name}-client-sg"
  })
}

# =============================================================================
# IAM ROLE FOR CLIENT (SSM + Parameter Store)
# =============================================================================

resource "aws_iam_role" "client_ssm_role" {
  name = "windows-dc-client-ssm-role"

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

  tags = merge(local.tags, {
    Name = "${local.project_name}-client-ssm-role"
  })
}

resource "aws_iam_role_policy_attachment" "ssm_managed_instance_core" {
  role       = aws_iam_role.client_ssm_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy" "parameter_store_read" {
  name = "parameter-store-read-write"
  role = aws_iam_role.client_ssm_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ssm:GetParameter",
          "ssm:GetParameters"
        ]
        Resource = [
          "arn:aws:ssm:*:*:parameter/windows-dc/dc/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "ssm:PutParameter"
        ]
        Resource = [
          "arn:aws:ssm:*:*:parameter/windows-dc/client-join-domain"
        ]
      }
    ]
  })
}

resource "aws_ssm_parameter" "client_join_progress" {
  name        = "/${local.project_name}/client-join-domain"
  description = "Client domain join progress tracking"
  type        = "String"
  value       = "pending"
  overwrite   = true

  tags = merge(local.tags, {
    Name = "${local.project_name}-client-join-progress"
  })

  lifecycle {
    ignore_changes = [value]
  }
}

resource "aws_iam_instance_profile" "client_ssm_profile" {
  name = "windows-dc-client-ssm-profile"
  role = aws_iam_role.client_ssm_role.name

  tags = merge(local.tags, {
    Name = "${local.project_name}-client-ssm-profile"
  })
}

# =============================================================================
# CLIENT INSTANCE
# =============================================================================

resource "aws_instance" "client" {
  ami                    = data.aws_ami.windows_server_2025.id
  instance_type          = var.client_instance_type
  subnet_id              = tolist(data.aws_subnets.private.ids)[0]
  vpc_security_group_ids = [aws_security_group.client.id]
  iam_instance_profile   = aws_iam_instance_profile.client_ssm_profile.name

  user_data = file("${path.module}/user_data.ps1")

  tags = merge(local.tags, {
    Name = "${local.project_name}-client"
    Type = "Client"
  })
}

data "aws_ami" "windows_server_2025" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["Windows_Server-2025-English-Full-Base-*"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}
