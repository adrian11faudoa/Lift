#!/usr/bin/env bash
# scripts/cost-report.sh
# Pulls AWS Cost Explorer data for IronLog resources.
# Requires: aws-cli v2, jq
# Usage: ./scripts/cost-report.sh [days_back]

set -euo pipefail
DAYS="${1:-30}"
END=$(date +%Y-%m-%d)
START=$(date -v-${DAYS}d +%Y-%m-%d 2>/dev/null || date -d "-${DAYS} days" +%Y-%m-%d)

echo "╔══════════════════════════════════════════════════════╗"
echo "║     IronLog AWS Cost Report (last ${DAYS} days)          ║"
echo "╚══════════════════════════════════════════════════════╝"
echo "Period: ${START} → ${END}"
echo ""

# Total cost with tag filter
TOTAL=$(aws ce get-cost-and-usage \
  --time-period "Start=${START},End=${END}" \
  --granularity MONTHLY \
  --metrics BlendedCost \
  --filter '{
    "Tags": {
      "Key": "Project",
      "Values": ["IronLog"]
    }
  }' \
  --query 'ResultsByTime[*].Total.BlendedCost.Amount' \
  --output text 2>/dev/null | awk '{sum+=$1} END {printf "%.2f", sum}')

echo "💰 Total Cost: \$${TOTAL}"
echo ""

# Cost by service
echo "📊 Cost by Service:"
aws ce get-cost-and-usage \
  --time-period "Start=${START},End=${END}" \
  --granularity MONTHLY \
  --metrics BlendedCost \
  --group-by '[{"Type":"DIMENSION","Key":"SERVICE"}]' \
  --filter '{
    "Tags": {
      "Key": "Project",
      "Values": ["IronLog"]
    }
  }' \
  --query 'ResultsByTime[0].Groups[*].[Keys[0],Metrics.BlendedCost.Amount]' \
  --output table 2>/dev/null | head -30

echo ""
echo "💡 Cost Optimization Tips:"
echo "  1. ECS FARGATE_SPOT saves ~70% on compute (already configured)"
echo "  2. RDS storage auto-scaling prevents over-provisioning"
echo "  3. ElastiCache t4g instances are ARM-based (cheaper than x86)"
echo "  4. S3 Intelligent-Tiering auto-moves cold data to IA"
echo "  5. CloudFront first 1TB/month is free"
echo "  6. Reserved Instances save ~40% for RDS/ElastiCache (1-year commit)"
echo ""
echo "🔧 Quick wins:"

# Check for idle resources
echo "  Checking for stopped/unused resources..."
STOPPED_RDS=$(aws rds describe-db-instances \
  --query 'DBInstances[?DBInstanceStatus==`stopped`].[DBInstanceIdentifier,DBInstanceClass]' \
  --output text 2>/dev/null || echo "")
if [ -n "${STOPPED_RDS}" ]; then
  echo "  ⚠ Stopped RDS instances (still cost storage): ${STOPPED_RDS}"
fi
