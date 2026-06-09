# terraform/modules/secrets/main.tf
# AWS Secrets Manager: DB credentials, JWT secrets, Redis auth token, OAuth keys

resource "random_password" "db_password" {
  length           = 32
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "random_password" "jwt_secret" {
  length  = 64
  special = false
}

resource "random_password" "jwt_refresh_secret" {
  length  = 64
  special = false
}

resource "random_password" "redis_auth_token" {
  length  = 32
  special = false
}

# ─── DB Credentials (username + password in one secret) ───────
resource "aws_secretsmanager_secret" "db_credentials" {
  name                    = "${var.name_prefix}/db/credentials"
  description             = "IronLog RDS PostgreSQL credentials"
  recovery_window_in_days = var.recovery_window

  tags = { Name = "${var.name_prefix}-db-credentials" }
}

resource "aws_secretsmanager_secret_version" "db_credentials" {
  secret_id = aws_secretsmanager_secret.db_credentials.id
  secret_string = jsonencode({
    username = var.db_username
    password = random_password.db_password.result
    engine   = "postgres"
    port     = 5432
  })
}

# ─── JWT Access Token Secret ──────────────────────────────────
resource "aws_secretsmanager_secret" "jwt_secret" {
  name                    = "${var.name_prefix}/auth/jwt-secret"
  description             = "JWT access token signing secret"
  recovery_window_in_days = var.recovery_window
}

resource "aws_secretsmanager_secret_version" "jwt_secret" {
  secret_id     = aws_secretsmanager_secret.jwt_secret.id
  secret_string = random_password.jwt_secret.result
}

# ─── JWT Refresh Token Secret ─────────────────────────────────
resource "aws_secretsmanager_secret" "jwt_refresh_secret" {
  name                    = "${var.name_prefix}/auth/jwt-refresh-secret"
  description             = "JWT refresh token signing secret"
  recovery_window_in_days = var.recovery_window
}

resource "aws_secretsmanager_secret_version" "jwt_refresh_secret" {
  secret_id     = aws_secretsmanager_secret.jwt_refresh_secret.id
  secret_string = random_password.jwt_refresh_secret.result
}

# ─── Redis Auth Token ─────────────────────────────────────────
resource "aws_secretsmanager_secret" "redis_auth_token" {
  name                    = "${var.name_prefix}/redis/auth-token"
  description             = "ElastiCache Redis AUTH token"
  recovery_window_in_days = var.recovery_window
}

resource "aws_secretsmanager_secret_version" "redis_auth_token" {
  secret_id     = aws_secretsmanager_secret.redis_auth_token.id
  secret_string = random_password.redis_auth_token.result
}

# ─── Google OAuth Client ID (set manually after Terraform) ────
resource "aws_secretsmanager_secret" "google_client_id" {
  name                    = "${var.name_prefix}/oauth/google-client-id"
  description             = "Google OAuth 2.0 Client ID"
  recovery_window_in_days = var.recovery_window
}

resource "aws_secretsmanager_secret_version" "google_client_id" {
  secret_id     = aws_secretsmanager_secret.google_client_id.id
  secret_string = "PLACEHOLDER_SET_MANUALLY"    # Update via console or CI/CD
}

# ─── Apple Bundle ID ──────────────────────────────────────────
resource "aws_secretsmanager_secret" "apple_client_id" {
  name                    = "${var.name_prefix}/oauth/apple-client-id"
  description             = "Apple Sign In Bundle ID"
  recovery_window_in_days = var.recovery_window
}

resource "aws_secretsmanager_secret_version" "apple_client_id" {
  secret_id     = aws_secretsmanager_secret.apple_client_id.id
  secret_string = "PLACEHOLDER_SET_MANUALLY"
}

# ─── RevenueCat API Keys ──────────────────────────────────────
resource "aws_secretsmanager_secret" "revenuecat_keys" {
  name                    = "${var.name_prefix}/revenuecat/api-keys"
  description             = "RevenueCat Android and iOS API keys"
  recovery_window_in_days = var.recovery_window
}

resource "aws_secretsmanager_secret_version" "revenuecat_keys" {
  secret_id = aws_secretsmanager_secret.revenuecat_keys.id
  secret_string = jsonencode({
    android = "PLACEHOLDER_SET_MANUALLY"
    ios     = "PLACEHOLDER_SET_MANUALLY"
  })
}

# ─────────────────────────────────────────────────────────────
# OUTPUTS
# ─────────────────────────────────────────────────────────────
output "db_credentials_arn"    { value = aws_secretsmanager_secret.db_credentials.arn }
output "db_password_arn"       { value = aws_secretsmanager_secret.db_credentials.arn }
output "jwt_secret_arn"        { value = aws_secretsmanager_secret.jwt_secret.arn }
output "jwt_refresh_secret_arn"{ value = aws_secretsmanager_secret.jwt_refresh_secret.arn }
output "redis_auth_token_arn"  { value = aws_secretsmanager_secret.redis_auth_token.arn }
output "google_client_id_arn"  { value = aws_secretsmanager_secret.google_client_id.arn }
output "apple_client_id_arn"   { value = aws_secretsmanager_secret.apple_client_id.arn }
output "revenuecat_keys_arn"   { value = aws_secretsmanager_secret.revenuecat_keys.arn }

output "all_secret_arns" {
  value = [
    aws_secretsmanager_secret.db_credentials.arn,
    aws_secretsmanager_secret.jwt_secret.arn,
    aws_secretsmanager_secret.jwt_refresh_secret.arn,
    aws_secretsmanager_secret.redis_auth_token.arn,
    aws_secretsmanager_secret.google_client_id.arn,
    aws_secretsmanager_secret.apple_client_id.arn,
    aws_secretsmanager_secret.revenuecat_keys.arn,
  ]
}
