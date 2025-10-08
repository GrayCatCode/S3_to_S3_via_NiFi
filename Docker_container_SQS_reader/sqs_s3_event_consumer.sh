#!/usr/bin/env bash
#
# sqs_s3_event_consumer.sh
# Bash v4+ script to consume S3 event notifications from SQS and download files locally.
#
# Environment Variables:
#   SQS_QUEUE_URL              (required) - Full SQS queue URL
#   MAX_MESSAGES               (optional) - Default: 10
#   WAIT_TIME_SECONDS           (optional) - Default: 10
#   VISIBILITY_TIMEOUT_SECONDS  (optional) - Default: 30
#   DOWNLOAD_DIR                (optional) - Default: /data/downloads
#
# Example:
#   export SQS_QUEUE_URL="https://sqs.us-east-1.amazonaws.com/123456789012/my-s3-events-queue"
#   ./sqs_s3_event_consumer.sh

set -euo pipefail

# Required
: "${SQS_QUEUE_URL:?SQS_QUEUE_URL environment variable must be set}"

# Defaults
MAX_MESSAGES="${MAX_MESSAGES:-10}"
WAIT_TIME_SECONDS="${WAIT_TIME_SECONDS:-10}"
VISIBILITY_TIMEOUT_SECONDS="${VISIBILITY_TIMEOUT_SECONDS:-30}"
DOWNLOAD_DIR="${DOWNLOAD_DIR:-/data/downloads}"

mkdir -p "$DOWNLOAD_DIR"

echo "Starting SQS S3 consumer"
echo "→ Queue URL: $SQS_QUEUE_URL"
echo "→ Max messages: $MAX_MESSAGES"
echo "→ Wait time: $WAIT_TIME_SECONDS s"
echo "→ Visibility timeout: $VISIBILITY_TIMEOUT_SECONDS s"
echo "→ Download dir: $DOWNLOAD_DIR"
echo "Press Ctrl+C to stop."

while true; do
  # Poll SQS for messages
  MESSAGES_JSON=$(aws sqs receive-message \
    --queue-url "$SQS_QUEUE_URL" \
    --max-number-of-messages "$MAX_MESSAGES" \
    --wait-time-seconds "$WAIT_TIME_SECONDS" \
    --visibility-timeout "$VISIBILITY_TIMEOUT_SECONDS" \
    --output json)

  # Skip if no messages
  if [[ -z "$MESSAGES_JSON" || "$MESSAGES_JSON" == "{}" ]]; then
    continue
  fi

  MESSAGE_COUNT=$(echo "$MESSAGES_JSON" | jq '.Messages | length // 0')
  (( MESSAGE_COUNT == 0 )) && continue

  echo "Received $MESSAGE_COUNT message(s)..."

  for (( i=0; i<MESSAGE_COUNT; i++ )); do
    RECEIPT_HANDLE=$(echo "$MESSAGES_JSON" | jq -r ".Messages[$i].ReceiptHandle")
    BODY=$(echo "$MESSAGES_JSON" | jq -r ".Messages[$i].Body")

    # Handle both direct and SNS-wrapped S3 notifications
    if echo "$BODY" | jq -e '.Records' >/dev/null 2>&1; then
      RECORDS_JSON="$BODY"
    else
      RECORDS_JSON=$(echo "$BODY" | jq -r '.Message' 2>/dev/null || echo "$BODY")
    fi

    BUCKET=$(echo "$RECORDS_JSON" | jq -r '.Records[0].s3.bucket.name')
    KEY=$(echo "$RECORDS_JSON" | jq -r '.Records[0].s3.object.key')
    BASENAME=$(basename "$KEY")
    DEST_PATH="$DOWNLOAD_DIR/$BASENAME"

    echo "→ S3 Event:"
    echo "   Bucket: $BUCKET"
    echo "   Key:    $KEY"
    echo "   Downloading to: $DEST_PATH"

    if aws s3 cp "s3://$BUCKET/$KEY" "$DEST_PATH"; then
      echo "✔ Download successful: $DEST_PATH"
      aws sqs delete-message \
        --queue-url "$SQS_QUEUE_URL" \
        --receipt-handle "$RECEIPT_HANDLE" >/dev/null
      echo "✔ Deleted message from SQS"
    else
      echo "✖ Failed to download s3://$BUCKET/$KEY"
    fi

  done
done
