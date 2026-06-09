#!/usr/bin/env bash
# scripts/disaster-recovery.sh
# IronLog Disaster Recovery Runbook
#
# Scenarios covered:
#   1. RDS failover verification
#   2. Restore from RDS snapshot
#   3. ECS service restart
#   4. Full environment restore
#
# Usage: ./scripts/disaster-recovery.sh [scenario] [options]

set -euo pipefail

REGION="${AWS_REGION:-us-east-1}"
ENV="${ENVIRONMENT:-production}"
CLUSTER="ironlog-${ENV}"
RDS_ID="ironlog-${ENV}"

print_header() {
  echo ""
  echo "╔══════════════════════════════════════════════════════╗"
  echo "║  $1"
  echo "╚══════════════════════════════════════════════════════╝"
}

# ─────────────────────────────────────────────────────────────
# SCENARIO 1: Check RDS Multi-AZ Failover Status
# ─────────────────────────────────────────────────────────────
check_rds_health() {
  print_header "RDS Health Check — ${RDS_ID}"

  STATUS=$(aws rds describe-db-instances \
    --db-instance-identifier "${RDS_ID}" \
    --region "${REGION}" \
    --query 'DBInstances[0].{
      Status:DBInstanceStatus,
      AZ:AvailabilityZone,
      MultiAZ:MultiAZ,
      Endpoint:Endpoint.Address,
      Storage:AllocatedStorage,
      FreeStorage:FreeStorageSpace
    }' \
    --output table 2>/dev/null)

  echo "${STATUS}"

  # Check if RDS is accepting connections
  echo ""
  echo "▶ Testing connectivity (via ECS task)..."
  TASK=$(aws ecs list-tasks \
    --cluster "${CLUSTER}" \
    --service-name ironlog-api \
    --region "${REGION}" \
    --query 'taskArns[0]' \
    --output text 2>/dev/null)

  if [ -n "${TASK}" ] && [ "${TASK}" != "None" ]; then
    echo "  Running health check via ECS task: ${TASK}"
    aws ecs execute-command \
      --cluster "${CLUSTER}" \
      --task "${TASK}" \
      --container ironlog-api \
      --command "curl -s http://localhost:3000/health" \
      --interactive \
      --region "${REGION}" 2>/dev/null || echo "  ⚠ ECS Exec not enabled or task not available"
  fi
}

# ─────────────────────────────────────────────────────────────
# SCENARIO 2: Trigger Manual RDS Failover (Multi-AZ)
# ─────────────────────────────────────────────────────────────
trigger_rds_failover() {
  print_header "Triggering RDS Multi-AZ Failover"
  echo "⚠ This will cause 60-120 seconds of database downtime!"
  echo ""
  read -p "Are you sure? Type 'failover' to confirm: " CONFIRM
  if [ "${CONFIRM}" != "failover" ]; then
    echo "Aborted."
    exit 0
  fi

  echo "▶ Initiating failover..."
  aws rds reboot-db-instance \
    --db-instance-identifier "${RDS_ID}" \
    --force-failover \
    --region "${REGION}"

  echo "▶ Waiting for RDS to become available..."
  aws rds wait db-instance-available \
    --db-instance-identifier "${RDS_ID}" \
    --region "${REGION}"

  echo "✅ Failover complete. Verify endpoint hasn't changed:"
  aws rds describe-db-instances \
    --db-instance-identifier "${RDS_ID}" \
    --region "${REGION}" \
    --query 'DBInstances[0].{Endpoint:Endpoint.Address,AZ:AvailabilityZone}' \
    --output table
}

# ─────────────────────────────────────────────────────────────
# SCENARIO 3: Restore RDS from Snapshot
# ─────────────────────────────────────────────────────────────
restore_from_snapshot() {
  local SNAPSHOT_ID="${1:-}"
  print_header "Restore RDS from Snapshot"

  if [ -z "${SNAPSHOT_ID}" ]; then
    echo "Available snapshots (last 5):"
    aws rds describe-db-snapshots \
      --db-instance-identifier "${RDS_ID}" \
      --region "${REGION}" \
      --query 'DBSnapshots[*].{ID:DBSnapshotIdentifier,Status:Status,Time:SnapshotCreateTime,Size:AllocatedStorage}' \
      --output table | head -20

    read -p "Enter snapshot ID: " SNAPSHOT_ID
  fi

  local NEW_ID="${RDS_ID}-restored-$(date +%Y%m%d%H%M%S)"
  echo ""
  echo "▶ Restoring snapshot ${SNAPSHOT_ID} to ${NEW_ID}..."

  # Get VPC and security group from current instance
  VPC_SG=$(aws rds describe-db-instances \
    --db-instance-identifier "${RDS_ID}" \
    --region "${REGION}" \
    --query 'DBInstances[0].VpcSecurityGroups[0].VpcSecurityGroupId' \
    --output text)

  SUBNET_GROUP=$(aws rds describe-db-instances \
    --db-instance-identifier "${RDS_ID}" \
    --region "${REGION}" \
    --query 'DBInstances[0].DBSubnetGroup.DBSubnetGroupName' \
    --output text)

  aws rds restore-db-instance-from-db-snapshot \
    --db-instance-identifier "${NEW_ID}" \
    --db-snapshot-identifier "${SNAPSHOT_ID}" \
    --db-instance-class db.t4g.medium \
    --db-subnet-group-name "${SUBNET_GROUP}" \
    --vpc-security-group-ids "${VPC_SG}" \
    --no-publicly-accessible \
    --multi-az \
    --region "${REGION}"

  echo "▶ Waiting for restored instance to be available (~10-20 minutes)..."
  aws rds wait db-instance-available \
    --db-instance-identifier "${NEW_ID}" \
    --region "${REGION}"

  NEW_ENDPOINT=$(aws rds describe-db-instances \
    --db-instance-identifier "${NEW_ID}" \
    --region "${REGION}" \
    --query 'DBInstances[0].Endpoint.Address' \
    --output text)

  echo ""
  echo "✅ Restore complete!"
  echo "   New endpoint: ${NEW_ENDPOINT}"
  echo ""
  echo "Next steps:"
  echo "  1. Verify data integrity: psql -h ${NEW_ENDPOINT} -U ironlog -d ironlog"
  echo "  2. Update DB_HOST in ECS task definition or Secrets Manager"
  echo "  3. Redeploy ECS service to pick up new endpoint"
  echo "  4. Delete old instance when ready: aws rds delete-db-instance --db-instance-identifier ${RDS_ID}"
}

# ─────────────────────────────────────────────────────────────
# SCENARIO 4: Force ECS Service Restart
# ─────────────────────────────────────────────────────────────
restart_ecs_service() {
  print_header "Force ECS Service Restart — ironlog-api"

  echo "▶ Current task status:"
  aws ecs list-tasks \
    --cluster "${CLUSTER}" \
    --service-name ironlog-api \
    --region "${REGION}" \
    --output table

  echo ""
  echo "▶ Force new deployment (stops all tasks, starts fresh)..."
  aws ecs update-service \
    --cluster "${CLUSTER}" \
    --service ironlog-api \
    --force-new-deployment \
    --region "${REGION}" \
    --query 'service.{Status:status,Desired:desiredCount,Running:runningCount,Pending:pendingCount}'

  echo ""
  echo "▶ Waiting for service stability..."
  aws ecs wait services-stable \
    --cluster "${CLUSTER}" \
    --services ironlog-api \
    --region "${REGION}"

  echo "✅ Service restarted and stable"
}

# ─────────────────────────────────────────────────────────────
# SCENARIO 5: Full Status Check
# ─────────────────────────────────────────────────────────────
full_status_check() {
  print_header "IronLog ${ENV} — Full Status Check"

  # API Health
  echo "▶ API Health:"
  HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
    https://api.ironlog.app/health 2>/dev/null || echo "000")
  if [ "${HTTP_STATUS}" = "200" ]; then
    echo "  ✅ API responding (HTTP ${HTTP_STATUS})"
  else
    echo "  ❌ API NOT responding (HTTP ${HTTP_STATUS})"
  fi

  # ECS
  echo ""
  echo "▶ ECS Service:"
  aws ecs describe-services \
    --cluster "${CLUSTER}" \
    --services ironlog-api \
    --region "${REGION}" \
    --query 'services[0].{
      Status:status,
      Desired:desiredCount,
      Running:runningCount,
      Pending:pendingCount,
      Deployments:deployments[*].{ID:id,Status:status,Desired:desiredCount,Running:runningCount}
    }' \
    --output table

  # RDS
  echo ""
  echo "▶ RDS:"
  aws rds describe-db-instances \
    --db-instance-identifier "${RDS_ID}" \
    --region "${REGION}" \
    --query 'DBInstances[0].{
      Status:DBInstanceStatus,
      AZ:AvailabilityZone,
      MultiAZ:MultiAZ,
      FreeStorage:FreeStorageSpace
    }' \
    --output table

  # ElastiCache
  echo ""
  echo "▶ ElastiCache Redis:"
  aws elasticache describe-replication-groups \
    --replication-group-id "ironlog-${ENV}" \
    --region "${REGION}" \
    --query 'ReplicationGroups[0].{
      Status:Status,
      Primary:NodeGroups[0].PrimaryEndpoint.Address,
      Members:MemberClusters
    }' \
    --output table

  # ALB Health
  echo ""
  echo "▶ ALB Target Health:"
  TG_ARN=$(aws elbv2 describe-target-groups \
    --names "ironlog-${ENV}-api-tg" \
    --region "${REGION}" \
    --query 'TargetGroups[0].TargetGroupArn' \
    --output text 2>/dev/null || echo "")
  if [ -n "${TG_ARN}" ]; then
    aws elbv2 describe-target-health \
      --target-group-arn "${TG_ARN}" \
      --region "${REGION}" \
      --query 'TargetHealthDescriptions[*].{IP:Target.Id,Port:Target.Port,Health:TargetHealth.State,Reason:TargetHealth.Description}' \
      --output table
  fi

  echo ""
  echo "▶ Recent CloudWatch Alarms (ALARM state):"
  aws cloudwatch describe-alarms \
    --state-value ALARM \
    --alarm-name-prefix "ironlog" \
    --region "${REGION}" \
    --query 'MetricAlarms[*].{Name:AlarmName,State:StateValue,Reason:StateReason}' \
    --output table 2>/dev/null || echo "  No alarms in ALARM state ✅"
}

# ─────────────────────────────────────────────────────────────
# MAIN
# ─────────────────────────────────────────────────────────────
SCENARIO="${1:-status}"

case "${SCENARIO}" in
  "status")         full_status_check ;;
  "rds-health")     check_rds_health ;;
  "rds-failover")   trigger_rds_failover ;;
  "rds-restore")    restore_from_snapshot "${2:-}" ;;
  "ecs-restart")    restart_ecs_service ;;
  *)
    echo "Usage: $0 [status|rds-health|rds-failover|rds-restore|ecs-restart]"
    echo ""
    echo "Scenarios:"
    echo "  status        Full system health check (default)"
    echo "  rds-health    RDS instance health and connectivity"
    echo "  rds-failover  Trigger Multi-AZ failover (causes brief downtime)"
    echo "  rds-restore   Restore RDS from a snapshot"
    echo "  ecs-restart   Force restart all ECS tasks"
    exit 1
    ;;
esac
