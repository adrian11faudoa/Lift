# terraform/modules/monitoring/main.tf
# CloudWatch dashboards, composite alarms, SNS alerts, and X-Ray

# ─────────────────────────────────────────────────────────────
# SNS TOPIC — alert destination
# ─────────────────────────────────────────────────────────────
resource "aws_sns_topic" "alerts" {
  name              = "ironlog-prod-alerts"
  kms_master_key_id = "alias/aws/sns"
  tags              = { Name = "ironlog-prod-alerts" }
}

resource "aws_sns_topic_subscription" "email" {
  count     = var.alert_email != null ? 1 : 0
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

resource "aws_sns_topic_subscription" "slack" {
  count     = var.slack_webhook_url != null ? 1 : 0
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "https"
  endpoint  = var.slack_webhook_url
}

# ─────────────────────────────────────────────────────────────
# CLOUDWATCH DASHBOARD
# ─────────────────────────────────────────────────────────────
resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = "IronLog-Production"

  dashboard_body = jsonencode({
    widgets = [
      # ── Row 1: API Health ─────────────────────────────────
      {
        type   = "text"
        x = 0; y = 0; width = 24; height = 1
        properties = { markdown = "## 🏋️ IronLog Production — API Health" }
      },
      {
        type = "metric"
        x = 0; y = 1; width = 6; height = 6
        properties = {
          title  = "API Request Rate"
          view   = "timeSeries"
          stacked = false
          metrics = [[
            "AWS/ApplicationELB", "RequestCount",
            "LoadBalancer", var.alb_arn_suffix,
            { stat = "Sum", period = 60, color = "#2563EB" }
          ]]
          period = 60
          yAxis  = { left = { min = 0 } }
        }
      },
      {
        type = "metric"
        x = 6; y = 1; width = 6; height = 6
        properties = {
          title  = "API Latency (p50/p95/p99)"
          view   = "timeSeries"
          metrics = [
            ["AWS/ApplicationELB", "TargetResponseTime", "LoadBalancer", var.alb_arn_suffix,
              { stat = "p50", label = "p50", color = "#16A34A" }],
            ["...", { stat = "p95", label = "p95", color = "#EA580C" }],
            ["...", { stat = "p99", label = "p99", color = "#DC2626" }],
          ]
          period = 60
        }
      },
      {
        type = "metric"
        x = 12; y = 1; width = 6; height = 6
        properties = {
          title  = "HTTP Error Rates"
          view   = "timeSeries"
          metrics = [
            ["AWS/ApplicationELB", "HTTPCode_Target_4XX_Count",
              "LoadBalancer", var.alb_arn_suffix,
              { stat = "Sum", label = "4xx", color = "#EA580C" }],
            ["AWS/ApplicationELB", "HTTPCode_Target_5XX_Count",
              "LoadBalancer", var.alb_arn_suffix,
              { stat = "Sum", label = "5xx", color = "#DC2626" }],
          ]
          period = 60
        }
      },
      {
        type = "metric"
        x = 18; y = 1; width = 6; height = 6
        properties = {
          title  = "Healthy Targets"
          view   = "singleValue"
          metrics = [[
            "AWS/ApplicationELB", "HealthyHostCount",
            "LoadBalancer", var.alb_arn_suffix,
            "TargetGroup", var.target_group_arn_suffix,
            { stat = "Average", color = "#16A34A" }
          ]]
        }
      },
      # ── Row 2: ECS ───────────────────────────────────────
      {
        type   = "text"
        x = 0; y = 7; width = 24; height = 1
        properties = { markdown = "## 🐳 ECS Fargate" }
      },
      {
        type = "metric"
        x = 0; y = 8; width = 8; height = 6
        properties = {
          title  = "ECS CPU Utilization"
          view   = "timeSeries"
          metrics = [[
            "AWS/ECS", "CPUUtilization",
            "ClusterName", var.ecs_cluster_name,
            "ServiceName", var.ecs_service_name,
            { stat = "Average", color = "#2563EB" }
          ]]
          period     = 60
          annotations = { horizontal = [{ value = 80, color = "#DC2626", label = "Scale threshold" }] }
        }
      },
      {
        type = "metric"
        x = 8; y = 8; width = 8; height = 6
        properties = {
          title  = "ECS Memory Utilization"
          view   = "timeSeries"
          metrics = [[
            "AWS/ECS", "MemoryUtilization",
            "ClusterName", var.ecs_cluster_name,
            "ServiceName", var.ecs_service_name,
            { stat = "Average", color = "#7C3AED" }
          ]]
          period = 60
        }
      },
      {
        type = "metric"
        x = 16; y = 8; width = 8; height = 6
        properties = {
          title  = "Running Task Count"
          view   = "timeSeries"
          metrics = [[
            "ECS/ContainerInsights", "RunningTaskCount",
            "ClusterName", var.ecs_cluster_name,
            "ServiceName", var.ecs_service_name,
            { stat = "Average", color = "#16A34A" }
          ]]
          period = 60
        }
      },
      # ── Row 3: Database ──────────────────────────────────
      {
        type   = "text"
        x = 0; y = 14; width = 24; height = 1
        properties = { markdown = "## 🗄️ RDS PostgreSQL" }
      },
      {
        type = "metric"
        x = 0; y = 15; width = 8; height = 6
        properties = {
          title  = "DB CPU & Connections"
          view   = "timeSeries"
          metrics = [
            ["AWS/RDS", "CPUUtilization", "DBInstanceIdentifier", var.rds_identifier,
              { stat = "Average", label = "CPU%", yAxis = "left", color = "#2563EB" }],
            ["AWS/RDS", "DatabaseConnections", "DBInstanceIdentifier", var.rds_identifier,
              { stat = "Average", label = "Connections", yAxis = "right", color = "#EA580C" }],
          ]
          period = 60
        }
      },
      {
        type = "metric"
        x = 8; y = 15; width = 8; height = 6
        properties = {
          title  = "DB Read/Write IOPS"
          view   = "timeSeries"
          metrics = [
            ["AWS/RDS", "ReadIOPS",  "DBInstanceIdentifier", var.rds_identifier,
              { stat = "Average", label = "Read IOPS",  color = "#16A34A" }],
            ["AWS/RDS", "WriteIOPS", "DBInstanceIdentifier", var.rds_identifier,
              { stat = "Average", label = "Write IOPS", color = "#EA580C" }],
          ]
          period = 60
        }
      },
      {
        type = "metric"
        x = 16; y = 15; width = 8; height = 6
        properties = {
          title  = "DB Free Storage Space"
          view   = "timeSeries"
          metrics = [[
            "AWS/RDS", "FreeStorageSpace",
            "DBInstanceIdentifier", var.rds_identifier,
            { stat = "Average", color = "#16A34A" }
          ]]
          period = 300
          yAxis  = { left = { label = "Bytes" } }
        }
      },
      # ── Row 4: Redis ─────────────────────────────────────
      {
        type   = "text"
        x = 0; y = 21; width = 24; height = 1
        properties = { markdown = "## ⚡ ElastiCache Redis" }
      },
      {
        type = "metric"
        x = 0; y = 22; width = 8; height = 6
        properties = {
          title  = "Redis CPU & Memory"
          view   = "timeSeries"
          metrics = [
            ["AWS/ElastiCache", "CPUUtilization",
              "ReplicationGroupId", var.redis_replication_group_id,
              { stat = "Average", label = "CPU%", color = "#2563EB" }],
            ["AWS/ElastiCache", "DatabaseMemoryUsagePercentage",
              "ReplicationGroupId", var.redis_replication_group_id,
              { stat = "Average", label = "Memory%", color = "#7C3AED" }],
          ]
          period = 60
        }
      },
      {
        type = "metric"
        x = 8; y = 22; width = 8; height = 6
        properties = {
          title  = "Redis Hit Rate"
          view   = "timeSeries"
          metrics = [
            ["AWS/ElastiCache", "CacheHits",
              "ReplicationGroupId", var.redis_replication_group_id,
              { stat = "Sum", label = "Hits",   color = "#16A34A" }],
            ["AWS/ElastiCache", "CacheMisses",
              "ReplicationGroupId", var.redis_replication_group_id,
              { stat = "Sum", label = "Misses", color = "#DC2626" }],
          ]
          period = 60
        }
      },
      # ── Row 5: Business Metrics (Custom) ─────────────────
      {
        type   = "text"
        x = 0; y = 28; width = 24; height = 1
        properties = { markdown = "## 📊 Business Metrics" }
      },
      {
        type = "metric"
        x = 0; y = 29; width = 8; height = 6
        properties = {
          title  = "Active Workouts (real-time)"
          view   = "singleValue"
          metrics = [[
            "IronLog/API", "ActiveWorkouts",
            { stat = "Sum", period = 300, color = "#2563EB" }
          ]]
        }
      },
      {
        type = "metric"
        x = 8; y = 29; width = 8; height = 6
        properties = {
          title  = "Workouts Logged Today"
          view   = "singleValue"
          metrics = [[
            "IronLog/API", "WorkoutsCompleted",
            { stat = "Sum", period = 86400, color = "#16A34A" }
          ]]
        }
      },
      {
        type = "metric"
        x = 16; y = 29; width = 8; height = 6
        properties = {
          title  = "New PRs Today"
          view   = "singleValue"
          metrics = [[
            "IronLog/API", "PersonalRecords",
            { stat = "Sum", period = 86400, color = "#FFD700" }
          ]]
        }
      },
    ]
  })
}

# ─────────────────────────────────────────────────────────────
# COMPOSITE ALARM — "IronLog is DOWN"
# ─────────────────────────────────────────────────────────────
resource "aws_cloudwatch_composite_alarm" "service_down" {
  alarm_name        = "ironlog-service-down"
  alarm_description = "IronLog API is unreachable or critically degraded"

  alarm_rule = join(" OR ", [
    "ALARM(${var.alb_unhealthy_alarm_arn})",
    "ALARM(${var.ecs_task_low_alarm_arn})",
    "ALARM(${var.alb_5xx_alarm_arn})",
  ])

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]
}

# ─────────────────────────────────────────────────────────────
# CUSTOM METRIC FILTER — app-level events from CloudWatch Logs
# ─────────────────────────────────────────────────────────────
resource "aws_cloudwatch_log_metric_filter" "active_workouts" {
  name           = "ActiveWorkoutsStarted"
  log_group_name = var.ecs_log_group_name
  pattern        = "{ $.type = \"workout_started\" }"

  metric_transformation {
    name          = "ActiveWorkouts"
    namespace     = "IronLog/API"
    value         = "1"
    default_value = "0"
  }
}

resource "aws_cloudwatch_log_metric_filter" "workouts_completed" {
  name           = "WorkoutsCompleted"
  log_group_name = var.ecs_log_group_name
  pattern        = "{ $.type = \"workout_completed\" }"

  metric_transformation {
    name          = "WorkoutsCompleted"
    namespace     = "IronLog/API"
    value         = "1"
    default_value = "0"
  }
}

resource "aws_cloudwatch_log_metric_filter" "personal_records" {
  name           = "PersonalRecords"
  log_group_name = var.ecs_log_group_name
  pattern        = "{ $.type = \"personal_record\" }"

  metric_transformation {
    name          = "PersonalRecords"
    namespace     = "IronLog/API"
    value         = "1"
    default_value = "0"
  }
}

resource "aws_cloudwatch_log_metric_filter" "api_errors" {
  name           = "APIErrors"
  log_group_name = var.ecs_log_group_name
  pattern        = "{ $.type = \"error\" && $.status >= 500 }"

  metric_transformation {
    name          = "APIErrors"
    namespace     = "IronLog/API"
    value         = "1"
    default_value = "0"
  }
}

# ─────────────────────────────────────────────────────────────
# ALARM: API error rate too high
# ─────────────────────────────────────────────────────────────
resource "aws_cloudwatch_metric_alarm" "api_error_rate" {
  alarm_name          = "ironlog-api-error-rate-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  threshold           = 50
  alarm_description   = "More than 50 API errors in 3 minutes"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]

  metric_query {
    id = "errors"
    metric {
      metric_name = "APIErrors"
      namespace   = "IronLog/API"
      period      = 60
      stat        = "Sum"
    }
  }
}

# ─────────────────────────────────────────────────────────────
# OUTPUTS
# ─────────────────────────────────────────────────────────────
output "sns_alert_topic_arn"  { value = aws_sns_topic.alerts.arn }
output "dashboard_name"       { value = aws_cloudwatch_dashboard.main.dashboard_name }
output "dashboard_url" {
  value = "https://console.aws.amazon.com/cloudwatch/home#dashboards:name=${aws_cloudwatch_dashboard.main.dashboard_name}"
}
