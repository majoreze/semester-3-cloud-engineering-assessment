#!/bin/bash

# Stop on errors, unset variables and failed pipelines.
set -euo pipefail

# Send output to the EC2 console and bootstrap log.
exec > >(tee -a /var/log/mongodb-bootstrap.log | logger -t mongodb-bootstrap -s 2>/dev/console) 2>&1

echo "Starting MongoDB server provisioning..."

# --------------------------------------------------
# 1. Infrastructure values supplied by Terraform
# --------------------------------------------------

AWS_REGION="${aws_region}"
MONGODB_EBS_VOLUME_ID="${mongodb_ebs_volume_id}"

MONGODB_DATA_DIR="/data/mongodb"
MONGODB_CONFIG_DIR="/opt/mongodb"
MONGO_CONTAINER="mongodb"
MONGO_IMAGE="mongo:8.0"

# --------------------------------------------------
# 2. Install required packages and start Docker
# --------------------------------------------------

echo "Updating Amazon Linux packages..."
dnf update -y

echo "Installing Docker, AWS CLI and EBS utilities..."
dnf install -y docker nvme-cli xfsprogs util-linux amazon-ec2-utils awscli-2 curl

systemctl enable docker
systemctl start docker

echo "Retrieving MongoDB instance private IP using IMDSv2..."

IMDS_BASE=$(printf '\150\164\164\160\072\057\057\061\066\071\056\062\065\064\056\061\066\071\056\062\065\064')

if ! IMDS_TOKEN=$(curl --fail --silent --show-error --max-time 5 -X PUT "$IMDS_BASE/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600"); then
    echo "ERROR: Unable to obtain IMDSv2 token."
    exit 1
fi

if ! MONGODB_PRIVATE_IP=$(curl --fail --silent --show-error --max-time 5 -H "X-aws-ec2-metadata-token: $IMDS_TOKEN" "$IMDS_BASE/latest/meta-data/local-ipv4"); then
    echo "ERROR: Unable to retrieve MongoDB private IP."
    exit 1
fi

if [[ -z "$MONGODB_PRIVATE_IP" ]]; then
    echo "ERROR: MongoDB private IP is empty."
    exit 1
fi

echo "MongoDB private IP retrieved: $MONGODB_PRIVATE_IP"


echo "Docker service started."

# --------------------------------------------------
# 3. Verify AWS CLI
# --------------------------------------------------

if ! command -v aws >/dev/null 2>&1; then
    echo "ERROR: AWS CLI installation failed."
    exit 1
fi

echo "AWS CLI is available: $(aws --version)"

# --------------------------------------------------
# 4. Retrieve MongoDB secrets from AWS SSM
# --------------------------------------------------

echo "Retrieving MongoDB configuration from Parameter Store..."

MONGO_ROOT_USERNAME=$(aws ssm get-parameter \
    --name "/muchtodo/mongodb/root-username" \
    --with-decryption \
    --region "$AWS_REGION" \
    --query "Parameter.Value" \
    --output text)

MONGO_ROOT_PASSWORD=$(aws ssm get-parameter \
    --name "/muchtodo/mongodb/root-password" \
    --with-decryption \
    --region "$AWS_REGION" \
    --query "Parameter.Value" \
    --output text)

MONGO_REPLICA_KEY=$(aws ssm get-parameter \
    --name "/muchtodo/mongodb/replica-key" \
    --with-decryption \
    --region "$AWS_REGION" \
    --query "Parameter.Value" \
    --output text)

if [[ -z "$MONGO_ROOT_USERNAME" || \
      -z "$MONGO_ROOT_PASSWORD" || \
      -z "$MONGO_REPLICA_KEY" ]]; then
    echo "ERROR: One or more MongoDB secrets are missing."
    exit 1
fi

echo "MongoDB secrets retrieved successfully."

# --------------------------------------------------
# 5. Prepare the MongoDB replica-set keyfile
# --------------------------------------------------

echo "Preparing MongoDB keyfile..."

mkdir -p "$MONGODB_CONFIG_DIR"

printf '%s' "$MONGO_REPLICA_KEY" > "$MONGODB_CONFIG_DIR/mongodb.key"

chown 999:999 "$MONGODB_CONFIG_DIR/mongodb.key"
chmod 400 "$MONGODB_CONFIG_DIR/mongodb.key"

echo "MongoDB keyfile created and protected."

# --------------------------------------------------
# 6. Identify and mount the persistent EBS volume
# --------------------------------------------------

echo "Waiting for MongoDB EBS volume: $MONGODB_EBS_VOLUME_ID"

DEVICE=""

for attempt in $(seq 1 30); do
    for candidate in /dev/nvme*n1; do
        [ -b "$candidate" ] || continue

        VOLUME_ID=$(/sbin/ebsnvme-id "$candidate" -v 2>/dev/null \
            | awk '/Volume ID:/ {print $3}')

        if [ "$VOLUME_ID" = "$MONGODB_EBS_VOLUME_ID" ]; then
            DEVICE="$candidate"
            break 2
        fi
    done

    echo "Waiting for EBS device. Attempt $attempt of 30..."
    sleep 10
done

if [ -z "$DEVICE" ]; then
    echo "ERROR: Expected MongoDB EBS volume was not found."
    exit 1
fi

echo "Identified MongoDB EBS device: $DEVICE"

# Detect an existing filesystem.
FILESYSTEM=$(blkid -o value -s TYPE "$DEVICE" || true)

if [ -z "$FILESYSTEM" ]; then

    # Never format a device containing an existing filesystem signature.
    if wipefs -n --noheadings "$DEVICE" | grep -q .; then
        echo "ERROR: Unrecognised existing disk signature. Refusing to format."
        exit 1
    fi

    echo "Blank EBS volume detected. Creating XFS filesystem..."
    mkfs.xfs "$DEVICE"
    FILESYSTEM="xfs"

else
    echo "Existing filesystem detected: $FILESYSTEM"

    if [ "$FILESYSTEM" != "xfs" ]; then
        echo "ERROR: Expected an XFS filesystem, but found '$FILESYSTEM'."
        echo "Refusing to mount or modify the existing filesystem."
        exit 1
    fi
fi

mkdir -p "$MONGODB_DATA_DIR"

UUID=$(blkid -s UUID -o value "$DEVICE")

if [ -z "$UUID" ]; then
    echo "ERROR: Could not determine EBS filesystem UUID."
    exit 1
fi

# Add the volume to fstab only once.
if ! awk -v uuid="$UUID" '$1 == "UUID=" uuid {found=1} END {exit !found}' /etc/fstab; then
    echo "UUID=$UUID $MONGODB_DATA_DIR xfs defaults,nofail 0 2" >> /etc/fstab
fi

# Mount only when it is not already mounted.
if ! mountpoint -q "$MONGODB_DATA_DIR"; then
    mount "$MONGODB_DATA_DIR"
fi

# Confirm the expected EBS filesystem is mounted.
MOUNTED_UUID=$(findmnt -n -o UUID --target "$MONGODB_DATA_DIR")

if [ "$MOUNTED_UUID" != "$UUID" ]; then
    echo "ERROR: MongoDB data directory is not backed by the expected EBS volume."
    exit 1
fi

echo "MongoDB EBS storage mounted successfully."
df -h "$MONGODB_DATA_DIR"

# Ensure the MongoDB container user can write to the data directory.
chown 999:999 "$MONGODB_DATA_DIR"
chmod 700 "$MONGODB_DATA_DIR"

# --------------------------------------------------
# 7. Pull and start MongoDB
# --------------------------------------------------

echo "Pulling MongoDB image: $MONGO_IMAGE"
docker pull "$MONGO_IMAGE"

# Remove an existing container if this bootstrap is rerun.
# The persistent EBS data is not removed.
if docker container inspect "$MONGO_CONTAINER" >/dev/null 2>&1; then
    echo "Removing existing MongoDB container..."
    docker rm -f "$MONGO_CONTAINER"
fi

echo "Starting MongoDB container..."

docker run -d \
    --name "$MONGO_CONTAINER" \
    --restart unless-stopped \
    --publish "$MONGODB_PRIVATE_IP:27017:27017" \
    --mount type=bind,source="$MONGODB_DATA_DIR",target=/data/db \
    --mount type=bind,source="$MONGODB_CONFIG_DIR/mongodb.key",target=/etc/mongodb.key,readonly \
    -e MONGO_INITDB_ROOT_USERNAME="$MONGO_ROOT_USERNAME" \
    -e MONGO_INITDB_ROOT_PASSWORD="$MONGO_ROOT_PASSWORD" \
    "$MONGO_IMAGE" \
    --replSet rs0 \
    --bind_ip_all \
    --keyFile /etc/mongodb.key

echo "MongoDB container started."

# --------------------------------------------------
# 8. Wait for authenticated MongoDB readiness
# --------------------------------------------------

echo "Waiting for MongoDB to become ready..."

MONGO_READY=false

for attempt in $(seq 1 60); do

    if docker exec "$MONGO_CONTAINER" mongosh \
        --quiet \
        --username "$MONGO_ROOT_USERNAME" \
        --password "$MONGO_ROOT_PASSWORD" \
        --authenticationDatabase admin \
        --eval 'db.adminCommand({ping: 1})' >/dev/null 2>&1; then

        MONGO_READY=true
        break
    fi

    echo "MongoDB is not ready yet. Attempt $attempt of 60..."
    sleep 5
done

if [ "$MONGO_READY" != "true" ]; then
    echo "ERROR: MongoDB did not become ready within five minutes."
    docker logs "$MONGO_CONTAINER"
    exit 1
fi

echo "MongoDB is accepting authenticated connections."

# --------------------------------------------------
# 9. Initialise the single-node replica set
# --------------------------------------------------

echo "Checking MongoDB replica-set configuration..."

docker exec "$MONGO_CONTAINER" mongosh \
    --quiet \
    --username "$MONGO_ROOT_USERNAME" \
    --password "$MONGO_ROOT_PASSWORD" \
    --authenticationDatabase admin \
    --eval "try {
        rs.status();
        print('Replica set is already configured.');
    } catch (error) {
        if (error.code === 94) {
            rs.initiate({
                _id: 'rs0',
                members: [
                    {_id: 0, host: '$${MONGODB_PRIVATE_IP}:27017'}
                ]
            });
        } else {
            throw error;
        }
    }"

# --------------------------------------------------
# 10. Wait for the replica set to become PRIMARY
# --------------------------------------------------

echo "Waiting for MongoDB replica set to become PRIMARY..."

REPLICA_READY=false

for attempt in $(seq 1 60); do

    if docker exec "$MONGO_CONTAINER" mongosh \
        --quiet \
        --username "$MONGO_ROOT_USERNAME" \
        --password "$MONGO_ROOT_PASSWORD" \
        --authenticationDatabase admin \
        --eval 'if (db.hello().isWritablePrimary) { quit(0); } else { quit(1); }' >/dev/null 2>&1; then

        REPLICA_READY=true
        break
    fi

    echo "Replica set is not PRIMARY yet. Attempt $attempt of 60..."
    sleep 5
done

if [ "$REPLICA_READY" != "true" ]; then
    echo "ERROR: MongoDB replica set did not become PRIMARY within five minutes."
    docker logs "$MONGO_CONTAINER"
    exit 1
fi

echo "MongoDB replica set is configured and PRIMARY."

echo "MongoDB server provisioning completed successfully."
