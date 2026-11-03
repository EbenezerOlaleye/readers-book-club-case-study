#!/usr/bin/env bash
# Excerpt from the private Readers Book Club repository (infrastructure/scripts/ecs-deploy.sh).
# Deploy a new image to an ECS service and wait until it is healthy.
#
# Usage: ecs-deploy.sh <cluster> <service> <container-name> <image>
#   e.g. ecs-deploy.sh rbc-staging backend backend 1234.dkr.ecr.eu-west-1.amazonaws.com/readers-bookclub-backend:42-a1b2c3d
#
# Starts from the LATEST revision of the task definition family (not the one
# the service is running), so settings changed by `terraform apply` - env vars,
# secrets, CPU/memory - go out with the next deploy instead of being dropped.
set -euo pipefail

CLUSTER=$1
SERVICE=$2
CONTAINER=$3
IMAGE=$4
FAMILY="${CLUSTER}-${SERVICE}"
WORKDIR=$(mktemp -d)
trap 'rm -rf "$WORKDIR"' EXIT

aws ecs describe-task-definition --task-definition "$FAMILY" --query taskDefinition \
  | jq --arg c "$CONTAINER" --arg img "$IMAGE" '
      .containerDefinitions |= map(if .name == $c then .image = $img else . end)
      | del(.taskDefinitionArn, .revision, .status, .requiresAttributes,
            .compatibilities, .registeredAt, .registeredBy, .deregisteredAt)' \
  > "$WORKDIR/taskdef.json"

NEW_ARN=$(aws ecs register-task-definition --cli-input-json "file://$WORKDIR/taskdef.json" \
  --query 'taskDefinition.taskDefinitionArn' --output text)

aws ecs update-service --cluster "$CLUSTER" --service "$SERVICE" \
  --task-definition "$NEW_ARN" > /dev/null

echo "Waiting for $CLUSTER/$SERVICE to become stable on $NEW_ARN ..."
aws ecs wait services-stable --cluster "$CLUSTER" --services "$SERVICE"

# The circuit breaker may have rolled back to the old revision; that is a failure
RUNNING=$(aws ecs describe-services --cluster "$CLUSTER" --services "$SERVICE" \
  --query 'services[0].taskDefinition' --output text)
if [ "$RUNNING" != "$NEW_ARN" ]; then
  echo "Deployment rolled back: service is running $RUNNING, not $NEW_ARN" >&2
  exit 1
fi

echo "Deployed $IMAGE to $CLUSTER/$SERVICE ($NEW_ARN)"
