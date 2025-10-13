#!/usr/bin/env bash
set -euo pipefail

# Load an optional environment file if present:
if [[ -f /etc/default/sqs-s3-poller ]]; then
    # shellcheck disable=SC1091
    source /etc/default/sqs-s3-poller
fi

# Configurable via environment variables:
: "${QUEUE_URL:?SQS queue URL must be set in /etc/default/sqs-s3-poller or env}"
: "${DEST_DIR:=/var/data/s3-files}"
: "${AWS_REGION:=us-east-1}"
: "${MAX_MSGS:=10}"
: "${WAIT_SECS:=20}"

mkdir -p "$DEST_DIR"

while true; do

    echo "Checking for SQS messages ..."

    MESSAGES=$(aws sqs receive-message \
        --queue-url "$QUEUE_URL" \
        --region "$AWS_REGION" \
        --max-number-of-messages "${MAX_MSGS}" \
        --wait-time-seconds "${WAIT_SECS}" \
        --output json)

    echo "MESSAGES = $MESSAGES"

    if [[ $(jq '.Messages | length' < "$MESSAGES") -eq 0 ]]; then

	echo "No SQS messages were found on the queue."
        break

    else

	num_of_msgs=$(jq '.Messages | length' < "$MESSAGES")
	echo "There were $num_of_msgs message(s) on the SQS queue ..."

    fi

    for row in $(jq -c '.Messages[]' < "$MESSAGES"); do

        RECEIPT_HANDLE=$(jq -r '.ReceiptHandle' <<< "$row")
        BODY=$(jq -r '.Body' <<< "$row")

        if jq -e . <<< "$BODY" >/dev/null 2>&1; then

            EVENT="$BODY"

        else

            EVENT=$(jq -r . <<< "$BODY")

        fi

        BUCKET=$(jq -r '.Records[0].s3.bucket.name' <<< "$EVENT")
        KEY=$(jq -r '.Records[0].s3.object.key' <<< "$EVENT")

        if [[ -z "$BUCKET" || -z "$KEY" ]]; then

            echo "Skipping invalid message ..."
            continue

        fi

        LOCAL_FILE="$DEST_DIR/$(basename "$KEY")"

        echo "Copying s3://$BUCKET/$KEY -> $LOCAL_FILE"

        if aws s3 cp "s3://$BUCKET/$KEY" "$LOCAL_FILE" --region "$AWS_REGION"; then

            echo "Copy successful, deleting SQS message"

            aws sqs delete-message \
                --queue-url "$QUEUE_URL" \
                --region "$AWS_REGION" \
                --receipt-handle "$RECEIPT_HANDLE"

        else

            echo "Copy failed, message left on queue"

        fi

    done

done
