#!/bin/sh

echo "Starting backup process..."

# Variables
BACKUP_DIR="/backups"
TIMESTAMP=$(date +"%Y%m%d%H%M%S")
BACKUP_FILE="$BACKUP_DIR/db_backup_$TIMESTAMP.sql"
POSTGRES_PORT="${POSTGRES_PORT:-5432}"  # Default to 5432 if not set

# Ensure the backup directory exists
mkdir -p $BACKUP_DIR

# Set the environment variables for the database connection
export PGPASSWORD=$POSTGRES_PASSWORD

# Perform the backup
echo "Creating backup file..."
pg_dump -U $POSTGRES_USER -h $POSTGRES_HOST -p $POSTGRES_PORT -F p -b -v -f $BACKUP_FILE $POSTGRES_DB

# Check if the backup was successful
if [ $? -eq 0 ]; then
  echo "Backup successful: $BACKUP_FILE"
else
  echo "Backup failed"
  exit 1
fi

# Check if encryption is enabled
if [ "$ENCRYPTION_ENABLED" = "true" ]; then
  if [ -z "$ENCRYPTION_PASSWORD" ]; then
    echo "Encryption password is not set. Please set ENCRYPTION_PASSWORD."
    exit 1
  fi

  echo "Encrypting the backup file..."
  openssl enc -aes-256-cbc -salt -pbkdf2 -in "$BACKUP_FILE" -out "${BACKUP_FILE}.enc" -k "$ENCRYPTION_PASSWORD"
  
  if [ $? -eq 0 ]; then
    echo "Encryption successful: ${BACKUP_FILE}.enc"
    # Remove the unencrypted backup file
    rm "$BACKUP_FILE"
    # Update BACKUP_FILE to point to the encrypted file
    BACKUP_FILE="${BACKUP_FILE}.enc"
  else
    echo "Encryption failed"
    exit 1
  fi
fi

# Call the upload script
/scripts/upload.sh "$BACKUP_FILE"