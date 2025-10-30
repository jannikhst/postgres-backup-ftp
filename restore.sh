#!/bin/sh

echo "Starting restore process..."

# Variables
BACKUP_DIR="/downloaded-backups"

# Function to URL-encode input
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

# Check if POSTGRES_DB is set
if [ -z "$POSTGRES_DB" ]; then
  echo "Error: POSTGRES_DB environment variable is not set."
  exit 1
fi

# Present database selection to the user
echo "Please select a database to restore:"
i=1
# Use tr to handle comma-separated list and read into an array-like structure for sh
for db in $(echo $POSTGRES_DB | tr ',' ' '); do
  echo "$i) $db"
  i=$(expr $i + 1)
done

read -p "Enter the number of the database: " DB_CHOICE

# Get the selected database name
SELECTED_DB_NAME=$(echo $POSTGRES_DB | tr ',' ' ' | cut -d' ' -f$DB_CHOICE)

if [ -z "$SELECTED_DB_NAME" ]; then
  echo "Invalid selection. Exiting."
  exit 1
fi

echo "You have selected to restore: $SELECTED_DB_NAME"

# Build FTP URL
ENCODED_FTP_PASS=$(urlencode "$FTP_PASS")
FTP_URL="ftp://$FTP_USER:$ENCODED_FTP_PASS@$FTP_HOST/$FTP_PATH/"

echo "Will attempt download from: ftp://$FTP_USER:XXXXXX@$FTP_HOST/$FTP_PATH/"

# Check if FTP_SSL is set to "true"
FTP_SSL_OPTION=""
if [ "$FTP_SSL" = "true" ]; then
  FTP_SSL_OPTION="--ftp-ssl"
fi

# List backups for the selected database and find the latest one
echo "Searching for the latest backup for '$SELECTED_DB_NAME'..."
LATEST_BACKUP=$(curl -s $FTP_SSL_OPTION --list-only "$FTP_URL" | grep "^${SELECTED_DB_NAME}_backup_" | sort | tail -n 1)

if [ -z "$LATEST_BACKUP" ]; then
  echo "No backup found for database '$SELECTED_DB_NAME'."
  exit 1
fi

BACKUP_FILE="$BACKUP_DIR/$LATEST_BACKUP"

# Get confirmation from the user
echo "The latest backup is: $LATEST_BACKUP"
read -p "Do you want to restore this backup? WARNING: This will DROP and RECREATE the database '$SELECTED_DB_NAME'! (yes/N): " CONFIRMATION

if [ "$CONFIRMATION" != "yes" ]; then
  echo "Restore cancelled."
  exit 0
fi

# Ensure the backup directory exists
mkdir -p $BACKUP_DIR

# Download the latest backup
echo "Downloading the latest backup: $LATEST_BACKUP"
curl -o "$BACKUP_FILE" "$FTP_URL$LATEST_BACKUP" $FTP_SSL_OPTION

# Check if the download was successful
if [ $? -eq 0 ]; then
  echo "Download successful: $BACKUP_FILE"
else
  echo "Download failed"
  exit 1
fi

# Check if encryption is enabled
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
    # Update BACKUP_FILE to the decrypted file
    BACKUP_FILE="$DECRYPTED_BACKUP_FILE"
  else
    echo "Decryption failed"
    exit 1
  fi
fi

# Set the environment variable for the database connection
export PGPASSWORD=$POSTGRES_PASSWORD

# Drop and recreate the database
echo "Dropping and recreating the database '$SELECTED_DB_NAME'..."

psql -U $POSTGRES_USER -h $POSTGRES_HOST -d postgres -c "DROP DATABASE IF EXISTS \"$SELECTED_DB_NAME\";"
if [ $? -ne 0 ]; then
  echo "Warning: Failed to drop the database. It might not have existed, continuing..."
fi

psql -U $POSTGRES_USER -h $POSTGRES_HOST -d postgres -c "CREATE DATABASE \"$SELECTED_DB_NAME\" WITH OWNER $POSTGRES_USER;"
if [ $? -ne 0 ]; then
  echo "Failed to create the database."
  exit 1
fi

echo "Database dropped and recreated successfully."

# Restore the backup
echo "Restoring the backup..."
psql -U $POSTGRES_USER -h $POSTGRES_HOST -d "$SELECTED_DB_NAME" -f "$BACKUP_FILE"

# Check if the restore was successful
if [ $? -eq 0 ]; then
  echo "Restore successful for database '$SELECTED_DB_NAME'"
else
  echo "Restore failed for database '$SELECTED_DB_NAME'"
  exit 1
fi