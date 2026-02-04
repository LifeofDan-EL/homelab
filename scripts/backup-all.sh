#!/bin/bash

# --- 1. LOAD SECRETS ------------------------------------------
SECRET_FILE="/root/.backup_secrets.env"

if [ -f "$SECRET_FILE" ]; then
    source "$SECRET_FILE"
else
    echo "🚨 Error: Secret file not found at $SECRET_FILE"
    exit 1
fi

# --- 2. CONFIGURATION -----------------------------------------
BACKUP_ROOT="/opt/backup-staging"          
TODAY=$(date +"%Y-%m-%d")
NOW=$(date +"%H-%M-%S")
TEMP_DIR="$BACKUP_ROOT/$TODAY/$NOW"
RCLONE_DEST="$REMOTE_NAME:$BUCKET_NAME"
SURE_BACKUPS_PATH="/opt/sure-data/backups/last"

# --- 3. TARGETS -----------------------------------------------
VOLUMES_TO_BACKUP=(
    "n8n-stack_postgres_data"
    "n8n-stack_qdrant_data"
    "n8n-stack_redis_data"
    "n8n-stack_uptime_kuma_data"
    "portainer_data"
    "sure_app_postgres_data"
    "sure_app_app_storage"
    "sure_app_redis_data"
)

# Containers to pause briefly for data consistency
CONTAINERS_TO_STOP=(
    "n8n"
    "solar_db"
    "qdrant"
    "n8n_redis"
    "uptime_kuma"
    "sure_app"       
)

# --- 4. PREPARATION -------------------------------------------
rm -rf "$TEMP_DIR"
mkdir -p "$TEMP_DIR"

echo "[$(date)] 🚀 Starting Lightweight System Backup..."
echo "   📂 Staging Directory: $TEMP_DIR"

# --- 5. SAFETY STOP -------------------------------------------
echo "[$(date)] 🛑 Pausing databases..."
for container in "${CONTAINERS_TO_STOP[@]}"; do
    docker stop "$container" > /dev/null 2>&1
done

# --- 6. BACKUP EXECUTION --------------------------------------

# 6A. Backup Docker Volumes
echo "[$(date)] 📦 Backing up Docker Volumes..."

backup_volume() {
    local VOL_NAME=$1
    if docker volume inspect "$VOL_NAME" > /dev/null 2>&1; then
        echo -n "   📸 $VOL_NAME... "
        
        docker run --rm \
            -v "$VOL_NAME":/source \
            -v "$TEMP_DIR":/backup \
            alpine tar -czf "/backup/${VOL_NAME}.tar.gz" -C /source .
            
        if [ $? -eq 0 ]; then echo "✅ OK"; else echo "❌ FAILED"; fi
    else
        echo "⚠️  Volume $VOL_NAME not found (Skipping)"
    fi
}

for vol in "${VOLUMES_TO_BACKUP[@]}"; do
    backup_volume "$vol"
done

# 6B. Backup Host Directory
echo "[$(date)] 📂 Backing up Host Directory..."
if [ -d "$SURE_BACKUPS_PATH" ]; then
    tar -czf "$TEMP_DIR/sure_local_backups.tar.gz" -C "$SURE_BACKUPS_PATH" .
    echo "   ✅ Host backup created"
else
    echo "   ⚠️  Directory $SURE_BACKUPS_PATH not found"
fi

# --- 7. RESTART CONTAINERS ------------------------------------
echo "[$(date)] ▶️  Resuming containers..."
for container in "${CONTAINERS_TO_STOP[@]}"; do
    docker start "$container" > /dev/null 2>&1
done

# --- 8. VERIFICATION & ENCRYPTION -----------------------------
echo "[$(date)] 🔍 Verifying Staged Files..."

FILE_COUNT=$(ls -1 "$TEMP_DIR" | wc -l)
if [ "$FILE_COUNT" -eq 0 ]; then
    echo "🚨 CRITICAL ERROR: Staging directory is empty! Nothing to encrypt."
    exit 1
else
    echo "   ✅ Found $FILE_COUNT files to backup."
fi

# 1. Create TAR
echo "[$(date)] 📦 Creating Master Archive..."
MASTER_TAR="$BACKUP_ROOT/full_backup_$TODAY.tar"
MASTER_GPG="$BACKUP_ROOT/full_backup_$TODAY.tar.gpg"

tar -cf "$MASTER_TAR" -C "$BACKUP_ROOT/$TODAY" "$NOW" 2> /tmp/tar_error.log
if [ $? -ne 0 ]; then
    echo "🚨 TAR FAILED! Check /tmp/tar_error.log"
    cat /tmp/tar_error.log
    exit 1
fi

# 2. Encrypt TAR
echo "[$(date)] 🔒 Encrypting..."
gpg --batch --yes --passphrase-fd 0 --symmetric --cipher-algo AES256 \
    -o "$MASTER_GPG" "$MASTER_TAR" <<< "$BACKUP_ENCRYPTION_PASS"

if [ $? -ne 0 ]; then
    echo "🚨 GPG FAILED!"
    exit 1
fi

FINAL_SIZE=$(stat -c%s "$MASTER_GPG")
echo "   ✅ Encrypted archive size: $(numfmt --to=iec-i --suffix=B $FINAL_SIZE)"

# --- 9. UPLOAD & CLEANUP --------------------------------------
if [ "$FINAL_SIZE" -lt 1000 ]; then
    echo "⚠️  WARNING: File size is suspiciously small. Skipping upload."
else
    echo "[$(date)] ☁️  Uploading to R2 (Starlink Optimized)..."
    
    # STARLINK OPTIMIZED FLAGS
    rclone copy "$MASTER_GPG" "$RCLONE_DEST/$TODAY" \
        --transfers 1 \
        --tpslimit 1 \
        --timeout 30m \
        --retries 10
    
    if [ $? -eq 0 ]; then
        echo "   ✅ Upload Successful"
        rm -rf "$BACKUP_ROOT/$TODAY"
        rm -f "$MASTER_TAR" "$MASTER_GPG"
        echo "[$(date)] 🧹 Cleanup Complete"
    else
        echo "   ❌ Upload Failed"
    fi
fi

echo "[$(date)] 🏁 Done!"