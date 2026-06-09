# 🏋️ IronLog — AWS Production Deployment Guide

> Complete guide to deploying IronLog on AWS using ECS Fargate, RDS PostgreSQL,
> ElastiCache Redis, CloudFront CDN, and GitHub Actions CI/CD.

---

## 🏗️ Architecture Overview

```
                    ┌─────────────────────────────────────────┐
                    │              AWS Cloud                   │
                    │                                          │
  Users ──HTTPS──▶  │  CloudFront CDN                          │
  Mobile Apps        │  ├── /api/* ──────▶ ALB ──▶ ECS Fargate │
  Flutter Web        │  │                   │       (NestJS API)│
                    │  └── /* ──────────▶ S3 (Flutter Web)    │
                    │                    │                     │
                    │              ┌─────▼─────────────────┐  │
                    │              │  Private Subnet (VPC)  │  │
                    │              │  ┌─────────────────┐   │  │
                    │              │  │ RDS PostgreSQL  │   │  │
                    │              │  │   (Multi-AZ)    │   │  │
                    │              │  └─────────────────┘   │  │
                    │              │  ┌─────────────────┐   │  │
                    │              │  │ ElastiCache     │   │  │
                    │              │  │ Redis (replica) │   │  │
                    │              │  └─────────────────┘   │  │
                    │              └────────────────────────┘  │
                    │                                          │
                    │  Secrets Manager  WAF  CloudWatch        │
                    └─────────────────────────────────────────┘

GitHub Actions ──push──▶ ECR ──deploy──▶ ECS (rolling update)
```

## 💰 Estimated Monthly Cost

| Service | Staging | Production |
|---------|---------|------------|
| ECS Fargate (1 task, 0.25vCPU/0.5GB) | ~$9 | ~$35 (2 tasks, 0.5vCPU/1GB) |
| RDS PostgreSQL (db.t4g.micro) | ~$13 | ~$70 (db.t4g.medium, Multi-AZ) |
| ElastiCache Redis (cache.t4g.micro) | ~$11 | ~$30 (cache.t4g.small × 2) |
| ALB | ~$16 | ~$22 |
| NAT Gateway | ~$5 | ~$30 (3 × AZ) |
| CloudFront | ~$1 | ~$5 (first 1TB free) |
| S3 | ~$1 | ~$3 |
| ECR | ~$1 | ~$1 |
| Secrets Manager | ~$1 | ~$2 |
| CloudWatch | ~$2 | ~$5 |
| **Total** | **~$60/mo** | **~$203/mo** |

> 💡 Use `FARGATE_SPOT` (30% of tasks) to cut ECS costs by ~70%.

---

## 📋 Prerequisites

| Tool | Version | Install |
|------|---------|---------|
| AWS CLI | v2+ | `brew install awscli` |
| Terraform | 1.7+ | `brew install terraform` |
| Docker | 24+ | [docker.com](https://docker.com) |
| Flutter | 3.19+ | `brew install flutter` |
| Node.js | 20+ | `brew install node` |
| jq | any | `brew install jq` |

---

## 🚀 Deployment Steps

### Step 1 — AWS Account Setup

```bash
# Configure AWS CLI with admin credentials
aws configure
# AWS Access Key ID: AKIA...
# AWS Secret Access Key: ...
# Default region: us-east-1
# Default output: json

# Verify you're in the right account
aws sts get-caller-identity
```

### Step 2 — Bootstrap Infrastructure State

```bash
cd ironlog-aws
chmod +x scripts/bootstrap.sh

# Creates: S3 state bucket, DynamoDB lock table, ECR repository
./scripts/bootstrap.sh us-east-1

# Output: terraform/environments/production/terraform.tfvars (with placeholders)
```

### Step 3 — Request ACM Certificates

You need two wildcard certificates:
- One in `us-east-1` for **CloudFront** (required by AWS)
- One in your deployment region for **ALB**

```bash
# Request wildcard cert in us-east-1 (for CloudFront)
aws acm request-certificate \
  --domain-name "*.ironlog.app" \
  --subject-alternative-names "ironlog.app" \
  --validation-method DNS \
  --region us-east-1

# If your ALB region ≠ us-east-1, also request there:
aws acm request-certificate \
  --domain-name "*.ironlog.app" \
  --validation-method DNS \
  --region us-east-1   # Change to your region

# Get the certificate ARNs and CNAME validation records
aws acm list-certificates --region us-east-1
```

Add the CNAME records to your DNS provider (Route 53, Cloudflare, etc.) and wait for validation (~2 minutes).

### Step 4 — Update terraform.tfvars

```bash
# Edit the generated file
nano terraform/environments/production/terraform.tfvars
```

```hcl
aws_region    = "us-east-1"
db_username   = "ironlog"

# Replace with your actual ACM certificate ARNs
acm_certificate_arn           = "arn:aws:acm:us-east-1:123456789012:certificate/abc-123"
acm_certificate_arn_us_east_1 = "arn:aws:acm:us-east-1:123456789012:certificate/abc-123"

api_domain_name = "api.ironlog.app"
app_domain_name = "app.ironlog.app"

github_org  = "your-github-username"
github_repo = "ironlog"
team_email  = "you@yourcompany.com"
```

### Step 5 — Deploy with Terraform

```bash
cd terraform/environments/production

# Initialize (downloads providers, configures S3 backend)
terraform init

# Preview changes
terraform plan -out=tfplan

# Review the plan carefully, then apply
terraform apply tfplan
```

**First apply takes ~15-20 minutes** (RDS creation is slow).

Save the outputs:
```bash
terraform output
# api_url         = "https://api.ironlog.app"
# ecr_repository  = "123456789012.dkr.ecr.us-east-1.amazonaws.com/ironlog-api"
# ecs_cluster     = "ironlog-prod"
# rds_endpoint    = "ironlog-prod.xxx.us-east-1.rds.amazonaws.com"
# redis_endpoint  = "ironlog-prod.xxx.0001.use1.cache.amazonaws.com"
```

### Step 6 — Set Secrets (Post-Terraform)

After Terraform runs, set the OAuth secrets manually:

```bash
# Google OAuth Client ID (from Google Cloud Console)
aws secretsmanager put-secret-value \
  --secret-id "ironlog/prod/oauth/google-client-id" \
  --secret-string "YOUR_GOOGLE_CLIENT_ID.apps.googleusercontent.com"

# Apple Bundle ID (from App Store Connect)
aws secretsmanager put-secret-value \
  --secret-id "ironlog/prod/oauth/apple-client-id" \
  --secret-string "app.ironlog.ios"

# RevenueCat API keys
aws secretsmanager put-secret-value \
  --secret-id "ironlog/prod/revenuecat/api-keys" \
  --secret-string '{"android":"appl_xxx","ios":"appl_yyy"}'

# AdMob App IDs (stored in app config, not secrets — update pubspec)
```

### Step 7 — Push First Docker Image

```bash
# Get ECR login token
aws ecr get-login-password --region us-east-1 | \
  docker login --username AWS --password-stdin \
  123456789012.dkr.ecr.us-east-1.amazonaws.com

# Build the API image
cd ironlog/backend
docker build -t ironlog-api .

# Tag and push
docker tag ironlog-api:latest \
  123456789012.dkr.ecr.us-east-1.amazonaws.com/ironlog-api:prod-latest

docker push \
  123456789012.dkr.ecr.us-east-1.amazonaws.com/ironlog-api:prod-latest
```

### Step 8 — Run Database Migrations

```bash
cd ironlog-aws
chmod +x scripts/db-migrate.sh
./scripts/db-migrate.sh production us-east-1
```

### Step 9 — Configure GitHub Actions

In your GitHub repo, go to **Settings → Secrets and Variables → Actions** and add:

| Secret | Value | Where to find |
|--------|-------|---------------|
| `AWS_DEPLOY_ROLE_ARN` | `arn:aws:iam::123456789...` | `terraform output` → `github_actions_role_arn` |
| `CLOUDFRONT_DISTRIBUTION_ID` | `E1A2B3C4D5E6F7` | `terraform output` → `cloudfront.distribution_id` |
| `REVENUECAT_IOS_KEY` | `appl_xxx` | RevenueCat dashboard |
| `REVENUECAT_ANDROID_KEY` | `goog_xxx` | RevenueCat dashboard |
| `SLACK_WEBHOOK_URL` | `https://hooks.slack.com/...` | Slack app settings |

> **No AWS_ACCESS_KEY_ID or AWS_SECRET_ACCESS_KEY needed** — we use OIDC (federated identity). The GitHub Actions role is created by Terraform automatically.

### Step 10 — Set Up DNS

Point your domain to CloudFront/ALB:

```
# In your DNS provider:
api.ironlog.app   CNAME   ironlog-prod.xxx.us-east-1.elb.amazonaws.com
app.ironlog.app   CNAME   d1234abcd.cloudfront.net
```

Or with Route 53:
```bash
# Get ALB hosted zone ID
terraform -chdir=terraform/environments/production output alb_zone_id

# Create A records as ALIASes in Route 53
aws route53 change-resource-record-sets \
  --hosted-zone-id Z1234567890 \
  --change-batch '{
    "Changes": [{
      "Action": "UPSERT",
      "ResourceRecordSet": {
        "Name": "api.ironlog.app",
        "Type": "A",
        "AliasTarget": {
          "HostedZoneId": "Z35SXDOTRQ7X7K",
          "DNSName": "ironlog-prod.us-east-1.elb.amazonaws.com",
          "EvaluateTargetHealth": true
        }
      }
    }]
  }'
```

### Step 11 — Verify Deployment

```bash
# API health check
curl https://api.ironlog.app/health
# {"status":"ok","timestamp":"...","database":"connected"}

# API docs
open https://api.ironlog.app/api/docs

# Flutter web app
open https://app.ironlog.app

# CloudWatch dashboard
open "https://console.aws.amazon.com/cloudwatch/home#dashboards:name=IronLog-Production"
```

---

## 🔄 Ongoing Deployments

After initial setup, deployments are **fully automated**:

```bash
# Deploy to production
git push origin main

# Deploy to staging
git push origin staging
```

GitHub Actions will:
1. Run backend tests (with PostgreSQL + Redis)
2. Run Flutter tests and analyze
3. Security scan (Trivy + npm audit)
4. Build Docker image and push to ECR
5. Scan image for vulnerabilities
6. Update ECS task definition
7. Rolling deploy with health checks
8. Run smoke tests
9. Build and deploy Flutter web to S3/CloudFront
10. Notify Slack on failure

---

## 🔧 Operations

### Scale ECS manually

```bash
aws ecs update-service \
  --cluster ironlog-prod \
  --service ironlog-api \
  --desired-count 4 \
  --region us-east-1
```

### View live logs

```bash
# Tail ECS logs from CloudWatch
aws logs tail /ecs/ironlog-prod/api \
  --follow \
  --format short \
  --region us-east-1

# Filter for errors only
aws logs tail /ecs/ironlog-prod/api \
  --follow \
  --filter-pattern "{ $.status >= 500 }" \
  --region us-east-1
```

### Connect to RDS (via ECS exec)

```bash
# Enable ECS Exec on the service (one-time)
aws ecs update-service \
  --cluster ironlog-prod \
  --service ironlog-api \
  --enable-execute-command \
  --region us-east-1

# Get a running task ARN
TASK=$(aws ecs list-tasks \
  --cluster ironlog-prod \
  --service-name ironlog-api \
  --query 'taskArns[0]' \
  --output text)

# Open a shell in the container
aws ecs execute-command \
  --cluster ironlog-prod \
  --task $TASK \
  --container ironlog-api \
  --command "/bin/sh" \
  --interactive
```

### Run database migrations in production

```bash
./scripts/db-migrate.sh production us-east-1
```

### Rollback a bad deployment

```bash
# List recent task definitions
aws ecs list-task-definitions \
  --family-prefix ironlog-api-task \
  --sort DESC \
  --query 'taskDefinitionArns[:5]' \
  --output table

# Roll back to previous task definition
aws ecs update-service \
  --cluster ironlog-prod \
  --service ironlog-api \
  --task-definition ironlog-api-task:42 \
  --region us-east-1
```

### Backup database manually

```bash
# Create manual RDS snapshot
aws rds create-db-snapshot \
  --db-instance-identifier ironlog-prod \
  --db-snapshot-identifier "ironlog-manual-$(date +%Y%m%d%H%M%S)" \
  --region us-east-1
```

### Destroy staging (save costs)

```bash
cd terraform/environments/staging
terraform destroy

# Re-create when needed
terraform apply
```

---

## 🔐 Security Notes

| Control | Implementation |
|---------|---------------|
| No static AWS keys | OIDC roles for GitHub Actions |
| Secrets rotation | AWS Secrets Manager (auto-rotation configurable) |
| Network isolation | ECS/RDS/Redis in private subnets, no public IPs |
| TLS everywhere | TLS 1.3 on ALB, TLS on Redis, SSL on RDS |
| WAF protection | Rate limiting, SQLi, OWASP Top 10 |
| Container hardening | Drop ALL Linux capabilities, non-root user |
| Image scanning | ECR scan on push + Trivy in CI |
| Audit logging | CloudTrail (enable separately) + VPC Flow Logs |
| GDPR | User deletion anonymizes data, purged after 30 days |

---

## 📁 File Structure

```
ironlog-aws/
├── terraform/
│   ├── modules/
│   │   ├── vpc/           # VPC, subnets, security groups, flow logs
│   │   ├── rds/           # PostgreSQL Multi-AZ with parameter groups
│   │   ├── elasticache/   # Redis replication group with TLS
│   │   ├── ecs/           # Fargate cluster, service, auto-scaling, ECR
│   │   ├── alb/           # ALB, target groups, WAF, listeners
│   │   ├── cloudfront/    # CDN, cache policies, OAC, SPA routing
│   │   ├── s3/            # Media, backups, Flutter web assets
│   │   ├── iam/           # ECS roles, GitHub OIDC, least-privilege policies
│   │   ├── secrets/       # Secrets Manager for all credentials
│   │   └── monitoring/    # CloudWatch dashboard, alarms, SNS
│   └── environments/
│       ├── production/    # main.tf, variables.tf, terraform.tfvars
│       └── staging/       # Same arch, smaller instances, lower cost
├── .github/
│   └── workflows/
│       └── deploy.yml     # Full CI/CD: test → build → scan → deploy
├── scripts/
│   ├── bootstrap.sh       # One-time setup: S3 state, DynamoDB, ECR
│   └── db-migrate.sh      # Run migrations via ECS task (no bastion)
└── backend-aws-additions.ts  # NestJS: Redis, S3, SES, interceptors
```

---

## 🆘 Troubleshooting

### ECS tasks keep restarting
```bash
# Check task stopped reason
aws ecs describe-tasks \
  --cluster ironlog-prod \
  --tasks $(aws ecs list-tasks --cluster ironlog-prod --query 'taskArns[0]' --output text) \
  --query 'tasks[0].{stopped:stoppedReason,containers:containers[*].{name:name,exit:exitCode,reason:reason}}'
```

### RDS connection refused
```bash
# Verify security group allows ECS → RDS on port 5432
aws ec2 describe-security-groups \
  --group-ids sg-xxxxx \
  --query 'SecurityGroups[0].IpPermissions'
```

### Secrets not injecting into container
```bash
# Verify execution role has secretsmanager:GetSecretValue
aws iam simulate-principal-policy \
  --policy-source-arn arn:aws:iam::123456789012:role/ironlog-prod-ecs-execution-role \
  --action-names secretsmanager:GetSecretValue \
  --resource-arns arn:aws:secretsmanager:us-east-1:123456789012:secret:ironlog/prod/*
```

### High RDS CPU
- Check slow query log in CloudWatch: `/aws/rds/instance/ironlog-prod/postgresql`
- Add indexes, check for N+1 queries
- Consider RDS Proxy for connection pooling

### CloudFront serving stale content
```bash
aws cloudfront create-invalidation \
  --distribution-id E1ABCDEF \
  --paths "/*"
```
