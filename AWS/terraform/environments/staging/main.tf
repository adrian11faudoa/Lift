# terraform/environments/staging/main.tf
# Staging: same architecture as production, smaller + cheaper instances

terraform {
  required_version = ">= 1.7.0"
  required_providers {
    aws    = { source = "hashicorp/aws", version = "~> 5.40" }
    random = { source = "hashicorp/random", version = "~> 3.6" }
  }

  backend "s3" {
    bucket         = "ironlog-terraform-state-prod"
    key            = "staging/terraform.tfstate"
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
      Environment = "staging"
      ManagedBy   = "Terraform"
    }
  }
}

provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
}

data "aws_caller_identity" "current" {}

# ── Modules (same as prod, smaller sizes) ───────────────────
module "vpc" {
  source = "../../modules/vpc"

  name               = "ironlog-staging"
  cidr               = "10.1.0.0/16"
  azs                = ["${var.aws_region}a", "${var.aws_region}b"]
  public_subnets     = ["10.1.1.0/24", "10.1.2.0/24"]
  private_subnets    = ["10.1.10.0/24", "10.1.11.0/24"]
  database_subnets   = ["10.1.20.0/24", "10.1.21.0/24"]
  enable_nat_gateway = true
  single_nat_gateway = true    # Cost savings: one NAT for staging
}

module "secrets" {
  source          = "../../modules/secrets"
  name_prefix     = "ironlog/staging"
  db_username     = var.db_username
  recovery_window = 7    # Shorter recovery for staging
}

module "rds" {
  source = "../../modules/rds"

  identifier            = "ironlog-staging"
  engine_version        = "16.2"
  instance_class        = "db.t4g.micro"    # Smallest — ~$13/month
  allocated_storage     = 20
  max_allocated_storage = 50
  multi_az              = false             # No HA in staging
  db_name               = "ironlog"
  username              = var.db_username
  password_secret_arn   = module.secrets.db_password_arn
  vpc_id                = module.vpc.vpc_id
  subnet_ids            = module.vpc.database_subnet_ids
  security_group_ids    = [module.vpc.db_security_group_id]

  backup_retention_period = 3
  deletion_protection     = false
  skip_final_snapshot     = true

  performance_insights_enabled = false
  monitoring_interval          = 0
  enabled_cloudwatch_logs      = ["postgresql"]
}

module "elasticache" {
  source = "../../modules/elasticache"

  cluster_id         = "ironlog-staging"
  engine_version     = "7.1"
  node_type          = "cache.t4g.micro"    # Smallest — ~$11/month
  num_cache_nodes    = 1                    # No replica in staging
  vpc_id             = module.vpc.vpc_id
  subnet_ids         = module.vpc.private_subnet_ids
  security_group_ids = [module.vpc.redis_security_group_id]
  at_rest_encryption = true
  transit_encryption = true
  auth_token_arn     = module.secrets.redis_auth_token_arn
  auto_failover      = false
  snapshot_retention = 1
}

module "s3" {
  source              = "../../modules/s3"
  bucket_prefix       = "ironlog-staging"
  media_bucket_name   = "ironlog-staging-media"
  backups_bucket_name = "ironlog-staging-backups"
  assets_bucket_name  = "ironlog-staging-assets"
  account_id          = data.aws_caller_identity.current.account_id

  backup_lifecycle_days_glacier = 30
  backup_lifecycle_days_delete  = 90
}

module "iam" {
  source = "../../modules/iam"

  name_prefix        = "ironlog-staging"
  account_id         = data.aws_caller_identity.current.account_id
  aws_region         = var.aws_region
  media_bucket_arn   = module.s3.media_bucket_arn
  backups_bucket_arn = module.s3.backups_bucket_arn
  secret_arns        = module.secrets.all_secret_arns
  rds_resource_id    = module.rds.resource_id
  github_org         = var.github_org
  github_repo        = var.github_repo
}

module "alb" {
  source = "../../modules/alb"

  name            = "ironlog-staging"
  vpc_id          = module.vpc.vpc_id
  subnet_ids      = module.vpc.public_subnet_ids
  certificate_arn = var.acm_certificate_arn
  domain_name     = var.api_domain_name

  health_check_path     = "/health"
  health_check_interval = 30
  health_check_timeout  = 10
  healthy_threshold     = 2
  unhealthy_threshold   = 3

  access_logs_bucket = module.s3.backups_bucket_name
}

module "ecs" {
  source = "../../modules/ecs"

  cluster_name   = "ironlog-staging"
  service_name   = "ironlog-api"
  vpc_id         = module.vpc.vpc_id
  subnet_ids     = module.vpc.private_subnet_ids

  # Smaller than production
  image_uri      = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.aws_region}.amazonaws.com/ironlog-api:${var.image_tag}"
  container_port = 3000
  cpu            = 256      # 0.25 vCPU
  memory         = 512      # 0.5 GB

  desired_count  = 1        # Single task in staging
  min_capacity   = 1
  max_capacity   = 3
  scale_cpu_target    = 70.0
  scale_memory_target = 80.0

  target_group_arn   = module.alb.target_group_arn
  security_group_ids = [module.vpc.ecs_security_group_id]
  execution_role_arn = module.iam.ecs_execution_role_arn
  task_role_arn      = module.iam.ecs_task_role_arn

  environment_variables = {
    NODE_ENV        = "staging"
    PORT            = "3000"
    DB_HOST         = module.rds.endpoint
    DB_PORT         = "5432"
    DB_NAME         = "ironlog"
    DB_SSL          = "true"
    REDIS_HOST      = module.elasticache.primary_endpoint
    REDIS_PORT      = "6379"
    REDIS_TLS       = "true"
    CORS_ORIGIN     = "https://${var.api_domain_name},https://${var.app_domain_name}"
    AWS_REGION      = var.aws_region
    S3_MEDIA_BUCKET = module.s3.media_bucket_name
  }

  secrets = {
    DB_USER            = "${module.secrets.db_credentials_arn}:username::"
    DB_PASSWORD        = "${module.secrets.db_credentials_arn}:password::"
    JWT_SECRET         = "${module.secrets.jwt_secret_arn}::"
    JWT_REFRESH_SECRET = "${module.secrets.jwt_refresh_secret_arn}::"
    REDIS_AUTH_TOKEN   = "${module.secrets.redis_auth_token_arn}::"
    GOOGLE_CLIENT_ID   = "${module.secrets.google_client_id_arn}::"
    APPLE_CLIENT_ID    = "${module.secrets.apple_client_id_arn}::"
  }

  log_group_name     = "/ecs/ironlog-staging/api"
  log_retention_days = 7

  health_check_command = ["CMD-SHELL", "curl -f http://localhost:3000/health || exit 1"]
}

# ── Variables ────────────────────────────────────────────────
variable "aws_region"              { default = "us-east-1" }
variable "db_username"             { default = "ironlog" }
variable "acm_certificate_arn"    { type = string }
variable "api_domain_name"        { default = "staging-api.ironlog.app" }
variable "app_domain_name"        { default = "staging.ironlog.app" }
variable "image_tag"              { default = "staging-latest" }
variable "github_org"             { type = string }
variable "github_repo"            { default = "ironlog" }

# ── Outputs ──────────────────────────────────────────────────
output "api_url"         { value = "https://${var.api_domain_name}" }
output "rds_endpoint"    { value = module.rds.endpoint }
output "redis_endpoint"  { value = module.elasticache.primary_endpoint }
output "alb_dns"         { value = module.alb.dns_name }
