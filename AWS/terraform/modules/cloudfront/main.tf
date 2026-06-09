# terraform/modules/cloudfront/main.tf
# CloudFront distribution: API pass-through + Flutter web app delivery

# ─────────────────────────────────────────────────────────────
# ORIGIN ACCESS CONTROL (S3 → CloudFront)
# ─────────────────────────────────────────────────────────────
resource "aws_cloudfront_origin_access_control" "assets" {
  name                              = "ironlog-assets-oac"
  description                       = "OAC for Flutter web assets S3 bucket"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# ─────────────────────────────────────────────────────────────
# CACHE POLICIES
# ─────────────────────────────────────────────────────────────

# API — no caching (dynamic content)
resource "aws_cloudfront_cache_policy" "api" {
  name        = "ironlog-api-no-cache"
  comment     = "No cache for API requests"
  default_ttl = 0
  max_ttl     = 0
  min_ttl     = 0

  parameters_in_cache_key_and_forwarded_to_origin {
    enable_accept_encoding_gzip   = true
    enable_accept_encoding_brotli = true

    cookies_config {
      cookie_behavior = "none"
    }
    headers_config {
      header_behavior = "whitelist"
      headers {
        items = ["Authorization", "Content-Type", "Accept", "Origin"]
      }
    }
    query_strings_config {
      query_string_behavior = "all"
    }
  }
}

# Static assets — aggressive caching with versioning
resource "aws_cloudfront_cache_policy" "assets" {
  name        = "ironlog-assets-cache"
  comment     = "Aggressive cache for versioned Flutter assets"
  default_ttl = 86400     # 1 day
  max_ttl     = 31536000  # 1 year
  min_ttl     = 0

  parameters_in_cache_key_and_forwarded_to_origin {
    enable_accept_encoding_gzip   = true
    enable_accept_encoding_brotli = true

    cookies_config { cookie_behavior = "none" }
    headers_config  { header_behavior = "none" }
    query_strings_config { query_string_behavior = "none" }
  }
}

# ─────────────────────────────────────────────────────────────
# RESPONSE HEADERS POLICY — security headers
# ─────────────────────────────────────────────────────────────
resource "aws_cloudfront_response_headers_policy" "security" {
  name    = "ironlog-security-headers"
  comment = "Security headers for IronLog"

  security_headers_config {
    strict_transport_security {
      access_control_max_age_sec = 31536000
      include_subdomains         = true
      preload                    = true
      override                   = true
    }
    content_type_options {
      override = true
    }
    frame_options {
      frame_option = "DENY"
      override     = true
    }
    xss_protection {
      mode_block = true
      protection = true
      override   = true
    }
    referrer_policy {
      referrer_policy = "strict-origin-when-cross-origin"
      override        = true
    }
    content_security_policy {
      content_security_policy = "default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'; img-src 'self' data: https:; connect-src 'self' https://api.ironlog.app;"
      override                = true
    }
  }

  custom_headers_config {
    items {
      header   = "Permissions-Policy"
      value    = "camera=(), microphone=(), geolocation=()"
      override = true
    }
    items {
      header   = "X-Powered-By"
      value    = ""
      override = true
    }
  }
}

# ─────────────────────────────────────────────────────────────
# CLOUDFRONT DISTRIBUTION
# ─────────────────────────────────────────────────────────────
resource "aws_cloudfront_distribution" "main" {
  enabled             = true
  is_ipv6_enabled     = true
  comment             = "IronLog CDN — API + Flutter Web"
  default_root_object = "index.html"
  price_class         = var.price_class
  aliases             = var.aliases
  web_acl_id          = var.waf_web_acl_id    # WAF (must be us-east-1 for CloudFront)

  # ── Origin 1: ALB (API) ────────────────────────────────────
  origin {
    domain_name = var.alb_dns_name
    origin_id   = "alb-api"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
      origin_read_timeout    = 60
      origin_keepalive_timeout = 60
    }

    custom_header {
      name  = "X-CloudFront-Secret"
      value = random_string.cf_secret.result
    }
  }

  # ── Origin 2: S3 assets (Flutter web) ─────────────────────
  origin {
    domain_name              = var.assets_bucket_domain
    origin_id                = "s3-assets"
    origin_access_control_id = aws_cloudfront_origin_access_control.assets.id
  }

  # ── Behavior 1: API requests — forward to ALB ─────────────
  ordered_cache_behavior {
    path_pattern             = var.api_path_pattern
    allowed_methods          = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods           = ["GET", "HEAD"]
    target_origin_id         = "alb-api"
    cache_policy_id          = aws_cloudfront_cache_policy.api.id
    compress                 = true
    viewer_protocol_policy   = "redirect-to-https"
    response_headers_policy_id = aws_cloudfront_response_headers_policy.security.id
  }

  # ── Behavior 2: Health check — forward to ALB ─────────────
  ordered_cache_behavior {
    path_pattern           = var.health_path_pattern
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = "alb-api"
    cache_policy_id        = aws_cloudfront_cache_policy.api.id
    compress               = true
    viewer_protocol_policy = "redirect-to-https"
  }

  # ── Default: Flutter web app from S3 ──────────────────────
  default_cache_behavior {
    allowed_methods          = ["GET", "HEAD", "OPTIONS"]
    cached_methods           = ["GET", "HEAD"]
    target_origin_id         = "s3-assets"
    cache_policy_id          = aws_cloudfront_cache_policy.assets.id
    compress                 = true
    viewer_protocol_policy   = "redirect-to-https"
    response_headers_policy_id = aws_cloudfront_response_headers_policy.security.id

    # Flutter WASM support
    function_association {
      event_type   = "viewer-request"
      function_arn = aws_cloudfront_function.spa_routing.arn
    }
  }

  # ── Custom error pages (SPA routing) ──────────────────────
  custom_error_response {
    error_code            = 403
    response_code         = 200
    response_page_path    = "/index.html"
    error_caching_min_ttl = 0
  }

  custom_error_response {
    error_code            = 404
    response_code         = 200
    response_page_path    = "/index.html"
    error_caching_min_ttl = 0
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn      = var.acm_certificate_arn
    minimum_protocol_version = "TLSv1.2_2021"
    ssl_support_method       = "sni-only"
  }

  # Access logging
  logging_config {
    include_cookies = false
    bucket          = "${var.logs_bucket}.s3.amazonaws.com"
    prefix          = "cloudfront/"
  }

  tags = { Name = "ironlog-cdn" }
}

# ─────────────────────────────────────────────────────────────
# CLOUDFRONT FUNCTION — SPA routing for Flutter web
# ─────────────────────────────────────────────────────────────
resource "aws_cloudfront_function" "spa_routing" {
  name    = "ironlog-spa-routing"
  runtime = "cloudfront-js-2.0"
  comment = "Redirect Flutter web SPA routes to index.html"
  publish = true
  code    = <<-EOF
    function handler(event) {
      var request = event.request;
      var uri = request.uri;

      // Serve files with extensions directly
      if (uri.match(/\.[a-zA-Z0-9]+$/)) {
        return request;
      }

      // API calls pass through (handled by ordered behavior)
      if (uri.startsWith('/api/') || uri === '/health') {
        return request;
      }

      // SPA: all other paths return index.html
      request.uri = '/index.html';
      return request;
    }
  EOF
}

# ─────────────────────────────────────────────────────────────
# SECRET — verify requests come from CloudFront (not direct ALB)
# ─────────────────────────────────────────────────────────────
resource "random_string" "cf_secret" {
  length  = 32
  special = false
}

# ─────────────────────────────────────────────────────────────
# OUTPUTS
# ─────────────────────────────────────────────────────────────
output "distribution_domain"  { value = aws_cloudfront_distribution.main.domain_name }
output "distribution_id"      { value = aws_cloudfront_distribution.main.id }
output "distribution_arn"     { value = aws_cloudfront_distribution.main.arn }
output "oac_id"               { value = aws_cloudfront_origin_access_control.assets.id }
