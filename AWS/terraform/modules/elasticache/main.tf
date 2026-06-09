# terraform/modules/elasticache/main.tf
# ElastiCache Redis with replication group, TLS, and auth token

# ─────────────────────────────────────────────────────────────
# PARAMETER GROUP — Redis tuning
# ─────────────────────────────────────────────────────────────
resource "aws_elasticache_parameter_group" "main" {
  family = "redis7"
  name   = "${var.cluster_id}-params"

  parameter {
    name  = "maxmemory-policy"
    value = "allkeys-lru"    # Evict least-recently-used keys when full
  }
  parameter {
    name  = "activerehashing"
    value = "yes"
  }
  parameter {
    name  = "hz"
    value = "15"    # Higher background task frequency
  }
  parameter {
    name  = "timeout"
    value = "300"   # Close idle connections after 5 minutes
  }
  parameter {
    name  = "tcp-keepalive"
    value = "60"
  }

  tags = { Name = "${var.cluster_id}-params" }
}

# ─────────────────────────────────────────────────────────────
# AUTH TOKEN FROM SECRETS MANAGER
# ─────────────────────────────────────────────────────────────
data "aws_secretsmanager_secret_version" "redis_auth" {
  secret_id = var.auth_token_arn
}

# ─────────────────────────────────────────────────────────────
# REPLICATION GROUP (Primary + Replicas)
# ─────────────────────────────────────────────────────────────
resource "aws_elasticache_replication_group" "main" {
  replication_group_id = var.cluster_id
  description          = "IronLog Redis — session cache, rate limiting, queues"

  node_type            = var.node_type
  num_cache_clusters   = var.num_cache_nodes    # 1 primary + N-1 replicas
  port                 = 6379

  # Network
  subnet_group_name  = var.subnet_ids != null ? aws_elasticache_subnet_group.main.name : null
  security_group_ids = var.security_group_ids

  # Encryption
  at_rest_encryption_enabled  = var.at_rest_encryption
  transit_encryption_enabled  = var.transit_encryption
  auth_token                  = var.transit_encryption ? data.aws_secretsmanager_secret_version.redis_auth.secret_string : null

  # High availability
  automatic_failover_enabled = var.auto_failover    # Requires num_cache_clusters >= 2
  multi_az_enabled           = var.auto_failover

  # Engine
  engine_version         = var.engine_version
  parameter_group_name   = aws_elasticache_parameter_group.main.name

  # Backups
  snapshot_retention_limit = var.snapshot_retention
  snapshot_window          = "05:00-06:00"
  maintenance_window       = "sun:06:00-sun:07:00"

  # Logs
  log_delivery_configuration {
    destination      = aws_cloudwatch_log_group.redis_slow.name
    destination_type = "cloudwatch-logs"
    log_format       = "text"
    log_type         = "slow-log"
  }

  log_delivery_configuration {
    destination      = aws_cloudwatch_log_group.redis_engine.name
    destination_type = "cloudwatch-logs"
    log_format       = "json"
    log_type         = "engine-log"
  }

  apply_immediately = false

  tags = { Name = var.cluster_id }
}

# ─────────────────────────────────────────────────────────────
# SUBNET GROUP
# ─────────────────────────────────────────────────────────────
resource "aws_elasticache_subnet_group" "main" {
  name       = "${var.cluster_id}-subnet-group"
  subnet_ids = var.subnet_ids
  tags       = { Name = "${var.cluster_id}-subnet-group" }
}

# ─────────────────────────────────────────────────────────────
# CLOUDWATCH LOGS
# ─────────────────────────────────────────────────────────────
resource "aws_cloudwatch_log_group" "redis_slow" {
  name              = "/elasticache/${var.cluster_id}/slow-log"
  retention_in_days = 14
}

resource "aws_cloudwatch_log_group" "redis_engine" {
  name              = "/elasticache/${var.cluster_id}/engine-log"
  retention_in_days = 7
}

# ─────────────────────────────────────────────────────────────
# CLOUDWATCH ALARMS
# ─────────────────────────────────────────────────────────────
resource "aws_cloudwatch_metric_alarm" "cpu" {
  alarm_name          = "${var.cluster_id}-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ElastiCache"
  period              = 60
  statistic           = "Average"
  threshold           = 80
  alarm_description   = "Redis CPU above 80%"

  dimensions = { ReplicationGroupId = aws_elasticache_replication_group.main.id }
}

resource "aws_cloudwatch_metric_alarm" "memory" {
  alarm_name          = "${var.cluster_id}-memory-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "DatabaseMemoryUsagePercentage"
  namespace           = "AWS/ElastiCache"
  period              = 60
  statistic           = "Average"
  threshold           = 80
  alarm_description   = "Redis memory above 80%"

  dimensions = { ReplicationGroupId = aws_elasticache_replication_group.main.id }
}

resource "aws_cloudwatch_metric_alarm" "evictions" {
  alarm_name          = "${var.cluster_id}-evictions"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "Evictions"
  namespace           = "AWS/ElastiCache"
  period              = 60
  statistic           = "Sum"
  threshold           = 100
  alarm_description   = "Redis is evicting keys — consider scaling"

  dimensions = { ReplicationGroupId = aws_elasticache_replication_group.main.id }
}

# ─────────────────────────────────────────────────────────────
# OUTPUTS
# ─────────────────────────────────────────────────────────────
output "primary_endpoint"    { value = aws_elasticache_replication_group.main.primary_endpoint_address }
output "reader_endpoint"     { value = aws_elasticache_replication_group.main.reader_endpoint_address }
output "replication_group_id"{ value = aws_elasticache_replication_group.main.id }
output "port"                { value = aws_elasticache_replication_group.main.port }
