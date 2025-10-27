# =============================================================================
# DATA SOURCES
# =============================================================================

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

data "http" "my_public_ip" {
  url = "https://checkip.amazonaws.com/"
}

# =============================================================================
# VPC AND NETWORKING
# =============================================================================

# VPC
resource "aws_vpc" "this" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(local.tags, {
    Name = "${var.project_name}-vpc"
  })
}

# Internet Gateway
resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = merge(local.tags, {
    Name = "${var.project_name}-igw"
  })
}

# Public Subnets
resource "aws_subnet" "public" {
  count = length(var.availability_zones)

  vpc_id                  = aws_vpc.this.id
  cidr_block              = cidrsubnet(aws_vpc.this.cidr_block, 8, count.index + 1)
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = true

  tags = merge(local.tags, {
    Name = "${var.project_name}-public-subnet-${count.index + 1}"
    Type = "Public"
  })
}

# Private Subnets
resource "aws_subnet" "private" {
  count = length(var.availability_zones)

  vpc_id            = aws_vpc.this.id
  cidr_block        = cidrsubnet(aws_vpc.this.cidr_block, 8, count.index + 10)
  availability_zone = var.availability_zones[count.index]

  tags = merge(local.tags, {
    Name = "${var.project_name}-private-subnet-${count.index + 1}"
    Type = "Private"
  })
}

# Elastic IPs for NAT Gateway
resource "aws_eip" "nat" {
  count = var.one_nat_gateway_per_az ? length(var.availability_zones) : 1

  domain     = "vpc"
  depends_on = [aws_internet_gateway.this]

  tags = merge(local.tags, {
    Name = var.one_nat_gateway_per_az ? "${var.project_name}-nat-eip-${count.index + 1}" : "${var.project_name}-nat-eip"
  })
}

# NAT Gateways
resource "aws_nat_gateway" "this" {
  count = var.one_nat_gateway_per_az ? length(var.availability_zones) : 1

  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = var.one_nat_gateway_per_az ? aws_subnet.public[count.index].id : aws_subnet.public[0].id

  tags = merge(local.tags, {
    Name = var.one_nat_gateway_per_az ? "${var.project_name}-nat-gateway-${count.index + 1}" : "${var.project_name}-nat-gateway"
  })

  depends_on = [aws_internet_gateway.this]
}

# Public Route Table
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  tags = merge(local.tags, {
    Name = "${var.project_name}-public-rt"
  })
}

# Private Route Tables
resource "aws_route_table" "private" {
  count = length(var.availability_zones)

  vpc_id = aws_vpc.this.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = var.one_nat_gateway_per_az ? aws_nat_gateway.this[count.index].id : aws_nat_gateway.this[0].id
  }

  tags = merge(local.tags, {
    Name = "${var.project_name}-private-rt-${count.index + 1}"
  })
}

# Public Route Table Associations
resource "aws_route_table_association" "public" {
  count = length(var.availability_zones)

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# Private Route Table Associations
resource "aws_route_table_association" "private" {
  count = length(var.availability_zones)

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}

# DHCP Options Set to use DC for DNS
resource "aws_vpc_dhcp_options" "dc_dns" {
  domain_name_servers = [aws_instance.domain_controller.private_ip, "8.8.8.8"]
  domain_name         = var.domain_name

  tags = merge(local.tags, {
    Name = "${var.project_name}-dhcp-options"
  })
}

resource "aws_vpc_dhcp_options_association" "dc_dns" {
  vpc_id          = aws_vpc.this.id
  dhcp_options_id = aws_vpc_dhcp_options.dc_dns.id

  depends_on = [aws_instance.domain_controller]
}

# =============================================================================
# IAM ROLES FOR SSM ACCESS
# =============================================================================

data "aws_iam_policy_document" "ec2_ssm_policy" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ec2_ssm_role" {
  name               = "${var.project_name}-ec2-ssm-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_ssm_policy.json

  tags = merge(local.tags, {
    Name = "${var.project_name}-ec2-ssm-role"
  })
}

resource "aws_iam_role_policy_attachment" "ssm_managed_instance_core" {
  role       = aws_iam_role.ec2_ssm_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy" "parameter_store_read" {
  name = "parameter-store-read-write"
  role = aws_iam_role.ec2_ssm_role.id

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
          "arn:aws:ssm:*:*:parameter/${var.project_name}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "ssm:PutParameter"
        ]
        Resource = [
          "arn:aws:ssm:*:*:parameter/${var.project_name}/dc-setup"
        ]
      }
    ]
  })
}

resource "aws_iam_instance_profile" "ec2_ssm_profile" {
  name = "${var.project_name}-ec2-ssm-profile"
  role = aws_iam_role.ec2_ssm_role.name

  tags = merge(local.tags, {
    Name = "${var.project_name}-ec2-ssm-profile"
  })
}

# =============================================================================
# RANDOM PASSWORDS
# =============================================================================

resource "random_password" "safe_mode_password" {
  length  = 24
  special = true
  # Exclude $, ?, ~, |, \, <, > characters that cause PowerShell escaping issues
  override_special = "!@#%^&*()-_=+[]{}:,."
  min_lower        = 1
  min_upper        = 1
  min_numeric      = 1
  min_special      = 1
}

resource "random_password" "admin_password" {
  length  = 24
  special = true
  # Exclude $, ?, ~, |, \, <, > characters that cause PowerShell escaping issues
  override_special = "!@#%^&*()-_=+[]{}:,."
  min_lower        = 1
  min_upper        = 1
  min_numeric      = 1
  min_special      = 1
}

# =============================================================================
# PARAMETER STORE (Encrypted passwords)
# =============================================================================

resource "aws_ssm_parameter" "safe_mode_password" {
  name        = "/${var.project_name}/dc/safe-mode-password"
  description = "Safe mode administrator password for DC"
  type        = "SecureString"
  value       = random_password.safe_mode_password.result

  tags = merge(local.tags, {
    Name = "${var.project_name}-dc-safe-mode-password"
  })
}

resource "aws_ssm_parameter" "admin_password" {
  name        = "/${var.project_name}/dc/admin-password"
  description = "Domain Administrator password"
  type        = "SecureString"
  value       = random_password.admin_password.result

  tags = merge(local.tags, {
    Name = "${var.project_name}-dc-admin-password"
  })
}

resource "aws_ssm_parameter" "domain_name" {
  name        = "/${var.project_name}/dc/domain-name"
  description = "Active Directory domain name"
  type        = "String"
  value       = var.domain_name

  tags = merge(local.tags, {
    Name = "${var.project_name}-dc-domain-name"
  })
}

resource "aws_ssm_parameter" "dc_setup_progress" {
  name        = "/${var.project_name}/dc-setup"
  description = "DC setup progress tracking"
  type        = "String"
  value       = "pending"
  overwrite   = true

  tags = merge(local.tags, {
    Name = "${var.project_name}-dc-setup-progress"
  })

  lifecycle {
    ignore_changes = [value]
  }
}

# =============================================================================
# SECURITY GROUPS
# =============================================================================

resource "aws_security_group" "domain_controller" {
  name        = "${var.project_name}-dc-sg"
  description = "Security group for domain controller"
  vpc_id      = aws_vpc.this.id

  ingress {
    description = "Allow all traffic from VPC for AD DS protocols"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [aws_vpc.this.cidr_block]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.tags, {
    Name = "${var.project_name}-dc-sg"
  })
}

# CloudWatch removed - was causing issues with DC promotion

# =============================================================================
# DOMAIN CONTROLLER
# =============================================================================

resource "aws_instance" "domain_controller" {
  ami                    = data.aws_ami.windows_server_2025.id
  instance_type          = var.dc_instance_type
  subnet_id              = aws_subnet.private[0].id
  vpc_security_group_ids = [aws_security_group.domain_controller.id]
  iam_instance_profile   = aws_iam_instance_profile.ec2_ssm_profile.name

  user_data = templatefile("${path.module}/user_data.ps1", {
    domain_name         = var.domain_name
    domain_netbios_name = var.domain_netbios_name
    project_name        = var.project_name
    region              = var.region
  })

  tags = merge(local.tags, {
    Name = "${var.project_name}-server"
    Type = "Domain Controller"
  })
}
