# terraform/modules/rds/main.tf

# ─────────────────────────────────────────────────────────────
# PARAMETER GROUP — optimized PostgreSQL settings
# ─────────────────────────────────────────────────────────────
resource "aws_db_parameter_group" "main" {
  family = "postgres16"
  name   = "${var.identifier}-params"

  parameter {
    name  = "log_connections"
    value = "1"
  }
  parameter {
    name  = "log_disconnections"
    value = "1"
  }
  parameter {
    name  = "log_duration"
    value = "1"
  }
  parameter {
    name  = "log_min_duration_statement"
    value = "1000"    # Log queries > 1 second
  }
  parameter {
    name  = "shared_preload_libraries"
    value = "pg_stat_statements"
  }
  parameter {
    name  = "pg_stat_statements.track"
    value = "ALL"
  }
  parameter {
    name         = "max_connections"
    value        = "200"
    apply_method = "pending-reboot"
  }
  parameter {
    name  = "work_mem"
    value = "16384"    # 16MB per query sort/hash
  }
  parameter {
    name         = "shared_buffers"
    value        = "{DBInstanceClassMemory/32768}"
    apply_method = "pending-reboot"
  }

  tags = { Name = "${var.identifier}-params" }
}

# ─────────────────────────────────────────────────────────────
# DB SUBNET GROUP
# ─────────────────────────────────────────────────────────────
resource "aws_db_subnet_group" "main" {
  name       = "${var.identifier}-subnet-group"
  subnet_ids = var.subnet_ids
  tags       = { Name = "${var.identifier}-subnet-group" }
}

# ─────────────────────────────────────────────────────────────
# MASTER PASSWORD — from Secrets Manager
# ─────────────────────────────────────────────────────────────
data "aws_secretsmanager_secret_version" "db_password" {
  secret_id = var.password_secret_arn
}

# ─────────────────────────────────────────────────────────────
# RDS INSTANCE
# ─────────────────────────────────────────────────────────────
resource "aws_db_instance" "main" {
  identifier = var.identifier

  # Engine
  engine         = "postgres"
  engine_version = var.engine_version
  instance_class = var.instance_class

  # Storage
  allocated_storage     = var.allocated_storage
  max_allocated_storage = var.max_allocated_storage
  storage_type          = "gp3"
  storage_encrypted     = true
  iops                  = 3000    # Baseline gp3 IOPS

  # Database
  db_name  = var.db_name
  username = var.username
  password = jsondecode(data.aws_secretsmanager_secret_version.db_password.secret_string)["password"]

  # Network
  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = var.security_group_ids
  publicly_accessible    = false    # Never public

  # High Availability
  multi_az               = var.multi_az
  availability_zone      = var.multi_az ? null : "${data.aws_region.current.name}a"

  # Parameters
  parameter_group_name = aws_db_parameter_group.main.name

  # Backups
  backup_retention_period = var.backup_retention_period
  backup_window           = var.backup_window
  maintenance_window      = var.maintenance_window
  copy_tags_to_snapshot   = true

  # Performance
  performance_insights_enabled          = var.performance_insights_enabled
  performance_insights_retention_period = 7    # Days (free tier = 7)
  monitoring_interval                   = var.monitoring_interval
  monitoring_role_arn                   = var.monitoring_interval > 0 ? aws_iam_role.rds_monitoring[0].arn : null
  enabled_cloudwatch_logs_exports       = var.enabled_cloudwatch_logs

  # Lifecycle
  deletion_protection       = var.deletion_protection
  skip_final_snapshot       = var.skip_final_snapshot
  final_snapshot_identifier = var.final_snapshot_identifier
  apply_immediately         = false    # Production: apply during maintenance window

  tags = { Name = var.identifier }
}

# ─────────────────────────────────────────────────────────────
# READ REPLICA (optional — for read scaling)
# ─────────────────────────────────────────────────────────────
resource "aws_db_instance" "replica" {
  count = var.create_read_replica ? 1 : 0

  identifier             = "${var.identifier}-replica"
  replicate_source_db    = aws_db_instance.main.identifier
  instance_class         = var.instance_class
  publicly_accessible    = false
  storage_encrypted      = true
  vpc_security_group_ids = var.security_group_ids

  performance_insights_enabled = var.performance_insights_enabled
  monitoring_interval          = var.monitoring_interval
  monitoring_role_arn          = var.monitoring_interval > 0 ? aws_iam_role.rds_monitoring[0].arn : null

  backup_retention_period = 0    # Read replicas don't need backups
  skip_final_snapshot     = true

  tags = { Name = "${var.identifier}-replica" }
}

# ─────────────────────────────────────────────────────────────
# ENHANCED MONITORING ROLE
# ─────────────────────────────────────────────────────────────
resource "aws_iam_role" "rds_monitoring" {
  count = var.monitoring_interval > 0 ? 1 : 0
  name  = "${var.identifier}-monitoring-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "monitoring.rds.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "rds_monitoring" {
  count      = var.monitoring_interval > 0 ? 1 : 0
  role       = aws_iam_role.rds_monitoring[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

# ─────────────────────────────────────────────────────────────
# CLOUDWATCH ALARMS
# ─────────────────────────────────────────────────────────────
resource "aws_cloudwatch_metric_alarm" "cpu" {
  alarm_name          = "${var.identifier}-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = 60
  statistic           = "Average"
  threshold           = 80
  alarm_description   = "RDS CPU above 80%"

  dimensions = { DBInstanceIdentifier = aws_db_instance.main.identifier }
}

resource "aws_cloudwatch_metric_alarm" "storage_low" {
  alarm_name          = "${var.identifier}-storage-low"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 1
  metric_name         = "FreeStorageSpace"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = 5368709120    # 5 GB
  alarm_description   = "RDS free storage below 5GB"

  dimensions = { DBInstanceIdentifier = aws_db_instance.main.identifier }
}

resource "aws_cloudwatch_metric_alarm" "connections" {
  alarm_name          = "${var.identifier}-connections-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "DatabaseConnections"
  namespace           = "AWS/RDS"
  period              = 60
  statistic           = "Average"
  threshold           = 150
  alarm_description   = "RDS connections above 150"

  dimensions = { DBInstanceIdentifier = aws_db_instance.main.identifier }
}

data "aws_region" "current" {}

# ─────────────────────────────────────────────────────────────
# OUTPUTS
# ─────────────────────────────────────────────────────────────
output "endpoint"        { value = aws_db_instance.main.address }
output "port"            { value = aws_db_instance.main.port }
output "database_name"   { value = aws_db_instance.main.db_name }
output "resource_id"     { value = aws_db_instance.main.resource_id }
output "arn"             { value = aws_db_instance.main.arn }
output "replica_endpoint"{ value = var.create_read_replica ? aws_db_instance.replica[0].address : null }
