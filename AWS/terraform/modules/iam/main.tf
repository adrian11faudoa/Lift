# terraform/modules/iam/main.tf
# IAM roles for ECS execution and task with least-privilege permissions

# ─────────────────────────────────────────────────────────────
# ECS EXECUTION ROLE
# Used by ECS agent to pull images and inject secrets
# ─────────────────────────────────────────────────────────────
resource "aws_iam_role" "ecs_execution" {
  name        = "${var.name_prefix}-ecs-execution-role"
  description = "ECS task execution role — pull images, inject secrets"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
    }]
  })

  tags = { Name = "${var.name_prefix}-ecs-execution-role" }
}

# AWS managed policy — ECR pull + CloudWatch logs
resource "aws_iam_role_policy_attachment" "ecs_execution_managed" {
  role       = aws_iam_role.ecs_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Custom policy — read specific Secrets Manager secrets
resource "aws_iam_role_policy" "ecs_execution_secrets" {
  name = "secrets-access"
  role = aws_iam_role.ecs_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ReadSecrets"
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret",
        ]
        Resource = var.secret_arns
      },
      {
        Sid    = "DecryptSecrets"
        Effect = "Allow"
        Action = ["kms:Decrypt"]
        Resource = ["arn:aws:kms:${var.aws_region}:${var.account_id}:key/*"]
        Condition = {
          StringEquals = {
            "kms:ViaService" = "secretsmanager.${var.aws_region}.amazonaws.com"
          }
        }
      },
      {
        Sid    = "CloudWatchLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents",
        ]
        Resource = "arn:aws:logs:${var.aws_region}:${var.account_id}:log-group:/ecs/*"
      },
    ]
  })
}

# ─────────────────────────────────────────────────────────────
# ECS TASK ROLE
# Used by the running application container
# ─────────────────────────────────────────────────────────────
resource "aws_iam_role" "ecs_task" {
  name        = "${var.name_prefix}-ecs-task-role"
  description = "ECS task role — permissions for the running app"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
    }]
  })

  tags = { Name = "${var.name_prefix}-ecs-task-role" }
}

# S3 — media upload/download and backups
resource "aws_iam_role_policy" "task_s3" {
  name = "s3-access"
  role = aws_iam_role.ecs_task.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "MediaBucketAccess"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:GetObjectAcl",
          "s3:PutObjectAcl",
        ]
        Resource = "${var.media_bucket_arn}/*"
      },
      {
        Sid    = "MediaBucketList"
        Effect = "Allow"
        Action = ["s3:ListBucket", "s3:GetBucketLocation"]
        Resource = var.media_bucket_arn
      },
      {
        Sid    = "BackupsBucketWrite"
        Effect = "Allow"
        Action = ["s3:PutObject", "s3:GetObject"]
        Resource = "${var.backups_bucket_arn}/*"
      },
    ]
  })
}

# CloudWatch — metrics and logs
resource "aws_iam_role_policy" "task_cloudwatch" {
  name = "cloudwatch-access"
  role = aws_iam_role.ecs_task.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "PutMetrics"
        Effect = "Allow"
        Action = [
          "cloudwatch:PutMetricData",
          "cloudwatch:GetMetricStatistics",
          "cloudwatch:ListMetrics",
        ]
        Resource = "*"
        Condition = {
          StringEquals = { "cloudwatch:namespace" = "IronLog/API" }
        }
      },
      {
        Sid    = "WriteLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogStreams",
        ]
        Resource = "arn:aws:logs:${var.aws_region}:${var.account_id}:log-group:/ecs/*:*"
      },
    ]
  })
}

# Secrets — runtime access (for dynamic secret fetching)
resource "aws_iam_role_policy" "task_secrets" {
  name = "secrets-runtime-access"
  role = aws_iam_role.ecs_task.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ReadSecrets"
        Effect = "Allow"
        Action = ["secretsmanager:GetSecretValue"]
        Resource = var.secret_arns
      },
    ]
  })
}

# RDS — IAM authentication (alternative to password auth)
resource "aws_iam_role_policy" "task_rds" {
  name = "rds-iam-auth"
  role = aws_iam_role.ecs_task.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "RDSConnect"
        Effect = "Allow"
        Action = ["rds-db:connect"]
        Resource = "arn:aws:rds-db:${var.aws_region}:${var.account_id}:dbuser:${var.rds_resource_id}/${var.db_username}"
      },
    ]
  })
}

# SES — email sending (for auth emails, receipts)
resource "aws_iam_role_policy" "task_ses" {
  name = "ses-send-email"
  role = aws_iam_role.ecs_task.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "SendEmail"
        Effect = "Allow"
        Action = [
          "ses:SendEmail",
          "ses:SendRawEmail",
          "ses:SendTemplatedEmail",
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "ses:FromAddress" = "noreply@ironlog.app"
          }
        }
      },
    ]
  })
}

# ─────────────────────────────────────────────────────────────
# GITHUB ACTIONS DEPLOYMENT ROLE (OIDC — no long-lived keys)
# ─────────────────────────────────────────────────────────────
resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]

  tags = { Name = "github-actions-oidc" }
}

resource "aws_iam_role" "github_actions" {
  name        = "${var.name_prefix}-github-actions-role"
  description = "GitHub Actions deployment role (OIDC — no static credentials)"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRoleWithWebIdentity"
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.github.arn
        }
        Condition = {
          StringLike = {
            "token.actions.githubusercontent.com:sub" = "repo:${var.github_org}/${var.github_repo}:*"
          }
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          }
        }
      },
    ]
  })

  tags = { Name = "${var.name_prefix}-github-actions-role" }
}

resource "aws_iam_role_policy" "github_actions_deploy" {
  name = "deployment-permissions"
  role = aws_iam_role.github_actions.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # ECR — push images
      {
        Sid    = "ECRAuth"
        Effect = "Allow"
        Action = ["ecr:GetAuthorizationToken"]
        Resource = "*"
      },
      {
        Sid    = "ECRPush"
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
          "ecr:PutImage",
        ]
        Resource = "arn:aws:ecr:${var.aws_region}:${var.account_id}:repository/ironlog-api"
      },
      # ECS — deploy new task definition
      {
        Sid    = "ECSDeployment"
        Effect = "Allow"
        Action = [
          "ecs:RegisterTaskDefinition",
          "ecs:UpdateService",
          "ecs:DescribeServices",
          "ecs:DescribeTaskDefinition",
          "ecs:ListTaskDefinitions",
          "ecs:DescribeTasks",
          "ecs:ListTasks",
        ]
        Resource = "*"
      },
      # IAM — pass roles to ECS tasks
      {
        Sid    = "PassRole"
        Effect = "Allow"
        Action = ["iam:PassRole"]
        Resource = [
          aws_iam_role.ecs_execution.arn,
          aws_iam_role.ecs_task.arn,
        ]
      },
      # S3 — deploy Flutter web build
      {
        Sid    = "S3Deploy"
        Effect = "Allow"
        Action = ["s3:PutObject", "s3:DeleteObject", "s3:ListBucket"]
        Resource = [
          "arn:aws:s3:::ironlog-prod-assets",
          "arn:aws:s3:::ironlog-prod-assets/*",
        ]
      },
      # CloudFront — invalidate cache after deploy
      {
        Sid    = "CloudFrontInvalidate"
        Effect = "Allow"
        Action = ["cloudfront:CreateInvalidation"]
        Resource = "*"
      },
    ]
  })
}

# ─────────────────────────────────────────────────────────────
# OUTPUTS
# ─────────────────────────────────────────────────────────────
output "ecs_execution_role_arn"   { value = aws_iam_role.ecs_execution.arn }
output "ecs_task_role_arn"        { value = aws_iam_role.ecs_task.arn }
output "github_actions_role_arn"  { value = aws_iam_role.github_actions.arn }
output "github_oidc_provider_arn" { value = aws_iam_openid_connect_provider.github.arn }
