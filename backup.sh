#!/bin/sh

echo "Starting backup process..."

# Variables
BACKUP_DIR="/backups"

# Ensure the backup directory exists
mkdir -p $BACKUP_DIR

# Set the environment variables for the database connection
export PGPASSWORD=$POSTGRES_PASSWORD

# Loop through each database name in POSTGRES_DB (comma-separated)
for DB_NAME in $(echo $POSTGRES_DB | tr ',' ' '); do
  echo "Processing database: $DB_NAME"
  TIMESTAMP=$(date +"%Y%m%d%H%M%S")
  BACKUP_FILE="$BACKUP_DIR/${DB_NAME}_backup_$TIMESTAMP.sql"

  # Perform the backup
  echo "Creating backup file for $DB_NAME..."
  pg_dump -U $POSTGRES_USER -h $POSTGRES_HOST -F p -b -v -f "$BACKUP_FILE" "$DB_NAME"

  # Check if the backup was successful
  if [ $? -eq 0 ]; then
    echo "Backup successful: $BACKUP_FILE"
  else
    echo "Backup failed for database: $DB_NAME"
    continue # Continue to the next database
  fi

  # Check if encryption is enabled
  if [ "$ENCRYPTION_ENABLED" = "true" ]; then
    if [ -z "$ENCRYPTION_PASSWORD" ]; then
      echo "Encryption password is not set. Please set ENCRYPTION_PASSWORD."
      # We can't proceed with this file, so we skip to the next DB
      rm "$BACKUP_FILE" # Clean up unencrypted file
      continue
    fi

    ENCRYPTED_FILE="${BACKUP_FILE}.enc"
    echo "Encrypting the backup file..."
    openssl enc -aes-256-cbc -salt -pbkdf2 -in "$BACKUP_FILE" -out "$ENCRYPTED_FILE" -k "$ENCRYPTION_PASSWORD"
    
    if [ $? -eq 0 ]; then
      echo "Encryption successful: $ENCRYPTED_FILE"
      # Remove the unencrypted backup file
      rm "$BACKUP_FILE"
      # Call the upload script with the encrypted file
      /scripts/upload.sh "$ENCRYPTED_FILE"
    else
      echo "Encryption failed for $BACKUP_FILE"
      rm "$BACKUP_FILE" # Clean up unencrypted file
      continue # Continue to the next database
    fi
  else
    # Call the upload script with the unencrypted file
    /scripts/upload.sh "$BACKUP_FILE"
  fi
  echo "Finished processing database: $DB_NAME"
done

echo "All database backup processes finished."