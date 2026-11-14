#!/bin/bash
set -Eeuo pipefail

exec > >(tee -a /var/log/backend-bootstrap.log) 2>&1

echo "Starting MuchToDo backend bootstrap..."

# Terraform template variables: keep these five expressions unchanged.
AWS_REGION="${aws_region}"
AWS_ACCOUNT_ID="${aws_account_id}"
ECR_REPOSITORY="${ecr_repository}"
IMAGE_TAG="${image_tag}"
PROJECT_NAME="${project_name}"

APP_DIR="/opt/muchtodo"
COMPOSE_VERSION="v5.7.1"
COMPOSE_PLUGIN_DIR="/usr/local/lib/docker/cli-plugins"
COMPOSE_PLUGIN="$${COMPOSE_PLUGIN_DIR}/docker-compose"
COMPOSE_DEPLOY_STARTED=false
DEPLOYMENT_SUCCEEDED=false
PREVIOUS_CONTAINER=""

# Install Docker, AWS CLI and required utilities.
dnf update -y
dnf install -y docker awscli-2 curl

systemctl enable --now docker

# Install and verify Docker Compose.
ARCH="$(uname -m)"

if [[ "$${ARCH}" != "x86_64" ]]; then
    echo "ERROR: Unsupported architecture: $${ARCH}"
    exit 1
fi

mkdir -p "$COMPOSE_PLUGIN_DIR"

curl -fsSL \
    "https://github.com/docker/compose/releases/download/$${COMPOSE_VERSION}/docker-compose-linux-x86_64" \
    -o /tmp/docker-compose

curl -fsSL \
    "https://github.com/docker/compose/releases/download/$${COMPOSE_VERSION}/checksums.txt" \
    -o /tmp/docker-compose-checksums.txt

EXPECTED_CHECKSUM="$(awk '$2 == "docker-compose-linux-x86_64" {print $1}' /tmp/docker-compose-checksums.txt)"

if [[ -z "$${EXPECTED_CHECKSUM}" ]]; then
    echo "ERROR: Could not retrieve Docker Compose checksum."
    exit 1
fi

printf '%s  %s\n' "$EXPECTED_CHECKSUM" /tmp/docker-compose | sha256sum -c -

install -m 0755 /tmp/docker-compose "$COMPOSE_PLUGIN"

rm -f /tmp/docker-compose /tmp/docker-compose-checksums.txt

docker compose version

# Retrieve application configuration from AWS Systems Manager.
get_parameter() {
    aws ssm get-parameter \
        --name "$1" \
        --with-decryption \
        --query 'Parameter.Value' \
        --output text \
        --region "$AWS_REGION"
}

echo "Retrieving application configuration from SSM..."

MONGO_URI="$(get_parameter "/$${PROJECT_NAME}/backend/mongo-uri")"
DB_NAME="$(get_parameter "/$${PROJECT_NAME}/backend/db-name")"
JWT_SECRET_KEY="$(get_parameter "/$${PROJECT_NAME}/backend/jwt-secret")"
ENABLE_CACHE="$(get_parameter "/$${PROJECT_NAME}/backend/enable-cache")"

# Validate configuration before writing it to disk.
if [[ "$${MONGO_URI}" != mongodb://* ]]; then
    echo "ERROR: MONGO_URI must use the mongodb:// scheme."
    exit 1
fi

MONGO_URI_PATTERN='^[A-Za-z0-9:/?&=%@.,_+-]+$'

if [[ ! "$${MONGO_URI}" =~ $MONGO_URI_PATTERN ]]; then
    echo "ERROR: MONGO_URI contains unsupported characters."
    exit 1
fi

if [[ ! "$${DB_NAME}" =~ ^[A-Za-z0-9_-]+$ ]]; then
    echo "ERROR: DB_NAME contains unsupported characters."
    exit 1
fi

if [[ ! "$${JWT_SECRET_KEY}" =~ ^[A-Za-z0-9_+/=-]+$ ]]; then
    echo "ERROR: JWT_SECRET_KEY contains unsupported characters."
    exit 1
fi

if [[ "$${ENABLE_CACHE}" != "true" && "$${ENABLE_CACHE}" != "false" ]]; then
    echo "ERROR: ENABLE_CACHE must be true or false."
    exit 1
fi

# Create a protected application directory and environment file.
install -d -o root -g root -m 0750 "$APP_DIR"

umask 077

cat > "$APP_DIR/.env" <<ENV_EOF
MONGO_URI=$${MONGO_URI}
DB_NAME=$${DB_NAME}
JWT_SECRET_KEY=$${JWT_SECRET_KEY}
ENABLE_CACHE=$${ENABLE_CACHE}
ENV_EOF

chown root:root "$APP_DIR/.env"
chmod 0600 "$APP_DIR/.env"

# Keep the image reference separate from the application environment.
IMAGE="$${AWS_ACCOUNT_ID}.dkr.ecr.$${AWS_REGION}.amazonaws.com/$${ECR_REPOSITORY}:$${IMAGE_TAG}"

cat > "$APP_DIR/.compose.env" <<ENV_EOF
IMAGE=$${IMAGE}
ENV_EOF

chown root:root "$APP_DIR/.compose.env"
chmod 0600 "$APP_DIR/.compose.env"

# Determine the MongoDB host and wait for its TCP port.
MONGO_HOST="$${MONGO_URI#*@}"
MONGO_HOST="$${MONGO_HOST%%:*}"

if [[ -z "$${MONGO_HOST}" ]]; then
    echo "ERROR: Could not determine MongoDB hostname."
    exit 1
fi

echo "Waiting for MongoDB at $MONGO_HOST:27017..."

MONGO_READY=false

for attempt in $(seq 1 60); do
    if timeout 5 bash -c "</dev/tcp/$MONGO_HOST/27017" 2>/dev/null; then
        MONGO_READY=true
        echo "MongoDB is accepting TCP connections."
        break
    fi

    echo "MongoDB not ready. Attempt $attempt/60."
    sleep 10
done

if [[ "$MONGO_READY" != true ]]; then
    echo "ERROR: MongoDB did not become reachable within 10 minutes."
    exit 1
fi

# Authenticate with Amazon ECR and pull the application image.
aws ecr get-login-password --region "$AWS_REGION" |
    docker login \
        --username AWS \
        --password-stdin \
        "$${AWS_ACCOUNT_ID}.dkr.ecr.$${AWS_REGION}.amazonaws.com"

docker pull "$IMAGE"

# Write the AWS-specific Docker Compose configuration.
cat > "$APP_DIR/compose.yaml" <<'COMPOSE_EOF'
name: muchtodo-aws

services:
  backend:
    image: $${IMAGE:?IMAGE must be supplied by the deployment environment}
    container_name: muchtodo-api
    env_file:
      - .env
    environment:
      PORT: "8080"
      JWT_EXPIRATION_HOURS: "72"
      LOG_LEVEL: INFO
      LOG_FORMAT: json
    ports:
      - "8080:8080"
    healthcheck:
      test:
        - CMD
        - wget
        - -q
        - -O
        - /dev/null
        - http://127.0.0.1:8080/health
      interval: 30s
      timeout: 5s
      retries: 3
      start_period: 20s
    restart: unless-stopped
    init: true
COMPOSE_EOF

chmod 0644 "$APP_DIR/compose.yaml"

# Roll back to the previous container if deployment fails.
rollback() {
    local status=$?
    trap - EXIT

    if [[ "$DEPLOYMENT_SUCCEEDED" != true ]]; then
        echo "Deployment did not complete successfully."

        if [[ "$COMPOSE_DEPLOY_STARTED" == true ]]; then
            docker compose \
                --env-file "$APP_DIR/.compose.env" \
                -f "$APP_DIR/compose.yaml" \
                down || true
        fi

        if [[ -n "$PREVIOUS_CONTAINER" ]] &&
           docker inspect "$PREVIOUS_CONTAINER" >/dev/null 2>&1; then

            if ! docker inspect muchtodo-api >/dev/null 2>&1; then
                docker rename "$PREVIOUS_CONTAINER" muchtodo-api || true
                docker start muchtodo-api || true
                echo "Previous backend container restoration attempted."
            else
                echo "WARNING: A container named muchtodo-api still exists."
                echo "Previous container remains named $PREVIOUS_CONTAINER."
            fi
        fi
    fi

    exit "$status"
}

trap rollback EXIT

# Preserve the existing backend container before deploying.
if docker inspect muchtodo-api >/dev/null 2>&1; then
    if docker inspect muchtodo-api-previous >/dev/null 2>&1; then
        echo "ERROR: muchtodo-api-previous already exists."
        echo "Resolve the previous deployment state before continuing."
        exit 1
    fi

  docker rename muchtodo-api muchtodo-api-previous
PREVIOUS_CONTAINER="muchtodo-api-previous"

docker stop "$PREVIOUS_CONTAINER"
fi

# Deploy using Docker Compose.
COMPOSE_DEPLOY_STARTED=true

docker compose \
    --env-file "$APP_DIR/.compose.env" \
    -f "$APP_DIR/compose.yaml" \
    up -d

# Wait for the application health check to pass.
for attempt in $(seq 1 30); do
    HEALTH_STATUS="$(docker inspect \
        --format '{{.State.Health.Status}}' muchtodo-api 2>/dev/null || true)"

    echo "Backend health status: $${HEALTH_STATUS:-not available}"

    if [[ "$${HEALTH_STATUS}" == "healthy" ]]; then
        echo "MuchToDo backend is healthy."
        break
    fi

    sleep 10
done

HEALTH_STATUS="$(docker inspect \
    --format '{{.State.Health.Status}}' muchtodo-api 2>/dev/null || true)"

if [[ "$${HEALTH_STATUS}" != "healthy" ]]; then
    echo "ERROR: MuchToDo backend failed its health check."
    docker logs muchtodo-api || true
    exit 1
fi

# Remove the old container only after the replacement is healthy.
if [[ -n "$PREVIOUS_CONTAINER" ]]; then
    docker rm -f "$PREVIOUS_CONTAINER" ||
        echo "WARNING: Previous container could not be removed."
fi

DEPLOYMENT_SUCCEEDED=true
trap - EXIT

echo "MuchToDo backend bootstrap completed successfully."