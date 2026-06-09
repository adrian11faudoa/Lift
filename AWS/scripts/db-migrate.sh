#!/usr/bin/env bash
# scripts/db-migrate.sh
# Run database migrations against RDS via an ECS task (no bastion needed).
# Uses ECS run-task to execute migration in the same VPC as RDS.
#
# Usage: ./scripts/db-migrate.sh [environment] [region]
# Example: ./scripts/db-migrate.sh production us-east-1

set -euo pipefail

ENVIRONMENT="${1:-staging}"
REGION="${2:-us-east-1}"
CLUSTER="ironlog-${ENVIRONMENT}"
TASK_FAMILY="ironlog-api-task"
CONTAINER="ironlog-api"

echo "╔══════════════════════════════════════════════════════╗"
echo "║  IronLog DB Migration — ${ENVIRONMENT}                      ║"
echo "╚══════════════════════════════════════════════════════╝"

# Get current task definition ARN
TASK_DEF=$(aws ecs describe-task-definition \
  --task-definition "${TASK_FAMILY}" \
  --region "${REGION}" \
  --query 'taskDefinition.taskDefinitionArn' \
  --output text)

echo "Using task definition: ${TASK_DEF}"

# Get subnet and security group from ECS service
SERVICE_DESC=$(aws ecs describe-services \
  --cluster "${CLUSTER}" \
  --services ironlog-api \
  --region "${REGION}" \
  --query 'services[0].networkConfiguration.awsvpcConfiguration')

SUBNETS=$(echo "$SERVICE_DESC" | jq -r '.subnets | join(",")')
SG=$(echo "$SERVICE_DESC" | jq -r '.securityGroups[0]')

echo "Subnets: ${SUBNETS}"
echo "Security Group: ${SG}"
echo ""
echo "▶ Running migration task..."

TASK_ARN=$(aws ecs run-task \
  --cluster "${CLUSTER}" \
  --task-definition "${TASK_DEF}" \
  --count 1 \
  --launch-type FARGATE \
  --network-configuration "awsvpcConfiguration={subnets=[${SUBNETS}],securityGroups=[${SG}],assignPublicIp=DISABLED}" \
  --overrides "{
    \"containerOverrides\": [{
      \"name\": \"${CONTAINER}\",
      \"command\": [\"node\", \"dist/scripts/migrate.js\"],
      \"environment\": [{
        \"name\": \"RUN_MIGRATIONS\",
        \"value\": \"true\"
      }]
    }]
  }" \
  --region "${REGION}" \
  --query 'tasks[0].taskArn' \
  --output text)

echo "Task ARN: ${TASK_ARN}"
echo ""
echo "▶ Waiting for migration to complete..."

aws ecs wait tasks-stopped \
  --cluster "${CLUSTER}" \
  --tasks "${TASK_ARN}" \
  --region "${REGION}"

# Check exit code
EXIT_CODE=$(aws ecs describe-tasks \
  --cluster "${CLUSTER}" \
  --tasks "${TASK_ARN}" \
  --region "${REGION}" \
  --query "tasks[0].containers[?name=='${CONTAINER}'].exitCode" \
  --output text)

if [ "${EXIT_CODE}" = "0" ]; then
  echo ""
  echo "✅ Migration completed successfully!"
else
  echo ""
  echo "❌ Migration FAILED (exit code: ${EXIT_CODE})"
  echo "Check CloudWatch Logs: /ecs/ironlog-${ENVIRONMENT}/api"
  exit 1
fi
