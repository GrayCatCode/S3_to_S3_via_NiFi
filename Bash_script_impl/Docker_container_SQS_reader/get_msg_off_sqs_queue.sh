#!/usr/bin/env bash
set -euxo pipefail

# Load an optional environment file if present:
if [[ -f /etc/default/sqs-s3-poller ]]; then
    # shellcheck disable=SC1091
    source /etc/default/sqs-s3-poller
fi

# Configurable via environment variables:
: "${QUEUE_URL:=https://sqs.us-east-1.amazonaws.com/726573357412/s3-notify-queue}"
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

    if [[ $(echo "$MESSAGES" | jq '.Messages | length') -eq 0 ]]; then

	echo "No SQS messages were found on the queue."
        break

    else

	num_of_msgs=$(echo "$MESSAGES" | jq '.Messages | length')
        echo "There are $num_of_msgs messages on the SQS queue ..."

    fi

    echo "$MESSAGES" | jq -c '.Messages[]' | while read -r msg;
    do

	echo
	echo "Message row: $msg"
	echo

	RECEIPT_HANDLE=$(echo $msg | jq -r '.ReceiptHandle')
	echo "Found receipt handle: $RECEIPT_HANDLE"

        BODY=$(echo $msg | jq -r '.Body')
	echo "Found body: $BODY"

	BUCKET=$(echo "$BODY" | jq -r '.Bucket')
	KEY=$(echo "$BODY" | jq -r '.Key')

	echo
	echo "S3 bucket: $BUCKET"
	echo "File key: $KEY"
	echo


        if [[ -z "$BUCKET" || -z "$KEY" ]]; then

            echo "Skipping invalid message ..."
            continue

        fi

        LOCAL_FILE="$DEST_DIR/$(basename "$KEY")"
	echo "The local file to copy the S3 file to is: $LOCAL_FILE"

        echo "Copying s3://$BUCKET/$KEY -> $LOCAL_FILE"

        if aws s3 cp "s3://$BUCKET/$KEY" "$LOCAL_FILE" --region "$AWS_REGION"; then

            echo "Copy successful, deleting SQS message"

            aws sqs delete-message \
                --queue-url "$QUEUE_URL" \
                --region "$AWS_REGION" \
                --receipt-handle "$RECEIPT_HANDLE"

	    echo "Deleted SQS message with handle $RECEPT_HANDLE"

        else

            echo "Copy failed, SQS message left on the queue"

        fi

    done

done
