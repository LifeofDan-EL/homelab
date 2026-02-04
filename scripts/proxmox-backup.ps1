# === Proxmox HDD → Laptop SSD backup (date-stamped) ===
$Key = "$env:USERPROFILE\.ssh\id_ed25519"                
$Src = "root@192.168.8.11:/mnt/pve/Storage/dump/*"           
$BaseDst = "F:/Backup/Proxmox backup"                     
$Log = Join-Path $BaseDst "backup-log.txt"

# Create dated destination folder
$Today = Get-Date -Format "yyyy-MM-dd"
$Dst = Join-Path $BaseDst $Today
New-Item -ItemType Directory -Force -Path $Dst | Out-Null

# Logging helper
function Log($msg) {
  $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
  "[$ts] $msg" | Out-File -FilePath $Log -Append -Encoding utf8
}

try {
  Log "Starting sync to '$Dst'..."
  # Accept host key automatically on first run; use scp with key
  scp -i $Key -o StrictHostKeyChecking=accept-new -r $Src $Dst
  if ($LASTEXITCODE -ne 0) { throw "scp exited with code $LASTEXITCODE" }
  Log "Sync completed successfully."
}
catch {
  Log "ERROR: $_"
  exit 1
}
