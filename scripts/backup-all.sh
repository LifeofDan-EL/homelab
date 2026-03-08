#!/bin/bash

# --- 1. LOAD SECRETS ------------------------------------------
SECRET_FILE="/root/.backup_secrets.env"

if [ -f "$SECRET_FILE" ]; then
    source "$SECRET_FILE"
else
    echo "Error: Secret file not found at $SECRET_FILE"
    exit 1
fi

# --- 2. CONFIGURATION -----------------------------------------
BACKUP_ROOT="/opt/backup-staging"
TODAY=$(date +"%Y-%m-%d")
NOW=$(date +"%H-%M-%S")
TEMP_DIR="$BACKUP_ROOT/$TODAY/$NOW"
RCLONE_DEST="$REMOTE_NAME:$BUCKET_NAME"
EXIT_CODE=0

mkdir -p "$TEMP_DIR"
echo "[$(date)] Starting Stack-Organized Backup..."
echo "   Staging Directory: $TEMP_DIR"

# --- 3. HELPER FUNCTIONS --------------------------------------

backup_volume() {
    local VOL_NAME=$1
    local DEST_DIR=$2
    mkdir -p "$DEST_DIR"
    if docker volume inspect "$VOL_NAME" > /dev/null 2>&1; then
        echo -n "   $VOL_NAME... "
        docker run --rm \
            -v "$VOL_NAME":/source \
            -v "$DEST_DIR":/backup \
            alpine tar -czf "/backup/${VOL_NAME}.tar.gz" -C /source .
        if [ $? -eq 0 ]; then echo "OK"; else echo "FAILED"; EXIT_CODE=1; fi
    else
        echo "   Volume $VOL_NAME not found (Skipping)"
    fi
}

backup_host_dir() {
    local SRC_PATH=$1
    local DEST_DIR=$2
    local ARCHIVE_NAME=$3
    mkdir -p "$DEST_DIR"
    if [ -d "$SRC_PATH" ]; then
        echo -n "   $SRC_PATH... "
        tar -czf "$DEST_DIR/${ARCHIVE_NAME}.tar.gz" -C "$SRC_PATH" .
        if [ $? -eq 0 ]; then echo "OK"; else echo "FAILED"; EXIT_CODE=1; fi
    else
        echo "   Directory $SRC_PATH not found (Skipping)"
    fi
}

stop_containers() {
    for c in "$@"; do docker stop "$c" > /dev/null 2>&1; done
}

start_containers() {
    for c in "$@"; do docker start "$c" > /dev/null 2>&1; done
}

# =============================================================
# --- 4. STACK BACKUPS ----------------------------------------
# =============================================================

# -- 4A. QDRANT -----------------------------------------------
echo ""
echo "[$(date)] [1/4] Backing up Qdrant Stack..."
stop_containers "qdrant"

backup_volume "n8n-stack_qdrant_data"   "$TEMP_DIR/qdrant"

start_containers "qdrant"

# -- 4B. SURE STACK -------------------------------------------
echo ""
echo "[$(date)] [2/4] Backing up Sure Stack..."
stop_containers "sure_web" "sure_worker" "sure_db" "sure_redis" "sure_backup"

backup_volume "sure_app_postgres_data"  "$TEMP_DIR/sure"
backup_volume "sure_app_app_storage"    "$TEMP_DIR/sure"
backup_volume "sure_app_redis_data"     "$TEMP_DIR/sure"
backup_host_dir "/opt/sure-data/backups/last" "$TEMP_DIR/sure" "sure_local_backups"

start_containers "sure_db" "sure_redis" "sure_web" "sure_worker" "sure_backup"

# -- 4C. SPEEDTEST TRACKER ------------------------------------
echo ""
echo "[$(date)] [3/4] Backing up Speedtest Tracker Stack..."
stop_containers "speedtest-tracker"

backup_host_dir "/opt/stacks/speedtest/data" "$TEMP_DIR/speedtest" "speedtest_data"

start_containers "speedtest-tracker"

# -- 4D. N8N SOLAR POSTGRES -----------------------------------
echo ""
echo "[$(date)] [4/4] Backing up N8N Solar Postgres..."
stop_containers "solar_db"

backup_volume "n8n-stack_postgres_data" "$TEMP_DIR/n8n_solar"

start_containers "solar_db"

# =============================================================
# --- 5. VERIFY -----------------------------------------------
# =============================================================
echo ""
echo "[$(date)] Verifying staged files..."
STACK_COUNT=$(ls -1 "$TEMP_DIR" | wc -l)
if [ "$STACK_COUNT" -eq 0 ]; then
    echo "CRITICAL ERROR: Staging directory is empty!"
    exit 1
fi

echo "   Backed up $STACK_COUNT stacks:"
for stack_dir in "$TEMP_DIR"/*/; do
    stack_name=$(basename "$stack_dir")
    file_count=$(ls -1 "$stack_dir" | wc -l)
    echo "      $stack_name - $file_count file(s)"
done

# --- 6. PACKAGE & ENCRYPT ------------------------------------
echo ""
echo "[$(date)] Creating master archive..."
MASTER_TAR="$BACKUP_ROOT/full_backup_$TODAY.tar"
MASTER_GPG="$BACKUP_ROOT/full_backup_$TODAY.tar.gpg"

tar -cf "$MASTER_TAR" -C "$BACKUP_ROOT/$TODAY" "$NOW" 2> /tmp/tar_error.log
if [ $? -ne 0 ]; then
    echo "TAR FAILED! Check /tmp/tar_error.log"
    cat /tmp/tar_error.log
    exit 1
fi

echo "[$(date)] Encrypting..."
gpg --batch --yes --passphrase-fd 0 --symmetric --cipher-algo AES256 \
    -o "$MASTER_GPG" "$MASTER_TAR" <<< "$BACKUP_ENCRYPTION_PASS"

if [ $? -ne 0 ]; then
    echo "GPG FAILED!"
    exit 1
fi

FINAL_SIZE=$(stat -c%s "$MASTER_GPG")
echo "   Encrypted archive size: $(numfmt --to=iec-i --suffix=B $FINAL_SIZE)"

# --- 7. UPLOAD & CLEANUP -------------------------------------
if [ "$FINAL_SIZE" -lt 1000 ]; then
    echo "WARNING: File size suspiciously small. Skipping upload."
    EXIT_CODE=1
else
    echo "[$(date)] Uploading to R2..."
    rclone copy "$MASTER_GPG" "$RCLONE_DEST/$TODAY" \
        --transfers 1 \
        --tpslimit 1 \
        --timeout 30m \
        --retries 10

    if [ $? -eq 0 ]; then
        echo "   Upload Successful"
        rm -rf "$BACKUP_ROOT/$TODAY"
        rm -f "$MASTER_TAR" "$MASTER_GPG"
        echo "[$(date)] Cleanup Complete"
    else
        echo "   Upload Failed"
        EXIT_CODE=1
    fi
fi

# --- 8. RETENTION CLEANUP ------------------------------------
echo ""
echo "[$(date)] Pruning old backups from R2 (keeping last 30 days)..."
RETENTION_DAYS=30
CUTOFF=$(date -d "$RETENTION_DAYS days ago" +"%Y-%m-%d")

rclone lsd "$RCLONE_DEST" | while read -r line; do
    DIR=$(echo "$line" | awk '{print $NF}')
    if [[ "$DIR" < "$CUTOFF" ]]; then
        echo "   Deleting old backup: $DIR"
        rclone purge "$RCLONE_DEST/$DIR"
    fi
done
echo "[$(date)] Retention cleanup done."

# --- 9. FINAL STATUS ------------------------------------------
echo ""
if [ "$EXIT_CODE" -eq 0 ]; then
    echo "[$(date)] ✅ Backup completed successfully."
else
    echo "[$(date)] ❌ Backup finished with errors."
fi