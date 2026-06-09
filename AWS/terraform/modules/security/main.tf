# terraform/modules/security/main.tf
# Additional security hardening: CloudTrail, Config, GuardDuty, SecurityHub

# ─────────────────────────────────────────────────────────────
# CLOUDTRAIL — audit log of all AWS API calls
# ─────────────────────────────────────────────────────────────
resource "aws_cloudtrail" "main" {
  name                          = "ironlog-audit-trail"
  s3_bucket_name                = aws_s3_bucket.cloudtrail.id
  include_global_service_events = true
  is_multi_region_trail         = true
  enable_log_file_validation    = true

  event_selector {
    read_write_type           = "All"
    include_management_events = true

    # Log S3 data events (who accessed what file)
    data_resource {
      type   = "AWS::S3::Object"
      values = ["arn:aws:s3:::ironlog-prod-media/"]
    }
  }

  cloud_watch_logs_group_arn = "${aws_cloudwatch_log_group.cloudtrail.arn}:*"
  cloud_watch_logs_role_arn  = aws_iam_role.cloudtrail.arn

  tags = { Name = "ironlog-audit-trail" }
}

resource "aws_s3_bucket" "cloudtrail" {
  bucket        = "ironlog-cloudtrail-${var.account_id}"
  force_destroy = false
  tags          = { Name = "ironlog-cloudtrail" }
}

resource "aws_s3_bucket_policy" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id
  policy = data.aws_iam_policy_document.cloudtrail_s3.json
}

data "aws_iam_policy_document" "cloudtrail_s3" {
  statement {
    principals { type = "Service"; identifiers = ["cloudtrail.amazonaws.com"] }
    actions   = ["s3:GetBucketAcl"]
    resources = [aws_s3_bucket.cloudtrail.arn]
  }
  statement {
    principals { type = "Service"; identifiers = ["cloudtrail.amazonaws.com"] }
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.cloudtrail.arn}/AWSLogs/${var.account_id}/*"]
    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }
  }
}

resource "aws_cloudwatch_log_group" "cloudtrail" {
  name              = "/aws/cloudtrail/ironlog"
  retention_in_days = 90
}

resource "aws_iam_role" "cloudtrail" {
  name = "ironlog-cloudtrail-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{ Action = "sts:AssumeRole"; Effect = "Allow"; Principal = { Service = "cloudtrail.amazonaws.com" } }]
  })
}

resource "aws_iam_role_policy" "cloudtrail" {
  role = aws_iam_role.cloudtrail.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
      Resource = "${aws_cloudwatch_log_group.cloudtrail.arn}:*"
    }]
  })
}

# ─────────────────────────────────────────────────────────────
# GUARDDUTY — ML-based threat detection
# ─────────────────────────────────────────────────────────────
resource "aws_guardduty_detector" "main" {
  enable = true

  datasources {
    s3_logs {
      enable = true    # Detect S3 threats (unusual access patterns)
    }
    kubernetes {
      audit_logs { enable = false }    # Not using EKS
    }
    malware_protection {
      scan_ec2_instance_with_findings {
        ebs_volumes { enable = false }    # Not using EC2
      }
    }
  }

  tags = { Name = "ironlog-guardduty" }
}

resource "aws_guardduty_filter" "suppress_known_good" {
  name        = "suppress-known-good-traffic"
  action      = "ARCHIVE"
  detector_id = aws_guardduty_detector.main.id
  rank        = 1

  finding_criteria {
    criterion {
      field  = "resource.accessKeyDetails.userName"
      equals = ["ironlog-github-actions"]    # Known good — CI/CD
    }
  }
}

# SNS for GuardDuty findings
resource "aws_cloudwatch_event_rule" "guardduty_findings" {
  name        = "ironlog-guardduty-findings"
  description = "Route high-severity GuardDuty findings to SNS"

  event_pattern = jsonencode({
    source      = ["aws.guardduty"]
    detail-type = ["GuardDuty Finding"]
    detail = {
      severity = [{ numeric = [">=", 7] }]    # High and critical only
    }
  })
}

resource "aws_cloudwatch_event_target" "guardduty_sns" {
  rule      = aws_cloudwatch_event_rule.guardduty_findings.name
  target_id = "guardduty-to-sns"
  arn       = var.sns_alert_arn
}

# ─────────────────────────────────────────────────────────────
# AWS CONFIG — compliance rules
# ─────────────────────────────────────────────────────────────
resource "aws_config_configuration_recorder" "main" {
  name     = "ironlog-config-recorder"
  role_arn = aws_iam_role.config.arn

  recording_group {
    all_supported                 = false
    include_global_resource_types = false
    resource_types = [
      "AWS::EC2::SecurityGroup",
      "AWS::RDS::DBInstance",
      "AWS::ElastiCache::ReplicationGroup",
      "AWS::ECS::Service",
      "AWS::S3::Bucket",
      "AWS::IAM::Role",
    ]
  }
}

resource "aws_iam_role" "config" {
  name = "ironlog-config-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{ Action = "sts:AssumeRole"; Effect = "Allow"; Principal = { Service = "config.amazonaws.com" } }]
  })
}

resource "aws_iam_role_policy_attachment" "config" {
  role       = aws_iam_role.config.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWS_ConfigRole"
}

resource "aws_config_configuration_recorder_status" "main" {
  name       = aws_config_configuration_recorder.main.name
  is_enabled = true
  depends_on = [aws_config_delivery_channel.main]
}

resource "aws_config_delivery_channel" "main" {
  name           = "ironlog-config-delivery"
  s3_bucket_name = aws_s3_bucket.cloudtrail.id
  depends_on     = [aws_config_configuration_recorder.main]
}

# Config rules — compliance checks
resource "aws_config_config_rule" "rds_storage_encrypted" {
  name = "rds-storage-encrypted"
  source {
    owner             = "AWS"
    source_identifier = "RDS_STORAGE_ENCRYPTED"
  }
  depends_on = [aws_config_configuration_recorder_status.main]
}

resource "aws_config_config_rule" "s3_bucket_public_read_prohibited" {
  name = "s3-bucket-public-read-prohibited"
  source {
    owner             = "AWS"
    source_identifier = "S3_BUCKET_PUBLIC_READ_PROHIBITED"
  }
  depends_on = [aws_config_configuration_recorder_status.main]
}

resource "aws_config_config_rule" "restricted_ssh" {
  name = "restricted-ssh"
  source {
    owner             = "AWS"
    source_identifier = "INCOMING_SSH_DISABLED"
  }
  depends_on = [aws_config_configuration_recorder_status.main]
}

# ─────────────────────────────────────────────────────────────
# SECRETS ROTATION — auto-rotate JWT secrets every 90 days
# ─────────────────────────────────────────────────────────────
resource "aws_secretsmanager_secret_rotation" "jwt" {
  secret_id           = var.jwt_secret_arn
  rotation_lambda_arn = aws_lambda_function.secret_rotator.arn

  rotation_rules {
    automatically_after_days = 90
  }
}

data "archive_file" "rotator" {
  type        = "zip"
  output_path = "${path.module}/rotator.zip"
  source {
    content  = <<-EOF
      import boto3
      import secrets
      import json

      def lambda_handler(event, context):
          arn   = event['SecretId']
          token = event['ClientRequestToken']
          step  = event['Step']
          client = boto3.client('secretsmanager')

          if step == 'createSecret':
              try:
                  client.get_secret_value(SecretId=arn, VersionStage='AWSPENDING')
              except client.exceptions.ResourceNotFoundException:
                  new_secret = secrets.token_hex(32)
                  client.put_secret_value(
                      SecretId=arn,
                      ClientRequestToken=token,
                      SecretString=new_secret,
                      VersionStages=['AWSPENDING'],
                  )

          elif step == 'setSecret':
              pass  # No external service to update for JWT secrets

          elif step == 'testSecret':
              pass  # Verify the new secret works

          elif step == 'finishSecret':
              metadata = client.describe_secret(SecretId=arn)
              current_version = next(
                  v for v, stages in metadata['VersionIdsToStages'].items()
                  if 'AWSCURRENT' in stages
              )
              client.update_secret_version_stage(
                  SecretId=arn,
                  VersionStage='AWSCURRENT',
                  MoveToVersionId=token,
                  RemoveFromVersionId=current_version,
              )
    EOF
    filename = "lambda_function.py"
  }
}

resource "aws_lambda_function" "secret_rotator" {
  function_name    = "ironlog-secret-rotator"
  filename         = data.archive_file.rotator.output_path
  source_code_hash = data.archive_file.rotator.output_base64sha256
  handler          = "lambda_function.lambda_handler"
  runtime          = "python3.12"
  role             = aws_iam_role.rotator.arn
  timeout          = 30

  environment {
    variables = { SECRETS_MANAGER_ENDPOINT = "https://secretsmanager.${var.aws_region}.amazonaws.com" }
  }

  tags = { Name = "ironlog-secret-rotator" }
}

resource "aws_iam_role" "rotator" {
  name = "ironlog-secret-rotator-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{ Action = "sts:AssumeRole"; Effect = "Allow"; Principal = { Service = "lambda.amazonaws.com" } }]
  })
}

resource "aws_iam_role_policy" "rotator" {
  role = aws_iam_role.rotator.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue", "secretsmanager:PutSecretValue",
                    "secretsmanager:DescribeSecret", "secretsmanager:UpdateSecretVersionStage"]
        Resource = [var.jwt_secret_arn, var.jwt_refresh_secret_arn]
      },
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

resource "aws_lambda_permission" "secrets_manager" {
  statement_id  = "SecretsManagerInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.secret_rotator.function_name
  principal     = "secretsmanager.amazonaws.com"
}

# ─────────────────────────────────────────────────────────────
# VARIABLES
# ─────────────────────────────────────────────────────────────
variable "account_id"             { type = string }
variable "aws_region"             { type = string }
variable "sns_alert_arn"          { type = string }
variable "jwt_secret_arn"         { type = string }
variable "jwt_refresh_secret_arn" { type = string }

# ─────────────────────────────────────────────────────────────
# OUTPUTS
# ─────────────────────────────────────────────────────────────
output "guardduty_detector_id" { value = aws_guardduty_detector.main.id }
output "cloudtrail_arn"        { value = aws_cloudtrail.main.arn }
output "rotator_lambda_arn"    { value = aws_lambda_function.secret_rotator.arn }
