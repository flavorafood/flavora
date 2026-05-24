#!/bin/bash
set -euo pipefail

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_NAME="flavora_mongo_${TIMESTAMP}"
BACKUP_DIR="/tmp/${BACKUP_NAME}"
ARCHIVE="${BACKUP_DIR}.tar.gz"

source /opt/flavora/.env

echo "[$(date)] Starting backup..."

docker exec flavora_mongo mongodump \
  --username="${MONGO_ROOT_USER}" \
  --password="${MONGO_ROOT_PASSWORD}" \
  --authenticationDatabase=admin \
  --db=flavora_food \
  --out="${BACKUP_DIR}"

tar -czf "${ARCHIVE}" -C /tmp "${BACKUP_NAME}"
rm -rf "${BACKUP_DIR}"

echo "[$(date)] Uploading to DO Spaces..."
s3cmd put "${ARCHIVE}" \
  "s3://${AWS_BUCKET_NAME}/mongodb/${BACKUP_NAME}.tar.gz" \
  --host="${AWS_REGION}.digitaloceanspaces.com" \
  --host-bucket="%(bucket)s.${AWS_REGION}.digitaloceanspaces.com" \
  --access_key="${S3_BUCKET_ACCESS_KEY}" \
  --secret_key="${S3_BUCKET_SECRET_ACCESS_KEY}"

# ৪৯ দিনের পুরানো backup delete করো
CUTOFF=$(date -d "49 days ago" +%Y%m%d)
s3cmd ls "s3://${AWS_BUCKET_NAME}/mongodb/" \
  --host="${AWS_REGION}.digitaloceanspaces.com" \
  --host-bucket="%(bucket)s.${AWS_REGION}.digitaloceanspaces.com" \
  --access_key="${S3_BUCKET_ACCESS_KEY}" \
  --secret_key="${S3_BUCKET_SECRET_ACCESS_KEY}" | while read -r line; do
    FILE=$(echo "$line" | awk '{print $4}')
    FILE_DATE=$(basename "$FILE" | grep -oP '\d{8}' | head -1)
    if [[ -n "$FILE_DATE" && "$FILE_DATE" -lt "$CUTOFF" ]]; then
      s3cmd del "$FILE" \
        --host="${AWS_REGION}.digitaloceanspaces.com" \
        --host-bucket="%(bucket)s.${AWS_REGION}.digitaloceanspaces.com" \
        --access_key="${S3_BUCKET_ACCESS_KEY}" \
        --secret_key="${S3_BUCKET_SECRET_ACCESS_KEY}"
      echo "Deleted: $FILE"
    fi
done

rm -f "${ARCHIVE}"
echo "[$(date)] Backup completed!"