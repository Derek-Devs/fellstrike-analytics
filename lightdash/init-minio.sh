#!/bin/sh
# Starts MinIO, the S3-style storage Lightdash keeps query results and exports in, and makes its bucket. Adapted from
# Lightdash's own docker/init-minio.sh (MIT licence). Files expire after a day, since they are only caches.
set -e

minio server /data &

until mc alias set local http://localhost:9000 "$MINIO_ROOT_USER" "$MINIO_ROOT_PASSWORD" >/dev/null 2>&1; do
  sleep 1
done

mc mb -p local/lightdash >/dev/null 2>&1 || true
mc ilm rule rm --all --force local/lightdash >/dev/null 2>&1 || true
mc ilm rule add --expire-days 1 local/lightdash >/dev/null
echo "MinIO is ready with the lightdash bucket"

wait
