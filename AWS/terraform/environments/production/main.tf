# ─────────────────────────────────────────────────────────────
# IronLog — AWS Production Infrastructure
# terraform/environments/production/main.tf
#
# Architecture:
#   Internet → CloudFront → ALB → ECS Fargate (NestJS API)
#                                     ↓           ↓
#                                   RDS       ElastiCache
#                                (PostgreSQL)   (Redis)
#
#   All private resources live in private subnets.
#   RDS and Redis have NO public access.
#   Secrets stored in AWS Secrets Manager.
# ─────────────────────────────────────────────────────────────

terraform {
  required_version = ">= 1.7.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.40"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  # Remote state — S3 backend with DynamoDB locking
  backend "s3" {
    bucket         = "ironlog-terraform-state-prod"
    key            = "production/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "ironlog-terraform-locks"
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "IronLog"
      Environment = "production"
      ManagedBy   = "Terraform"
      Owner       = var.team_email
    }
  }
}

# Secondary provider for CloudFront ACM (must be us-east-1)
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"

  default_tags {
    tags = {
      Project     = "IronLog"
      Environment = "production"
      ManagedBy   = "Terraform"
    }
  }
}

# ─────────────────────────────────────────────────────────────
# DATA SOURCES
# ─────────────────────────────────────────────────────────────
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# ─────────────────────────────────────────────────────────────
# MODULES
# ─────────────────────────────────────────────────────────────

# VPC — isolated network with public/private subnets
module "vpc" {
  source = "../../modules/vpc"

  name               = "ironlog-prod"
  cidr               = "10.0.0.0/16"
  azs                = ["${var.aws_region}a", "${var.aws_region}b", "${var.aws_region}c"]
  public_subnets     = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  private_subnets    = ["10.0.10.0/24", "10.0.11.0/24", "10.0.12.0/24"]
  database_subnets   = ["10.0.20.0/24", "10.0.21.0/24", "10.0.22.0/24"]
  enable_nat_gateway = true
  single_nat_gateway = false   # HA: one NAT per AZ in production
}

# Secrets — rotate automatically
module "secrets" {
  source = "../../modules/secrets"

  name_prefix     = "ironlog/prod"
  db_username     = var.db_username
  recovery_window = 30
}

# RDS — PostgreSQL 16 Multi-AZ
module "rds" {
  source = "../../modules/rds"

  identifier          = "ironlog-prod"
  engine_version      = "16.2"
  instance_class      = "db.t4g.medium"    # 2 vCPU, 4 GB RAM
  allocated_storage   = 50
  max_allocated_storage = 200              # Auto-scaling up to 200 GB
  multi_az            = true
  db_name             = "ironlog"
  username            = var.db_username
  password_secret_arn = module.secrets.db_password_arn
  vpc_id              = module.vpc.vpc_id
  subnet_ids          = module.vpc.database_subnet_ids
  security_group_ids  = [module.vpc.db_security_group_id]

  # Backups
  backup_retention_period    = 14
  backup_window              = "03:00-04:00"
  maintenance_window         = "Mon:04:00-Mon:05:00"
  deletion_protection        = true
  skip_final_snapshot        = false
  final_snapshot_identifier  = "ironlog-prod-final-snapshot"

  # Performance
  performance_insights_enabled = true
  monitoring_interval          = 60
  enabled_cloudwatch_logs      = ["postgresql", "upgrade"]
}

# ElastiCache — Redis 7 (cluster mode disabled for simplicity)
module "elasticache" {
  source = "../../modules/elasticache"

  cluster_id         = "ironlog-prod"
  engine_version     = "7.1"
  node_type          = "cache.t4g.small"
  num_cache_nodes    = 2                  # Primary + 1 replica
  vpc_id             = module.vpc.vpc_id
  subnet_ids         = module.vpc.private_subnet_ids
  security_group_ids = [module.vpc.redis_security_group_id]
  at_rest_encryption = true
  transit_encryption = true
  auth_token_arn     = module.secrets.redis_auth_token_arn
  auto_failover      = true
  snapshot_retention = 5
}

# S3 — media storage, backups, Flutter web assets
module "s3" {
  source = "../../modules/s3"

  bucket_prefix    = "ironlog-prod"
  media_bucket_name   = "ironlog-prod-media"
  backups_bucket_name = "ironlog-prod-backups"
  assets_bucket_name  = "ironlog-prod-assets"
  account_id       = data.aws_caller_identity.current.account_id

  # Lifecycle: move old backups to Glacier after 90 days
  backup_lifecycle_days_glacier = 90
  backup_lifecycle_days_delete  = 365
}

# IAM — ECS task roles
module "iam" {
  source = "../../modules/iam"

  name_prefix        = "ironlog-prod"
  account_id         = data.aws_caller_identity.current.account_id
  aws_region         = var.aws_region
  media_bucket_arn   = module.s3.media_bucket_arn
  backups_bucket_arn = module.s3.backups_bucket_arn
  secret_arns        = module.secrets.all_secret_arns
  rds_resource_id    = module.rds.resource_id
}

# ALB — Application Load Balancer
module "alb" {
  source = "../../modules/alb"

  name            = "ironlog-prod"
  vpc_id          = module.vpc.vpc_id
  subnet_ids      = module.vpc.public_subnet_ids
  certificate_arn = var.acm_certificate_arn
  domain_name     = var.api_domain_name

  # Health check
  health_check_path     = "/health"
  health_check_interval = 30
  health_check_timeout  = 10
  healthy_threshold     = 2
  unhealthy_threshold   = 3

  # Access logs
  access_logs_bucket = module.s3.backups_bucket_name
}

# ECS — Fargate cluster running NestJS API
module "ecs" {
  source = "../../modules/ecs"

  cluster_name   = "ironlog-prod"
  service_name   = "ironlog-api"
  vpc_id         = module.vpc.vpc_id
  subnet_ids     = module.vpc.private_subnet_ids

  # Container
  image_uri      = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.aws_region}.amazonaws.com/ironlog-api:${var.image_tag}"
  container_port = 3000
  cpu            = 512       # 0.5 vCPU
  memory         = 1024      # 1 GB RAM

  # Scaling
  desired_count  = 2
  min_capacity   = 2
  max_capacity   = 10
  scale_cpu_target   = 60.0
  scale_memory_target= 70.0

  # Networking
  target_group_arn   = module.alb.target_group_arn
  security_group_ids = [module.vpc.ecs_security_group_id]

  # IAM
  execution_role_arn = module.iam.ecs_execution_role_arn
  task_role_arn      = module.iam.ecs_task_role_arn

  # Environment
  environment_variables = {
    NODE_ENV    = "production"
    PORT        = "3000"
    DB_HOST     = module.rds.endpoint
    DB_PORT     = "5432"
    DB_NAME     = "ironlog"
    DB_SSL      = "true"
    REDIS_HOST  = module.elasticache.primary_endpoint
    REDIS_PORT  = "6379"
    REDIS_TLS   = "true"
    CORS_ORIGIN = "https://${var.api_domain_name},https://${var.app_domain_name}"
    AWS_REGION  = var.aws_region
    S3_MEDIA_BUCKET = module.s3.media_bucket_name
  }

  # Secrets from Secrets Manager (injected at container start)
  secrets = {
    DB_USER            = "${module.secrets.db_credentials_arn}:username::"
    DB_PASSWORD        = "${module.secrets.db_credentials_arn}:password::"
    JWT_SECRET         = "${module.secrets.jwt_secret_arn}::"
    JWT_REFRESH_SECRET = "${module.secrets.jwt_refresh_secret_arn}::"
    REDIS_AUTH_TOKEN   = "${module.secrets.redis_auth_token_arn}::"
    GOOGLE_CLIENT_ID   = "${module.secrets.google_client_id_arn}::"
    APPLE_CLIENT_ID    = "${module.secrets.apple_client_id_arn}::"
  }

  # Logging
  log_group_name      = "/ecs/ironlog-prod/api"
  log_retention_days  = 30

  # Health check
  health_check_command = ["CMD-SHELL", "curl -f http://localhost:3000/health || exit 1"]
}

# CloudFront — CDN in front of ALB + S3
module "cloudfront" {
  source = "../../modules/cloudfront"

  providers = { aws = aws.us_east_1 }

  aliases              = [var.api_domain_name, var.app_domain_name]
  acm_certificate_arn  = var.acm_certificate_arn_us_east_1
  alb_dns_name         = module.alb.dns_name
  assets_bucket_domain = module.s3.assets_bucket_regional_domain
  price_class          = "PriceClass_100"  # US, Canada, Europe
  waf_web_acl_id       = module.alb.waf_web_acl_id

  api_path_pattern     = "/api/*"
  health_path_pattern  = "/health"
}

# ─────────────────────────────────────────────────────────────
# OUTPUTS
# ─────────────────────────────────────────────────────────────
output "api_url"           { value = "https://${var.api_domain_name}" }
output "cloudfront_url"    { value = module.cloudfront.distribution_domain }
output "rds_endpoint"      { value = module.rds.endpoint }
output "redis_endpoint"    { value = module.elasticache.primary_endpoint }
output "ecr_repository"    { value = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.aws_region}.amazonaws.com/ironlog-api" }
output "ecs_cluster"       { value = module.ecs.cluster_name }
output "alb_dns"           { value = module.alb.dns_name }
output "media_bucket"      { value = module.s3.media_bucket_name }
