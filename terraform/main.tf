# MuchToDo API - AWS Infrastructure
# Consolidated Terraform resource definitions



# ==========================================
# Source: amis.tf
# ==========================================

# Pin the existing Amazon Linux 2023 AMI to avoid
# unintended EC2 replacements during routine Terraform plans.

locals {
  al2023_ami_id = "ami-09bf9dfeeb1e9adbc"
}


# ==========================================
# Source: networking.tf
# ==========================================

# Discover available Availability Zones
data "aws_availability_zones" "available" {
  state = "available"
}

# Define subnet CIDR ranges and select two Availability Zones
locals {
  availability_zones = slice(data.aws_availability_zones.available.names, 0, 2)

  public_subnet_cidrs = [
    "10.0.1.0/24",
    "10.0.2.0/24"
  ]

  private_subnet_cidrs = [
    "10.0.11.0/24",
    "10.0.12.0/24"
  ]
}


# Main VPC
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "startuptech-vpc"
  }
}

# Internet Gateway
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-igw"
  }
}

# Two public subnets
resource "aws_subnet" "public" {
  count = 2

  vpc_id                  = aws_vpc.main.id
  cidr_block              = local.public_subnet_cidrs[count.index]
  availability_zone       = local.availability_zones[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.project_name}-public-${count.index + 1}"
    Type = "Public"
  }
}

# Two private subnets
resource "aws_subnet" "private" {
  count = 2

  vpc_id                  = aws_vpc.main.id
  cidr_block              = local.private_subnet_cidrs[count.index]
  availability_zone       = local.availability_zones[count.index]
  map_public_ip_on_launch = false

  tags = {
    Name = "${var.project_name}-private-${count.index + 1}"
    Type = "Private"
  }
}

# Public route table
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "${var.project_name}-public-rt"
  }
}

# Associate public subnets with public route table
resource "aws_route_table_association" "public" {
  count = 2

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# Elastic IP for NAT Gateway
resource "aws_eip" "nat" {
  domain = "vpc"

  tags = {
    Name = "${var.project_name}-nat-eip"
  }
}

# NAT Gateway in the first public subnet
resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id

  tags = {
    Name = "${var.project_name}-nat"
  }

  depends_on = [aws_internet_gateway.main]
}

# Private route table
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main.id
  }

  tags = {
    Name = "${var.project_name}-private-rt"
  }
}

# Associate private subnets with private route table
resource "aws_route_table_association" "private" {
  count = 2

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}


# ==========================================
# Source: security-groups.tf
# ==========================================

# Application Load Balancer Security Group
resource "aws_security_group" "alb" {
  name        = "${var.project_name}-alb-sg"
  description = "Allow public HTTP traffic to the ALB"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "Allow HTTP from the internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Allow HTTPS from the internet"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-alb-sg"
  }
}

# Bastion Host Security Group
resource "aws_security_group" "bastion" {
  name        = "${var.project_name}-bastion-sg"
  description = "Allow SSH access only from the approved public IP"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "SSH from approved public IP"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.allowed_ssh_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-bastion-sg"
  }
}

# Backend Security Group
resource "aws_security_group" "backend" {
  name        = "${var.project_name}-backend-sg"
  description = "Allow application traffic from ALB and SSH from Bastion"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "Application traffic from ALB"
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  ingress {
    description     = "SSH access from Bastion"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-backend-sg"
  }
}

# MongoDB Security Group
resource "aws_security_group" "mongodb" {
  name        = "${var.project_name}-mongodb-sg"
  description = "Allow MongoDB traffic from Backend and SSH from Bastion"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "MongoDB traffic from Backend"
    from_port       = 27017
    to_port         = 27017
    protocol        = "tcp"
    security_groups = [aws_security_group.backend.id]
  }

  ingress {
    description     = "SSH access from Bastion"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-mongodb-sg"
  }
}


# ==========================================
# Source: iam.tf
# ==========================================

# Retrieve information about the current AWS account

data "aws_caller_identity" "current" {}

# IAM role that allows EC2 to access AWS services

resource "aws_iam_role" "backend_ecr_role" {
  name = "${var.project_name}-backend-ecr-role"

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

  tags = {
    Name        = "${var.project_name}-backend-ecr-role"
    Environment = "assessment"
    Project     = var.project_name
  }
}


# ADD THE NEW POLICY HERE
resource "aws_iam_role_policy" "backend_ecr_pull" {
  name = "${var.project_name}-backend-ecr-pull"
  role = aws_iam_role.backend_ecr_role.id

  policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Sid      = "ECRAuthentication"
        Effect   = "Allow"
        Action   = ["ecr:GetAuthorizationToken"]
        Resource = "*"
      },
      {
        Sid    = "PullFromBackendRepository"
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:BatchGetImage",
          "ecr:GetDownloadUrlForLayer"
        ]
        Resource = aws_ecr_repository.backend.arn
      }
    ]
  })
}

# Allow backend EC2 to register with and communicate with Systems Manager
resource "aws_iam_role_policy_attachment" "backend_ssm_core" {
  role       = aws_iam_role.backend_ecr_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}





# Allow backend EC2 to read application configuration from SSM Parameter Store

resource "aws_iam_role_policy" "backend_ssm_read" {
  name = "${var.project_name}-backend-ssm-read"
  role = aws_iam_role.backend_ecr_role.id

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
          "arn:aws:ssm:${var.aws_region}:${data.aws_caller_identity.current.account_id}:parameter/${var.project_name}/backend/*"
        ]
      }
    ]
  })
}

# Allow backend EC2 to decrypt SecureString parameters using our KMS key

resource "aws_iam_role_policy" "backend_kms_decrypt" {
  name = "${var.project_name}-backend-kms-decrypt"
  role = aws_iam_role.backend_ecr_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["kms:Decrypt"]
        Resource = aws_kms_key.muchtodo_secrets.arn
      }
    ]
  })
}

# Make the IAM role available to the EC2 instance

resource "aws_iam_instance_profile" "backend" {
  name = "${var.project_name}-backend-instance-profile"
  role = aws_iam_role.backend_ecr_role.name
}

# Customer-managed KMS key for encrypting application secrets
resource "aws_kms_key" "muchtodo_secrets" {
  description             = "KMS key for MuchToDo application secrets"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  tags = {
    Name        = "${var.project_name}-secrets-key"
    Environment = "assessment"
    Project     = var.project_name
  }
}

# Friendly alias for the KMS key
resource "aws_kms_alias" "muchtodo_secrets" {
  name          = "alias/${var.project_name}-secrets"
  target_key_id = aws_kms_key.muchtodo_secrets.key_id
}


# IAM role for MongoDB EC2
resource "aws_iam_role" "mongodb_role" {
  name = "${var.project_name}-mongodb-role"

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

  tags = {
    Name        = "${var.project_name}-mongodb-role"
    Environment = "assessment"
    Project     = var.project_name
  }
}

# Allow MongoDB EC2 to retrieve its own SSM parameters

resource "aws_iam_role_policy" "mongodb_ssm_read" {
  name = "${var.project_name}-mongodb-ssm-read"
  role = aws_iam_role.mongodb_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "ssm:GetParameter",
        "ssm:GetParameters"
      ]
      Resource = [
        "arn:aws:ssm:${var.aws_region}:${data.aws_caller_identity.current.account_id}:parameter/${var.project_name}/mongodb/*"
      ]
    }]
  })
}



# Allow MongoDB EC2 to use the project KMS key for decryption
resource "aws_iam_role_policy" "mongodb_kms_decrypt" {
  name = "${var.project_name}-mongodb-kms-decrypt"
  role = aws_iam_role.mongodb_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "kms:Decrypt"
      ]
      Resource = aws_kms_key.muchtodo_secrets.arn
    }]
  })
}

# Allow MongoDB EC2 to register with and communicate with Systems Manager
resource "aws_iam_role_policy_attachment" "mongodb_ssm_core" {
  role       = aws_iam_role.mongodb_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}


# Make the MongoDB IAM role available to EC2
resource "aws_iam_instance_profile" "mongodb" {
  name = "${var.project_name}-mongodb-instance-profile"
  role = aws_iam_role.mongodb_role.name
}


# ==========================================
# Source: ecr.tf
# ==========================================

# Amazon ECR repository for the MuchToDo API Docker image

resource "aws_ecr_repository" "backend" {
  name                 = "${var.project_name}-api"
  image_tag_mutability = "MUTABLE"
  force_delete         = false

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = {
    Name        = "${var.project_name}-api"
    Environment = "assessment"
    Project     = var.project_name
  }
}

# ==========================================
# Source: compute.tf
# ==========================================

# Bastion host
resource "aws_instance" "bastion" {
  ami                         = sensitive(local.al2023_ami_id)
  instance_type               = var.instance_type
  key_name                    = var.key_pair_name
  subnet_id                   = aws_subnet.public[0].id
  vpc_security_group_ids      = [aws_security_group.bastion.id]
  associate_public_ip_address = true

  tags = {
    Name = "${var.project_name}-bastion"
    Role = "Bastion"
  }
}

# Elastic IP for Bastion host
resource "aws_eip" "bastion" {
  domain   = "vpc"
  instance = aws_instance.bastion.id

  tags = {
    Name = "${var.project_name}-bastion-eip"
  }
}

# Backend application server
resource "aws_instance" "backend" {
  ami                    = sensitive(local.al2023_ami_id)
  instance_type          = var.instance_type
  key_name               = var.key_pair_name
  subnet_id              = aws_subnet.private[0].id
  vpc_security_group_ids = [aws_security_group.backend.id]
  iam_instance_profile   = aws_iam_instance_profile.backend.name
  depends_on             = [aws_route_table_association.private]
  user_data = templatefile("${path.module}/user_data/backend_setup.sh", {
    aws_region     = var.aws_region
    aws_account_id = data.aws_caller_identity.current.account_id
    ecr_repository = aws_ecr_repository.backend.name
    image_tag      = "1.0"
    project_name   = var.project_name
  })

  tags = {
    Name = "${var.project_name}-backend"
    Role = "Backend"
  }
}

# MongoDB database server
resource "aws_instance" "mongodb" {
  ami                    = sensitive(local.al2023_ami_id)
  instance_type          = var.instance_type
  key_name               = var.key_pair_name
  subnet_id              = aws_subnet.private[1].id
  vpc_security_group_ids = [aws_security_group.mongodb.id]
  iam_instance_profile   = aws_iam_instance_profile.mongodb.name
  depends_on             = [aws_route_table_association.private]

  user_data = templatefile("${path.module}/user_data/mongodb_setup.sh", {
    aws_region            = var.aws_region
    mongodb_ebs_volume_id = aws_ebs_volume.mongodb_data.id
  })

  tags = {
    Name = "${var.project_name}-mongodb"
    Role = "Database"
  }
}

# Persistent storage for MongoDB
resource "aws_ebs_volume" "mongodb_data" {
  availability_zone = aws_subnet.private[1].availability_zone
  size              = 20
  type              = "gp3"
  encrypted         = true

  tags = {
    Name = "${var.project_name}-mongodb-data"
    Role = "Database Storage"
  }
  lifecycle {
    prevent_destroy = true
  }
}


# Attach persistent storage to MongoDB EC2 instance
resource "aws_volume_attachment" "mongodb_data" {
  device_name = "/dev/sdf"
  volume_id   = aws_ebs_volume.mongodb_data.id
  instance_id = aws_instance.mongodb.id
}


# ==========================================
# Source: alb.tf
# ==========================================

# Application Load Balancer
resource "aws_lb" "main" {
  name               = "${var.project_name}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]

  subnets = [
    aws_subnet.public[0].id,
    aws_subnet.public[1].id
  ]

  enable_deletion_protection = false

  tags = {
    Name = "${var.project_name}-alb"
  }
}

# Target Group for the backend application
resource "aws_lb_target_group" "backend" {
  name     = "${var.project_name}-backend-tg"
  port     = 8080
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id

  health_check {
    enabled             = true
    path                = "/health"
    protocol            = "HTTP"
    port                = "traffic-port"
    matcher             = "200"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  tags = {
    Name = "${var.project_name}-backend-tg"
  }
}

# Register the backend EC2 instance with the target group
resource "aws_lb_target_group_attachment" "backend" {
  target_group_arn = aws_lb_target_group.backend.arn
  target_id        = aws_instance.backend.id
  port             = 8080
}

# HTTP listener
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.backend.arn
  }
}
