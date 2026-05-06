terraform {
  backend "s3" {
    bucket = "ryo-terraform-state-20260430"
    key    = "study-aws-3/terraform.tfstate"
    region = "ap-northeast-1"
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_caller_identity" "current" {}

data "aws_iam_policy_document" "ecs_tasks_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

locals {
  name_prefix       = "study-aws-3"
  wordpress_db_host = var.restore_db_endpoint != "" ? var.restore_db_endpoint : aws_db_instance.mysql.address
  ecr_image_uri     = "${aws_ecr_repository.wordpress.repository_url}:${var.image_tag}"
}

# -------------------------
# SSH Key Pair for Bastion
# -------------------------
resource "tls_private_key" "bastion_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "local_sensitive_file" "bastion_private_key" {
  filename        = "${path.module}/bastion-key.pem"
  content         = tls_private_key.bastion_key.private_key_pem
  file_permission = "0400"
}

resource "aws_key_pair" "bastion_key" {
  key_name   = "${local.name_prefix}-bastion-key"
  public_key = tls_private_key.bastion_key.public_key_openssh

  tags = {
    Name = "${local.name_prefix}-bastion-key"
  }
}

# -------------------------
# VPC / Subnets
# -------------------------
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${local.name_prefix}-vpc"
  }
}

resource "aws_subnet" "public_1" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = {
    Name = "${local.name_prefix}-public-1"
  }
}

resource "aws_subnet" "public_2" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = data.aws_availability_zones.available.names[1]
  map_public_ip_on_launch = true

  tags = {
    Name = "${local.name_prefix}-public-2"
  }
}

resource "aws_subnet" "private_app_1" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.10.0/24"
  availability_zone = data.aws_availability_zones.available.names[0]

  tags = {
    Name = "${local.name_prefix}-private-app-1"
  }
}

resource "aws_subnet" "private_app_2" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.11.0/24"
  availability_zone = data.aws_availability_zones.available.names[1]

  tags = {
    Name = "${local.name_prefix}-private-app-2"
  }
}

resource "aws_subnet" "private_db_1" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.3.0/24"
  availability_zone = data.aws_availability_zones.available.names[0]

  tags = {
    Name = "${local.name_prefix}-private-db-1"
  }
}

resource "aws_subnet" "private_db_2" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.4.0/24"
  availability_zone = data.aws_availability_zones.available.names[1]

  tags = {
    Name = "${local.name_prefix}-private-db-2"
  }
}

# -------------------------
# Internet Gateway / Route Tables / NAT Gateway
# -------------------------
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${local.name_prefix}-igw"
  }
}

resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${local.name_prefix}-public-rt"
  }
}

resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public_rt.id
  gateway_id             = aws_internet_gateway.igw.id
  destination_cidr_block = "0.0.0.0/0"
}

resource "aws_route_table_association" "public_1_assoc" {
  subnet_id      = aws_subnet.public_1.id
  route_table_id = aws_route_table.public_rt.id
}

resource "aws_route_table_association" "public_2_assoc" {
  subnet_id      = aws_subnet.public_2.id
  route_table_id = aws_route_table.public_rt.id
}

resource "aws_eip" "nat_eip" {
  domain = "vpc"

  tags = {
    Name = "${local.name_prefix}-nat-eip"
  }
}

resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat_eip.id
  subnet_id     = aws_subnet.public_1.id
  depends_on    = [aws_internet_gateway.igw]

  tags = {
    Name = "${local.name_prefix}-nat"
  }
}

resource "aws_route_table" "private_app_rt" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${local.name_prefix}-private-app-rt"
  }
}

resource "aws_route" "private_app_nat" {
  route_table_id         = aws_route_table.private_app_rt.id
  nat_gateway_id         = aws_nat_gateway.nat.id
  destination_cidr_block = "0.0.0.0/0"
}

resource "aws_route_table_association" "private_app_1_assoc" {
  subnet_id      = aws_subnet.private_app_1.id
  route_table_id = aws_route_table.private_app_rt.id
}

resource "aws_route_table_association" "private_app_2_assoc" {
  subnet_id      = aws_subnet.private_app_2.id
  route_table_id = aws_route_table.private_app_rt.id
}

# -------------------------
# Security Groups
# -------------------------
resource "aws_security_group" "alb_sg" {
  name   = "${local.name_prefix}-alb-sg"
  vpc_id = aws_vpc.main.id

  ingress {
    from_port   = 80
    to_port     = 80
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
    Name = "${local.name_prefix}-alb-sg"
  }
}

resource "aws_security_group" "ecs_sg" {
  name   = "${local.name_prefix}-ecs-sg"
  vpc_id = aws_vpc.main.id

  ingress {
    description     = "Allow HTTP from ALB"
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.name_prefix}-ecs-sg"
  }
}

resource "aws_security_group" "bastion_sg" {
  name   = "${local.name_prefix}-bastion-sg"
  vpc_id = aws_vpc.main.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.my_ip]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.name_prefix}-bastion-sg"
  }
}

resource "aws_security_group" "rds_sg" {
  name   = "${local.name_prefix}-rds-sg"
  vpc_id = aws_vpc.main.id

  ingress {
    description     = "Allow MySQL from ECS tasks"
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs_sg.id]
  }

  ingress {
    description     = "Allow MySQL from Bastion EC2"
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion_sg.id]
  }

  tags = {
    Name = "${local.name_prefix}-rds-sg"
  }
}

resource "aws_security_group" "efs_sg" {
  name   = "${local.name_prefix}-efs-sg"
  vpc_id = aws_vpc.main.id

  ingress {
    description     = "Allow NFS from ECS tasks"
    from_port       = 2049
    to_port         = 2049
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs_sg.id]
  }

  tags = {
    Name = "${local.name_prefix}-efs-sg"
  }
}

# -------------------------
# RDS MySQL
# -------------------------
resource "aws_db_subnet_group" "db_subnet" {
  name = "${local.name_prefix}-db-subnet-group"

  subnet_ids = [
    aws_subnet.private_db_1.id,
    aws_subnet.private_db_2.id
  ]

  tags = {
    Name = "${local.name_prefix}-db-subnet-group"
  }
}

resource "aws_db_instance" "mysql" {
  identifier        = "${local.name_prefix}-mysql"
  engine            = "mysql"
  engine_version    = "8.0"
  instance_class    = "db.t3.micro"
  allocated_storage = 20
  storage_encrypted = true

  db_name  = "wordpress"
  username = var.db_user
  password = var.db_pass

  db_subnet_group_name   = aws_db_subnet_group.db_subnet.name
  vpc_security_group_ids = [aws_security_group.rds_sg.id]

  backup_retention_period = 7
  backup_window           = "18:00-19:00"
  maintenance_window      = "sun:19:00-sun:20:00"
  skip_final_snapshot     = true

  tags = {
    Name = "${local.name_prefix}-rds"
  }
}

# -------------------------
# Bastion EC2 for RDS check
# -------------------------
resource "aws_instance" "bastion" {
  ami                         = var.bastion_ami_id
  instance_type               = "t2.micro"
  subnet_id                   = aws_subnet.public_1.id
  associate_public_ip_address = true
  key_name                    = aws_key_pair.bastion_key.key_name

  vpc_security_group_ids = [aws_security_group.bastion_sg.id]

  user_data_replace_on_change = true
  user_data = <<EOF2
#!/bin/bash
set -eux
apt update -y
apt install -y mysql-client
EOF2

  tags = {
    Name = "${local.name_prefix}-bastion"
  }
}

# -------------------------
# ECR
# -------------------------
resource "aws_ecr_repository" "wordpress" {
  name                 = "${local.name_prefix}-wordpress"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  force_delete = true

  tags = {
    Name = "${local.name_prefix}-wordpress-ecr"
  }
}

# -------------------------
# Secrets Manager
# -------------------------
resource "aws_secretsmanager_secret" "wordpress" {
  name                    = "${local.name_prefix}/wordpress-db"
  recovery_window_in_days = 0

  tags = {
    Name = "${local.name_prefix}-wordpress-secret"
  }
}

resource "aws_secretsmanager_secret_version" "wordpress" {
  secret_id = aws_secretsmanager_secret.wordpress.id

  secret_string = jsonencode({
    host     = "${local.wordpress_db_host}:3306"
    username = var.db_user
    password = var.db_pass
    dbname   = "wordpress"
  })
}

# -------------------------
# EFS for WordPress files
# -------------------------
resource "aws_efs_file_system" "wordpress" {
  encrypted = true

  tags = {
    Name = "${local.name_prefix}-wordpress-efs"
  }
}

resource "aws_efs_access_point" "wordpress" {
  file_system_id = aws_efs_file_system.wordpress.id

  posix_user {
    gid = 33
    uid = 33
  }

  root_directory {
    path = "/wordpress"

    creation_info {
      owner_gid   = 33
      owner_uid   = 33
      permissions = "0755"
    }
  }

  tags = {
    Name = "${local.name_prefix}-wordpress-efs-ap"
  }
}

resource "aws_efs_mount_target" "private_app_1" {
  file_system_id  = aws_efs_file_system.wordpress.id
  subnet_id       = aws_subnet.private_app_1.id
  security_groups = [aws_security_group.efs_sg.id]
}

resource "aws_efs_mount_target" "private_app_2" {
  file_system_id  = aws_efs_file_system.wordpress.id
  subnet_id       = aws_subnet.private_app_2.id
  security_groups = [aws_security_group.efs_sg.id]
}

# -------------------------
# CloudWatch Logs
# -------------------------
resource "aws_cloudwatch_log_group" "wordpress" {
  name              = "/ecs/${local.name_prefix}-wordpress"
  retention_in_days = 7

  tags = {
    Name = "${local.name_prefix}-wordpress-logs"
  }
}

# -------------------------
# IAM for ECS task
# -------------------------
resource "aws_iam_role" "ecs_task_execution_role" {
  name               = "${local.name_prefix}-ecs-task-execution-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume_role.json
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution_managed" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role_policy" "ecs_task_execution_secrets" {
  name = "${local.name_prefix}-ecs-task-execution-secrets"
  role = aws_iam_role.ecs_task_execution_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        Resource = aws_secretsmanager_secret.wordpress.arn
      }
    ]
  })
}

resource "aws_iam_role" "ecs_task_role" {
  name               = "${local.name_prefix}-ecs-task-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume_role.json
}

resource "aws_iam_role_policy" "ecs_task_efs" {
  name = "${local.name_prefix}-ecs-task-efs"
  role = aws_iam_role.ecs_task_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "elasticfilesystem:ClientMount",
          "elasticfilesystem:ClientWrite",
          "elasticfilesystem:ClientRootAccess"
        ]
        Resource = aws_efs_file_system.wordpress.arn
      }
    ]
  })
}

# -------------------------
# ALB
# -------------------------
resource "aws_lb" "alb" {
  name               = "${local.name_prefix}-alb"
  load_balancer_type = "application"

  subnets = [
    aws_subnet.public_1.id,
    aws_subnet.public_2.id
  ]

  security_groups = [aws_security_group.alb_sg.id]

  tags = {
    Name = "${local.name_prefix}-alb"
  }
}

resource "aws_lb_target_group" "tg" {
  name        = "${local.name_prefix}-tg"
  port        = 80
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = aws_vpc.main.id

  health_check {
    path                = "/"
    protocol            = "HTTP"
    matcher             = "200-499"
    interval            = 30
    timeout             = 10
    healthy_threshold   = 2
    unhealthy_threshold = 10
  }

  tags = {
    Name = "${local.name_prefix}-tg"
  }
}

resource "aws_lb_listener" "listener" {
  load_balancer_arn = aws_lb.alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tg.arn
  }
}

# -------------------------
# ECS Fargate
# -------------------------
resource "aws_ecs_cluster" "main" {
  name = "${local.name_prefix}-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = {
    Name = "${local.name_prefix}-cluster"
  }
}

resource "aws_ecs_task_definition" "wordpress" {
  family                   = "${local.name_prefix}-wordpress"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "512"
  memory                   = "1024"
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_task_role.arn

  volume {
    name = "wordpress-files"

    efs_volume_configuration {
      file_system_id     = aws_efs_file_system.wordpress.id
      transit_encryption = "ENABLED"

      authorization_config {
        access_point_id = aws_efs_access_point.wordpress.id
        iam             = "ENABLED"
      }
    }
  }

  container_definitions = jsonencode([
    {
      name      = "wordpress"
      image     = local.ecr_image_uri
      essential = true

      portMappings = [
        {
          containerPort = 80
          hostPort      = 80
          protocol      = "tcp"
        }
      ]

      environment = [
        { name = "WORDPRESS_DB_NAME", value = "wordpress" },
        { name = "WORDPRESS_CONFIG_EXTRA", value = "define('FORCE_SSL_ADMIN', true); if (isset($_SERVER['HTTP_CLOUDFRONT_FORWARDED_PROTO']) && $_SERVER['HTTP_CLOUDFRONT_FORWARDED_PROTO'] === 'https') { $_SERVER['HTTPS'] = 'on'; }" }
      ]

      secrets = [
        { name = "WORDPRESS_DB_HOST", valueFrom = "${aws_secretsmanager_secret.wordpress.arn}:host::" },
        { name = "WORDPRESS_DB_USER", valueFrom = "${aws_secretsmanager_secret.wordpress.arn}:username::" },
        { name = "WORDPRESS_DB_PASSWORD", valueFrom = "${aws_secretsmanager_secret.wordpress.arn}:password::" }
      ]

      mountPoints = [
        {
          sourceVolume  = "wordpress-files"
          containerPath = "/var/www/html"
          readOnly      = false
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.wordpress.name
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = "wordpress"
        }
      }
    }
  ])

  depends_on = [
    aws_efs_mount_target.private_app_1,
    aws_efs_mount_target.private_app_2
  ]

  tags = {
    Name = "${local.name_prefix}-wordpress-task"
  }
}

resource "aws_ecs_service" "wordpress" {
  name            = "${local.name_prefix}-wordpress-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.wordpress.arn
  desired_count   = 2
  launch_type     = "FARGATE"

  deployment_minimum_healthy_percent = 50
  deployment_maximum_percent         = 200

  network_configuration {
    subnets          = [aws_subnet.private_app_1.id, aws_subnet.private_app_2.id]
    security_groups  = [aws_security_group.ecs_sg.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.tg.arn
    container_name   = "wordpress"
    container_port   = 80
  }

  depends_on = [
    aws_lb_listener.listener,
    aws_iam_role_policy_attachment.ecs_task_execution_managed,
    aws_iam_role_policy.ecs_task_execution_secrets,
    aws_iam_role_policy.ecs_task_efs
  ]

  tags = {
    Name = "${local.name_prefix}-wordpress-service"
  }
}

# -------------------------
# CloudFront
# -------------------------
resource "aws_cloudfront_distribution" "wordpress" {
  enabled         = true
  is_ipv6_enabled = true
  comment         = "${local.name_prefix}-wordpress-cloudfront"

  origin {
    domain_name = aws_lb.alb.dns_name
    origin_id   = "alb"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }

    custom_header {
      name  = "X-Forwarded-Proto"
      value = "https"
    }
  }

  default_cache_behavior {
    target_origin_id       = "alb"
    viewer_protocol_policy = "redirect-to-https"

    allowed_methods = ["GET", "HEAD", "OPTIONS", "POST", "PUT", "DELETE", "PATCH"]
    cached_methods  = ["GET", "HEAD"]

    forwarded_values {
      query_string = true
      headers      = ["CloudFront-Forwarded-Proto", "Host"]

      cookies {
        forward = "all"
      }
    }

    min_ttl     = 0
    default_ttl = 0
    max_ttl     = 0
  }

  restrictions {
    geo_restriction {
      restriction_type = "whitelist"
      locations        = ["JP"]
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }

  tags = {
    Name = "${local.name_prefix}-cloudfront"
  }
}
