# terraform/environments/production/variables.tf

variable "aws_region" {
  description = "AWS region for primary resources"
  type        = string
  default     = "us-east-1"
}

variable "db_username" {
  description = "RDS master username"
  type        = string
  default     = "ironlog"
}

variable "acm_certificate_arn" {
  description = "ACM certificate ARN in the deployment region (for ALB)"
  type        = string
}

variable "acm_certificate_arn_us_east_1" {
  description = "ACM certificate ARN in us-east-1 (required by CloudFront)"
  type        = string
}

variable "api_domain_name" {
  description = "Domain for the API (e.g. api.ironlog.app)"
  type        = string
  default     = "api.ironlog.app"
}

variable "app_domain_name" {
  description = "Domain for the Flutter web app (e.g. app.ironlog.app)"
  type        = string
  default     = "app.ironlog.app"
}

variable "image_tag" {
  description = "Docker image tag to deploy"
  type        = string
  default     = "latest"
}

variable "team_email" {
  description = "Team email for resource tagging"
  type        = string
  default     = "infra@ironlog.app"
}
