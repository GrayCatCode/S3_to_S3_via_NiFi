#!/usr/bin/env bash
#
# sqs_s3_event_consumer.sh
# Bash v4+ script: polls SQS for S3 events, downloads files, retries on failure,
# and emits structured syslog-style logs.
#
# Environment Variables:
#   SQS_QUEUE_URL               (required)
#   MAX_MESSAGES                (default: 10)
#   WAIT_TIME_SECONDS           (default: 10)
#   VISIBILITY_TIMEOUT_SECONDS  (default: 30)
#   DOWNLOAD_DIR                (default: /data/downloads)
#   RCVD_MSGS_DIR               (default: /data/rcvd_sqs_msgs)
#   HEALTHCHECK_FILE            (default: /tmp/sqs_consumer_healthy)
#   MAX_RETRIES                 (default: 5)
#   BASE_BACKOFF_SECONDS        (default: 2)
#   LOG_LEVEL                   (default: INFO)
#
# Exit codes:
#   0 = normal operation
#   1 = misconfiguration
#   2 = unhealthy (used by Docker HEALTHCHECK)
#

set -euo pipefail

# -----------------------------
# Configuration
# -----------------------------
: "${SQS_QUEUE_URL:?SQS_QUEUE_URL environment variable must be set}"

MAX_MESSAGES="${MAX_MESSAGES:-10}"
WAIT_TIME_SECONDS="${WAIT_TIME_SECONDS:-10}"
VISIBILITY_TIMEOUT_SECONDS="${VISIBILITY_TIMEOUT_SECONDS:-30}"
DOWNLOAD_DIR="${DOWNLOAD_DIR:-/data/downloads}"
RCVD_SQS_MSGS_DIR="${RCVD_SQS_MSGS_DIR:-/data/rcvd_sqs_msgs_dir}"
HEALTHCHECK_FILE="${HEALTHCHECK_FILE:-/tmp/sqs_consumer_healthy}"
MAX_RETRIES="${MAX_RETRIES:-5}"
BASE_BACKOFF_SECONDS="${BASE_BACKOFF_SECONDS:-2}"
LOG_LEVEL="${LOG_LEVEL:-INFO}"

mkdir -p "$DOWNLOAD_DIR"

# -----------------------------
# Logging Functions
# -----------------------------
timestamp() {

  # Generate a timestamp string:
  date +"%m%d%Y_%H:%M:%S%z"

}

log() {

  # The first item passed to the function has to be
  # the logging level:
  local level="$1"; shift

  # Everything else passed to the function is the log message:
  local msg="$*"

  echo "$(timestamp) [$level] sqs-consumer: $msg"

}

# Define logging functions based on the appropriate logging level:
log_debug() { [[ "$LOG_LEVEL" == "DEBUG" ]] && log "DEBUG" "$*"; }
log_info()  { log "INFO" "$*"; }
log_warn()  { log "WARN" "$*"; }
log_error() { log "ERROR" "$*"; }

# -----------------------------
# Health Check Update:
# -----------------------------
update_healthcheck() {

  # Write the current timestamp to the health ehck file:
  date +%s > "$HEALTHCHECK_FILE"

  # Log the update to the health check file:
  log_debug "Health check updated."

}

#-------------------------------------------------------
# Function to retry a given command a specified number
# of times with a configurable backoff delay in seconds:
#-------------------------------------------------------
retry_with_backoff() {

  local attempt=1
  local cmd=("$@")
  local delay=$BASE_BACKOFF_SECONDS

  while true; do

    if "${cmd[@]}"; then
      return 0
    fi

    if (( attempt >= MAX_RETRIES )); then

      log_error "Command failed after $MAX_RETRIES attempts: ${cmd[*]}"
      return 1

    fi

    log_warn "Attempt $attempt failed; retrying in ${delay}s..."
    sleep "$delay"
    delay=$((delay * 2))
    ((attempt++))

  done
}

# -----------------------------
# Script Initialization:
# -----------------------------
log_info "Starting SQS→S3 consumer"
log_info "=> Queue: $SQS_QUEUE_URL"
log_info "=> Download dir: $DOWNLOAD_DIR"
log_info "=> Max retries: $MAX_RETRIES, base backoff: $BASE_BACKOFF_SECONDS s"
log_info "=> Healthcheck file: $HEALTHCHECK_FILE"
log_info "=> Log level: $LOG_LEVEL"
log_info "Press Ctrl+C to stop."

# -----------------------------
# Main Script Loop:
# -----------------------------
while true; do

  # Write the current timestamp to the health check file:
  update_healthcheck

  # Check for messages on the SQS queue:
  MESSAGES_JSON=$(aws sqs receive-message \
    --queue-url "$SQS_QUEUE_URL" \
    --max-number-of-messages "$MAX_MESSAGES" \
    --wait-time-seconds "$WAIT_TIME_SECONDS" \
    --visibility-timeout "$VISIBILITY_TIMEOUT_SECONDS" \
    --output json 2>/dev/null || true)

  # If there were no messages, wait and iterate the main loop again.
  if [[ -z "$MESSAGES_JSON" || "$MESSAGES_JSON" == "{}" ]]; then

#   sleep 2
    continue

  else

    # Write the SQS message body we received to the local filesystem:
    current_timestamp=timestamp
    sqs_msg_name="sqs_msg_${current_timestamp}"

    log_info "Recived an SQS message: $sqs_msg_name"

    echo "$MESSAGES_JSON" > "$RCVD_SQS_MSGS_DIR/$sqs_msg_name"

  fi

  # Get the number of S3 event messages from the SQS message retreived:
  MESSAGE_COUNT=$(echo "$MESSAGES_JSON" | jq '.Messages | length // 0')
  (( MESSAGE_COUNT == 0 )) && sleep 2 && continue

  log_info "Received $MESSAGE_COUNT message(s)"

  # Loop through all the received S3 event messages:
  for (( i=0; i<MESSAGE_COUNT; i++ )); do

    RECEIPT_HANDLE=$(echo "$MESSAGES_JSON" | jq -r ".Messages[$i].ReceiptHandle")
    BODY=$(echo "$MESSAGES_JSON" | jq -r ".Messages[$i].Body")

    # Check if the messages came via SQS or SNS:
    if echo "$BODY" | jq -e '.Records' >/dev/null 2>&1; then

      # S3 event messages came direct via SQS:
      RECORDS_JSON="$BODY"

    else # Messages are SNS-wrapped:

      RECORDS_JSON=$(echo "$BODY" | jq -r '.Message' 2>/dev/null || echo "$BODY")

    fi

    # Parse the S3 event for the bucket name and key:
    BUCKET=$(echo "$RECORDS_JSON" | jq -r '.Records[0].s3.bucket.name')
    KEY=$(echo "$RECORDS_JSON" | jq -r '.Records[0].s3.object.key')

    # Get the name of the file:
    BASENAME=$(basename "$KEY")

    # Get the destination that the file will be written to:
    DEST_PATH="$DOWNLOAD_DIR/$BASENAME"

    log_info "Processing object: s3://$BUCKET/$KEY"
    log_debug "Download path: $DEST_PATH"

    # Try to copy the file from the S3 bucket:
    if retry_with_backoff aws s3 cp "s3://$BUCKET/$KEY" "$DEST_PATH"; then

      log_info "Downloaded: $DEST_PATH"

      # Attept to delete the message from the SQS queue:
      retry_with_backoff aws sqs delete-message \
        --queue-url "$SQS_QUEUE_URL" \
        --receipt-handle "$RECEIPT_HANDLE"

      log_info "Deleted message from SQS ..."

    else # Downloading the file from the S3 bucket failed:

      log_error "Failed to download s3://$BUCKET/$KEY after retries ..."

    fi

  done

done
