# terraform/modules/s3/main.tf
# S3 buckets: media storage, backups, Flutter web assets

# ─────────────────────────────────────────────────────────────
# MEDIA BUCKET — user-uploaded content (exercise videos, avatars)
# ─────────────────────────────────────────────────────────────
resource "aws_s3_bucket" "media" {
  bucket = var.media_bucket_name
  tags   = { Name = var.media_bucket_name, Type = "media" }
}

resource "aws_s3_bucket_versioning" "media" {
  bucket = aws_s3_bucket.media.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "media" {
  bucket = aws_s3_bucket.media.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "media" {
  bucket                  = aws_s3_bucket.media.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_cors_configuration" "media" {
  bucket = aws_s3_bucket.media.id
  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["GET", "PUT", "POST"]
    allowed_origins = ["https://api.ironlog.app", "https://app.ironlog.app"]
    max_age_seconds = 3600
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "media" {
  bucket = aws_s3_bucket.media.id
  rule {
    id     = "transition-to-ia"
    status = "Enabled"
    filter { prefix = "exercises/videos/" }
    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }
  }
}

# ─────────────────────────────────────────────────────────────
# BACKUPS BUCKET — DB snapshots, workout exports
# ─────────────────────────────────────────────────────────────
resource "aws_s3_bucket" "backups" {
  bucket = var.backups_bucket_name
  tags   = { Name = var.backups_bucket_name, Type = "backups" }
}

resource "aws_s3_bucket_versioning" "backups" {
  bucket = aws_s3_bucket.backups.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "backups" {
  bucket = aws_s3_bucket.backups.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "backups" {
  bucket                  = aws_s3_bucket.backups.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "backups" {
  bucket = aws_s3_bucket.backups.id
  rule {
    id     = "backup-lifecycle"
    status = "Enabled"
    transition {
      days          = var.backup_lifecycle_days_glacier
      storage_class = "GLACIER"
    }
    expiration {
      days = var.backup_lifecycle_days_delete
    }
  }
}

# ─────────────────────────────────────────────────────────────
# ASSETS BUCKET — Flutter web app static files
# ─────────────────────────────────────────────────────────────
resource "aws_s3_bucket" "assets" {
  bucket = var.assets_bucket_name
  tags   = { Name = var.assets_bucket_name, Type = "assets" }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "assets" {
  bucket = aws_s3_bucket.assets.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "assets" {
  bucket                  = aws_s3_bucket.assets.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# CloudFront OAC policy — only CloudFront can read assets
data "aws_iam_policy_document" "assets_cloudfront" {
  statement {
    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.assets.arn}/*"]
    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"
      values   = [var.cloudfront_distribution_arn]
    }
  }
}

resource "aws_s3_bucket_policy" "assets" {
  count  = var.cloudfront_distribution_arn != null ? 1 : 0
  bucket = aws_s3_bucket.assets.id
  policy = data.aws_iam_policy_document.assets_cloudfront.json
}

# Website configuration for SPA routing
resource "aws_s3_bucket_website_configuration" "assets" {
  bucket = aws_s3_bucket.assets.id
  index_document { suffix = "index.html" }
  error_document { key    = "index.html" }    # SPA — all 404s go to index.html
}

# ─────────────────────────────────────────────────────────────
# TERRAFORM STATE BUCKET (bootstrap — run once manually)
# ─────────────────────────────────────────────────────────────
resource "aws_s3_bucket" "terraform_state" {
  bucket = "ironlog-terraform-state-${var.account_id}"
  tags   = { Name = "ironlog-terraform-state" }
}

resource "aws_s3_bucket_versioning" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "terraform_state" {
  bucket                  = aws_s3_bucket.terraform_state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_dynamodb_table" "terraform_locks" {
  name         = "ironlog-terraform-locks"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"
  attribute {
    name = "LockID"
    type = "S"
  }
  tags = { Name = "ironlog-terraform-locks" }
}

# ─────────────────────────────────────────────────────────────
# OUTPUTS
# ─────────────────────────────────────────────────────────────
output "media_bucket_name"              { value = aws_s3_bucket.media.id }
output "media_bucket_arn"               { value = aws_s3_bucket.media.arn }
output "backups_bucket_name"            { value = aws_s3_bucket.backups.id }
output "backups_bucket_arn"             { value = aws_s3_bucket.backups.arn }
output "assets_bucket_name"             { value = aws_s3_bucket.assets.id }
output "assets_bucket_arn"              { value = aws_s3_bucket.assets.arn }
output "assets_bucket_regional_domain"  { value = aws_s3_bucket.assets.bucket_regional_domain_name }
output "assets_website_endpoint"        { value = aws_s3_bucket_website_configuration.assets.website_endpoint }
