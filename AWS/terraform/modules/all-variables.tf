# ─────────────────────────────────────────────────────────────
# terraform/modules/vpc/variables.tf
# ─────────────────────────────────────────────────────────────
variable "name"               { type = string }
variable "cidr"               { type = string }
variable "azs"                { type = list(string) }
variable "public_subnets"     { type = list(string) }
variable "private_subnets"    { type = list(string) }
variable "database_subnets"   { type = list(string) }
variable "enable_nat_gateway" { type = bool; default = true }
variable "single_nat_gateway" { type = bool; default = false }

# ─────────────────────────────────────────────────────────────
# terraform/modules/rds/variables.tf
# ─────────────────────────────────────────────────────────────
variable "identifier"              { type = string }
variable "engine_version"          { type = string;  default = "16.2" }
variable "instance_class"          { type = string }
variable "allocated_storage"       { type = number;  default = 20 }
variable "max_allocated_storage"   { type = number;  default = 100 }
variable "multi_az"                { type = bool;    default = false }
variable "db_name"                 { type = string }
variable "username"                { type = string }
variable "password_secret_arn"     { type = string }
variable "vpc_id"                  { type = string }
variable "subnet_ids"              { type = list(string) }
variable "security_group_ids"      { type = list(string) }
variable "backup_retention_period" { type = number;  default = 7 }
variable "backup_window"           { type = string;  default = "03:00-04:00" }
variable "maintenance_window"      { type = string;  default = "Mon:04:00-Mon:05:00" }
variable "deletion_protection"     { type = bool;    default = true }
variable "skip_final_snapshot"     { type = bool;    default = false }
variable "final_snapshot_identifier" { type = string; default = "final-snapshot" }
variable "performance_insights_enabled" { type = bool; default = true }
variable "monitoring_interval"     { type = number;  default = 60 }
variable "enabled_cloudwatch_logs" { type = list(string); default = ["postgresql"] }
variable "create_read_replica"     { type = bool;    default = false }
variable "db_username"             { type = string;  default = "ironlog" }

# ─────────────────────────────────────────────────────────────
# terraform/modules/elasticache/variables.tf
# ─────────────────────────────────────────────────────────────
variable "cluster_id"          { type = string }
variable "engine_version"      { type = string;  default = "7.1" }
variable "node_type"           { type = string }
variable "num_cache_nodes"     { type = number;  default = 2 }
variable "vpc_id"              { type = string }
variable "subnet_ids"          { type = list(string) }
variable "security_group_ids"  { type = list(string) }
variable "at_rest_encryption"  { type = bool;    default = true }
variable "transit_encryption"  { type = bool;    default = true }
variable "auth_token_arn"      { type = string }
variable "auto_failover"       { type = bool;    default = true }
variable "snapshot_retention"  { type = number;  default = 5 }

# ─────────────────────────────────────────────────────────────
# terraform/modules/ecs/variables.tf
# ─────────────────────────────────────────────────────────────
variable "cluster_name"           { type = string }
variable "service_name"           { type = string }
variable "vpc_id"                 { type = string }
variable "subnet_ids"             { type = list(string) }
variable "image_uri"              { type = string }
variable "container_port"         { type = number;  default = 3000 }
variable "cpu"                    { type = number;  default = 512 }
variable "memory"                 { type = number;  default = 1024 }
variable "desired_count"          { type = number;  default = 2 }
variable "min_capacity"           { type = number;  default = 2 }
variable "max_capacity"           { type = number;  default = 10 }
variable "scale_cpu_target"       { type = number;  default = 60 }
variable "scale_memory_target"    { type = number;  default = 70 }
variable "target_group_arn"       { type = string }
variable "security_group_ids"     { type = list(string) }
variable "execution_role_arn"     { type = string }
variable "task_role_arn"          { type = string }
variable "environment_variables"  { type = map(string); default = {} }
variable "secrets"                { type = map(string); default = {} }
variable "log_group_name"         { type = string }
variable "log_retention_days"     { type = number;  default = 30 }
variable "health_check_command"   { type = list(string) }
variable "sns_alarm_arn"          { type = string;  default = null }
variable "alb_resource_label"     { type = string;  default = "" }

# ─────────────────────────────────────────────────────────────
# terraform/modules/alb/variables.tf
# ─────────────────────────────────────────────────────────────
variable "name"                  { type = string }
variable "vpc_id"                { type = string }
variable "subnet_ids"            { type = list(string) }
variable "certificate_arn"       { type = string }
variable "domain_name"           { type = string }
variable "health_check_path"     { type = string;  default = "/health" }
variable "health_check_interval" { type = number;  default = 30 }
variable "health_check_timeout"  { type = number;  default = 10 }
variable "healthy_threshold"     { type = number;  default = 2 }
variable "unhealthy_threshold"   { type = number;  default = 3 }
variable "access_logs_bucket"    { type = string }

# ─────────────────────────────────────────────────────────────
# terraform/modules/cloudfront/variables.tf
# ─────────────────────────────────────────────────────────────
variable "aliases"                { type = list(string) }
variable "acm_certificate_arn"    { type = string }
variable "alb_dns_name"           { type = string }
variable "assets_bucket_domain"   { type = string }
variable "price_class"            { type = string;  default = "PriceClass_100" }
variable "waf_web_acl_id"         { type = string;  default = null }
variable "api_path_pattern"       { type = string;  default = "/api/*" }
variable "health_path_pattern"    { type = string;  default = "/health" }
variable "logs_bucket"            { type = string;  default = "" }

# ─────────────────────────────────────────────────────────────
# terraform/modules/s3/variables.tf
# ─────────────────────────────────────────────────────────────
variable "bucket_prefix"                  { type = string }
variable "media_bucket_name"              { type = string }
variable "backups_bucket_name"            { type = string }
variable "assets_bucket_name"             { type = string }
variable "account_id"                     { type = string }
variable "backup_lifecycle_days_glacier"  { type = number; default = 90 }
variable "backup_lifecycle_days_delete"   { type = number; default = 365 }
variable "cloudfront_distribution_arn"    { type = string; default = null }

# ─────────────────────────────────────────────────────────────
# terraform/modules/iam/variables.tf
# ─────────────────────────────────────────────────────────────
variable "name_prefix"       { type = string }
variable "account_id"        { type = string }
variable "aws_region"        { type = string }
variable "media_bucket_arn"  { type = string }
variable "backups_bucket_arn"{ type = string }
variable "secret_arns"       { type = list(string) }
variable "rds_resource_id"   { type = string }
variable "db_username"       { type = string;  default = "ironlog" }
variable "github_org"        { type = string;  default = "your-org" }
variable "github_repo"       { type = string;  default = "ironlog" }

# ─────────────────────────────────────────────────────────────
# terraform/modules/secrets/variables.tf
# ─────────────────────────────────────────────────────────────
variable "name_prefix"       { type = string }
variable "db_username"       { type = string }
variable "recovery_window"   { type = number; default = 30 }

# ─────────────────────────────────────────────────────────────
# terraform/modules/monitoring/variables.tf
# ─────────────────────────────────────────────────────────────
variable "alert_email"               { type = string; default = null }
variable "slack_webhook_url"         { type = string; default = null }
variable "alb_arn_suffix"            { type = string }
variable "target_group_arn_suffix"   { type = string }
variable "ecs_cluster_name"          { type = string }
variable "ecs_service_name"          { type = string }
variable "ecs_log_group_name"        { type = string }
variable "rds_identifier"            { type = string }
variable "redis_replication_group_id"{ type = string }
variable "alb_unhealthy_alarm_arn"   { type = string }
variable "ecs_task_low_alarm_arn"    { type = string }
variable "alb_5xx_alarm_arn"         { type = string }
