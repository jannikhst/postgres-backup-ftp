#!/bin/sh

echo "Starting restore process..."

# Variablen
BACKUP_DIR="/downloaded-backups"

# Funktion zum URL-Encodieren
urlencode() {
  local input="$1"
  local output=""
  local i
  local c

  for i in $(seq 0 $((${#input} - 1))); do
    c=$(printf "%s" "${input:$i:1}")
    case "$c" in
      [a-zA-Z0-9.~_-]) output="$output$c" ;;
      *) output="$output$(printf '%%%02X' "'$c")" ;;
    esac
  done

  echo "$output"
}

# Aufbau der FTP-URL
ENCODED_FTP_USER=$(urlencode "$FTP_USER")
ENCODED_FTP_PASS=$(urlencode "$FTP_PASS")
ENCODED_FTP_HOST=$(urlencode "$FTP_HOST")

FTP_URL="ftp://$ENCODED_FTP_USER:$ENCODED_FTP_PASS@$ENCODED_FTP_HOST/$FTP_PATH/"

echo "Will attempt download from: $FTP_URL"

# Überprüfung, ob FTP_SSL auf "true" gesetzt ist
FTP_SSL_OPTION=""
if [ "$FTP_SSL" = "true" ]; then
  FTP_SSL_OPTION="--ftp-ssl"
fi

# Liste der Backups abrufen und das neueste auswählen
LATEST_BACKUP=$(curl -s $FTP_SSL_OPTION --list-only "$FTP_URL" | sort | tail -n 1)
BACKUP_FILE="$BACKUP_DIR/$LATEST_BACKUP"

# Bestätigung vom Benutzer einholen
echo "The latest backup is: $LATEST_BACKUP"
read -p "Do you want to restore this backup? WARNING: This will DROP and RECREATE your database! (yes/N): " CONFIRMATION

if [ "$CONFIRMATION" != "yes" ]; then
  echo "Restore cancelled."
  exit 0
fi

# Sicherstellen, dass das Backup-Verzeichnis existiert
mkdir -p $BACKUP_DIR

# Neuestes Backup herunterladen
echo "Downloading the latest backup: $LATEST_BACKUP"
curl -o "$BACKUP_FILE" "$FTP_URL$LATEST_BACKUP" $FTP_SSL_OPTION

# Überprüfen, ob der Download erfolgreich war
if [ $? -eq 0 ]; then
  echo "Download successful: $BACKUP_FILE"
else
  echo "Download failed"
  exit 1
fi

# Überprüfung, ob Verschlüsselung aktiviert ist
if [ "$ENCRYPTION_ENABLED" = "true" ]; then
  if [ -z "$ENCRYPTION_PASSWORD" ]; then
    echo "Encryption password is not set. Please set ENCRYPTION_PASSWORD."
    exit 1
  fi

  echo "Decrypting the backup file..."
  DECRYPTED_BACKUP_FILE="${BACKUP_FILE%.enc}"

  openssl enc -d -aes-256-cbc -pbkdf2 -in "$BACKUP_FILE" -out "$DECRYPTED_BACKUP_FILE" -k "$ENCRYPTION_PASSWORD"

  if [ $? -eq 0 ]; then
    echo "Decryption successful: $DECRYPTED_BACKUP_FILE"
    # Aktualisiere BACKUP_FILE auf die entschlüsselte Datei
    BACKUP_FILE="$DECRYPTED_BACKUP_FILE"
  else
    echo "Decryption failed"
    exit 1
  fi
fi

# Setze die Umgebungsvariable für die Datenbankverbindung
export PGPASSWORD=$POSTGRES_PASSWORD

# Die Datenbank droppen und neu erstellen
echo "Dropping and recreating the database..."

psql -U $POSTGRES_USER -h $POSTGRES_HOST -d postgres -c "DROP DATABASE $POSTGRES_DB;"
if [ $? -ne 0 ]; then
  echo "Failed to drop the database."
  exit 1
fi

psql -U $POSTGRES_USER -h $POSTGRES_HOST -d postgres -c "CREATE DATABASE $POSTGRES_DB WITH OWNER $POSTGRES_USER;"
if [ $? -ne 0 ]; then
  echo "Failed to create the database."
  exit 1
fi

echo "Database dropped and recreated successfully."

# Default to 5432 if not set
POSTGRES_PORT="${POSTGRES_PORT:-5432}"

# Backup wiederherstellen
echo "Restoring the backup..."
psql -U $POSTGRES_USER -h $POSTGRES_HOST -p $POSTGRES_PORT -d $POSTGRES_DB -f "$BACKUP_FILE"

# Überprüfen, ob die Wiederherstellung erfolgreich war
if [ $? -eq 0 ]; then
  echo "Restore successful"
else
  echo "Restore failed"
  exit 1
fi