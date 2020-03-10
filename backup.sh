#!/bin/bash

# Minecraft server automatic backup management script
# by Nicolas Chan
# modified by Martin Oyola
# further modified by Patrick Mischke
# MIT License
#
# Adapted for Minecraft servers running in a Docker Container with local folder as mounted volume, RCON enabled but not exposed.
# Should also still work using RCON via pass/port, for non docker installations. 
# Tested with itzg/minecraft-server image. 
# This file is available at https://raw.githubusercontent.com/Patschke/minecraft-backup/master/backup.sh
# 
# For most convenience, run automatically with cron.

# Default Configuration
DOCKER_CONTAINER="" # Name of Docker Container
USE_DOCKER=false # Use docker exec instead of RCON via port
RCON_PASS="" # RCON PASSWORD
RCON_PORT="25575" # RCON PORT
SERVER_WORLD="" # Server world directory
BACKUP_DIRECTORY="" # Directory to save backups in
MAX_BACKUPS=128 # -1 indicates unlimited
DELETE_METHOD="thin" # Choices: thin, sequential, none; sequential: delete oldest; thin: keep last 24 hourly, last 30 daily, and monthly (use with 1 hr cron interval)
COMPRESSION_ALGORITHM="gzip" # Leave empty for no compression
COMPRESSION_FILE_EXTENSION=".gz" # Leave empty for no compression; Precede with a . (for example: ".gz")
COMPRESSION_LEVEL=3 # Passed to the compression algorithm
ENABLE_CHAT_MESSAGES=false # Tell players in Minecraft chat about backup status
PREFIX="Backup" # Shows in the chat message
DEBUG=false # Enable debug messages
SUPPRESS_WARNINGS=false # Suppress warnings

# Other Variables (do not modify)
DATE_FORMAT="%F_%H-%M-%S"
TIMESTAMP=$(date +$DATE_FORMAT)

while getopts 'a:cd:e:f:hi:l:mn:o:p:qs:r:v' FLAG; do
  case $FLAG in
    a) COMPRESSION_ALGORITHM=$OPTARG ;;
    c) ENABLE_CHAT_MESSAGES=true ;;
    d) DELETE_METHOD=$OPTARG ;;
    e) COMPRESSION_FILE_EXTENSION=".$OPTARG" ;;
    f) TIMESTAMP=$OPTARG ;;
    h) echo "Minecraft Backup (by Nicolas Chan, Martin Oyola and Patrick Mischke)"
       echo "-a    Compression algorithm (default: gzip)"
       echo "-c    Enable chat messages"
       echo "-d    Delete method: thin (default), sequential, none"
       echo "-e    Compression file extension, exclude leading \".\" (default: gz)"
       echo "-f    Output file name (default is the timestamp)"
       echo "-h    Shows this help text"
       echo "-i    Input directory (path to world folder)"
       echo "-l    Compression level (default: 3)"
       echo "-m    Maximum backups to keep, use -1 for unlimited (default: 128)"
       echo "-n    Name of DOCKER CONTAINER (default: mc). This overrides usage of RCON PASS, RCON PORT"
       echo "-o    Output directory"
       echo "-p    Prefix that shows in Minecraft chat (default: Backup)"
       echo "-q    Suppress warnings"
       echo "-r    Minecraft server RCON PASS"
       echo "-s    Minecraft server RCON PORT"
       echo "-v    Verbose mode"
       exit 0
       ;;
    i) SERVER_WORLD=$OPTARG ;;
    l) COMPRESSION_LEVEL=$OPTARG ;;
    m) MAX_BACKUPS=$OPTARG ;;
    n) DOCKER_CONTAINER=$OPTARG 
       USE_DOCKER=true ;;
    o) BACKUP_DIRECTORY=$OPTARG ;;
    p) PREFIX=$OPTARG ;;
    q) SUPPRESS_WARNINGS=true ;;
    r) RCON_PASS=$OPTARG ;;
    s) RCON_PORT=$OPTARG ;;
    v) DEBUG=true ;;
    *) echo "Invalid option used. Ignoring it."
  esac
done

log-fatal () {
  echo -e "\033[0;31mFATAL:\033[0m $*"
}
log-warning () {
  echo -e "\033[0;33mWARNING:\033[0m $*"
}

# Check for missing encouraged arguments
if ! $SUPPRESS_WARNINGS; then
  if [[ $RCON_PORT == "" ]] && [ ! $USE_DOCKER ]; then
    log-warning "Neither RCON_PORT (-s) nor DOCKER CONTAINER (-n) given. Falling back to RCON on default port" 
  fi
fi
if [[ ! $USE_DOCKER ]] && [[ $RCON_PASS == "" ]]; then
  log-fatal "Neither DOCKER CONTAINER (-n) nor RCON PASS (-r) given. Backups will be taken while server is running"
fi
# Check for required arguments
MISSING_CONFIGURATION=false
if [[ $SERVER_WORLD == "" ]]; then
  log-fatal "Server world not specified (use -i)"
  MISSING_CONFIGURATION=true
fi
if [[ $BACKUP_DIRECTORY == "" ]]; then
  log-fatal "Backup directory not specified (use -o)"
  MISSING_CONFIGURATION=true
fi

if $MISSING_CONFIGURATION; then
  exit 0
fi

ARCHIVE_FILE_NAME=$TIMESTAMP.tar$COMPRESSION_FILE_EXTENSION
ARCHIVE_PATH=$BACKUP_DIRECTORY/$ARCHIVE_FILE_NAME

# Minecraft server screen interface functions
message-players () {
  local MESSAGE=$1
  local HOVER_MESSAGE=$2
  message-players-color "$MESSAGE" "$HOVER_MESSAGE" "blue"
}

execute-command () {
  local COMMAND=$1
  if [[ ! $USE_DOCKER ]] && [[ $RCON_PASS != "" ]]; then
    mcrcon -H localhost -P $RCON_PORT -p $RCON_PASS "$COMMAND"
  fi
  if [[ $USE_DOCKER ]]; then
    docker exec -i $DOCKER_CONTAINER rcon-cli "$COMMAND"
  fi
}

message-players-error () {
  local MESSAGE=$1
  local HOVER_MESSAGE=$2
  message-players-color "$MESSAGE" "$HOVER_MESSAGE" "red"
}

message-players-success () {
  local MESSAGE=$1
  local HOVER_MESSAGE=$2
  message-players-color "$MESSAGE" "$HOVER_MESSAGE" "green"
}

message-players-color () {
  local MESSAGE=$1
  local HOVER_MESSAGE=$2
  local COLOR=$3
  if $DEBUG; then
    echo "$MESSAGE ($HOVER_MESSAGE)"
  fi
  if $ENABLE_CHAT_MESSAGES; then
    execute-command "/tellraw @a [\"\",{\"text\":\"[$PREFIX] \",\"color\":\"gray\",\"bold\":true},{\"text\":\"$MESSAGE\",\"color\":\"$COLOR\",\"bold\":true,\"hoverEvent\":{\"action\":\"show_text\",\"value\":{\"text\":\"\",\"extra\":[{\"text\":\"$HOVER_MESSAGE\"}]}}}]"
  fi
}

# Notify players of start
message-players "Starting backup..." "$ARCHIVE_FILE_NAME"

# Parse file timestamp to one readable by "date"
parse-file-timestamp () {
  local DATE_STRING=$(echo $1 | awk -F_ '{gsub(/-/,":",$2); print $1" "$2}')
  echo $DATE_STRING
}

# Delete a backup
delete-backup () {
  local BACKUP=$1
  rm $BACKUP_DIRECTORY/$BACKUP
  message-players "Deleted old backup" "$BACKUP"
}

# Sequential delete method
delete-sequentially () {
  local BACKUPS=($(ls $BACKUP_DIRECTORY))
  while [[ $MAX_BACKUPS -ge 0 && ${#BACKUPS[@]} -gt $MAX_BACKUPS ]]; do
    delete-backup ${BACKUPS[0]}
    BACKUPS=($(ls $BACKUP_DIRECTORY))
  done
}

# Functions to sort backups into correct categories based on timestamps
is-hourly-backup () {
  local TIMESTAMP=$*
  local MINUTE=$(date -d "$TIMESTAMP" +%M)
  return $MINUTE
}
is-daily-backup () {
  local TIMESTAMP=$*
  local HOUR=$(date -d "$TIMESTAMP" +%H)
  return $HOUR
}
is-weekly-backup () {
  local TIMESTAMP=$*
  local DAY=$(date -d "$TIMESTAMP" +%u)
  return $((DAY - 1))
}

# Helper function to sum an array
array-sum () {
  SUM=0
  for NUMBER in $*; do
    (( SUM += NUMBER ))
  done
  echo $SUM
}

# Thinning delete method
delete-thinning () {
  # sub-hourly, hourly, daily, weekly is everything else
  local BLOCK_SIZES=(16 24 30)
  # First block is unconditional
  # The next blocks will only accept files whose names cause these functions to return true (0)
  local BLOCK_FUNCTIONS=("is-hourly-backup" "is-daily-backup" "is-weekly-backup")

  # Warn if $MAX_BACKUPS does not have enough room for all the blocks
  TOTAL_BLOCK_SIZE=$(array-sum ${BLOCK_SIZES[@]})
  if [[ $TOTAL_BLOCK_SIZE -gt $MAX_BACKUPS ]]; then
    if ! $SUPPRESS_WARNINGS; then
      log-warning "MAX_BACKUPS ($MAX_BACKUPS) is smaller than TOTAL_BLOCK_SIZE ($TOTAL_BLOCK_SIZE)"
    fi
  fi

  local CURRENT_INDEX=0
  local BACKUPS=($(ls -r $BACKUP_DIRECTORY)) # List newest first

  for BLOCK_INDEX in ${!BLOCK_SIZES[@]}; do
    local BLOCK_SIZE=${BLOCK_SIZES[BLOCK_INDEX]}
    local BLOCK_FUNCTION=${BLOCK_FUNCTIONS[BLOCK_INDEX]}
    local OLDEST_BACKUP_IN_BLOCK_INDEX=$((BLOCK_SIZE + CURRENT_INDEX)) # Not an off-by-one error because a new backup was already saved
    local OLDEST_BACKUP_IN_BLOCK=${BACKUPS[OLDEST_BACKUP_IN_BLOCK_INDEX]}

    if [[ $OLDEST_BACKUP_IN_BLOCK == "" ]]; then
      break
    fi

    local OLDEST_BACKUP_TIMESTAMP=$(parse-file-timestamp ${OLDEST_BACKUP_IN_BLOCK:0:19})
    local BLOCK_COMMAND="$BLOCK_FUNCTION $OLDEST_BACKUP_TIMESTAMP"

    if $BLOCK_COMMAND; then
      # Oldest backup in this block satisfies the condition for placement in the next block
      if $DEBUG; then
        echo "$OLDEST_BACKUP_IN_BLOCK promoted to next block"
      fi
    else
      # Oldest backup in this block does not satisfy the condition for placement in next block
      delete-backup $OLDEST_BACKUP_IN_BLOCK
      break
    fi

    ((CURRENT_INDEX += BLOCK_SIZE))
  done

  delete-sequentially
}

# Disable world autosaving
execute-command "save-off"

# Save the world and flush so the backup is the most recent save
execute-command "save-all flush"

# Backup world
START_TIME=$(date +"%s")
case $COMPRESSION_ALGORITHM in
  "") # No compression
    tar -cf $ARCHIVE_PATH -C $SERVER_WORLD .
    ;;
  *) # With compression
    tar -cf - -C $SERVER_WORLD . | $COMPRESSION_ALGORITHM -cv -$COMPRESSION_LEVEL - > $ARCHIVE_PATH 2>> /dev/null
    ;;
esac
sync
END_TIME=$(date +"%s")

# Enable world autosaving again
execute-command "save-on"

# Delete old backups
delete-old-backups () {
  case $DELETE_METHOD in
    "sequential") delete-sequentially
      ;;
    "thin") delete-thinning
      ;;
  esac
}

# Notify players of completion
WORLD_SIZE_BYTES=$(du -b --max-depth=0 $SERVER_WORLD | awk '{print $1}')
ARCHIVE_SIZE_BYTES=$(du -b $ARCHIVE_PATH | awk '{print $1}')
COMPRESSION_PERCENT=$(($ARCHIVE_SIZE_BYTES * 100 / $WORLD_SIZE_BYTES))
ARCHIVE_SIZE=$(du -h $ARCHIVE_PATH | awk '{print $1}')
BACKUP_DIRECTORY_SIZE=$(du -h --max-depth=0 $BACKUP_DIRECTORY | awk '{print $1}')
TIME_DELTA=$((END_TIME - START_TIME))

# Check that archive size is not null and at least 1024 KB
if [[ "$ARCHIVE_SIZE" != "" && "$ARCHIVE_SIZE_BYTES" -gt 8 ]]; then
  message-players-success "Backup complete!" "$TIME_DELTA s, $ARCHIVE_SIZE/$BACKUP_DIRECTORY_SIZE, $COMPRESSION_PERCENT%"
  delete-old-backups
else
  message-players-error "Backup was not saved!" "Please notify an administrator"
fi
