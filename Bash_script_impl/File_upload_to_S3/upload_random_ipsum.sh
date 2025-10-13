#!/usr/bin/env bash
#
# upload_random_ipsum.sh
#
# Generate a random Lorem Ipsum text file of a given size and upload to S3.
# Requires: awscli, base64, /usr/share/dict/words or built-in lorem text.
#
# Usage:
#   ./upload_random_ipsum.sh <size_in_kb> <s3_bucket_name>
#
# Example:
#   ./upload_random_ipsum.sh 512 my-sample-bucket
#
# To run in cron (every hour):
#   0 * * * * /path/to/upload_random_ipsum.sh 512 my-sample-bucket >> /var/log/upload_random_ipsum.log 2>&1
#

set -euo pipefail

echo "Executing upload_random_ipsum.sh ..."

SIZE_KB="${1:-100}"              # Default 100 KB
S3_BUCKET="${2:-my-s3-bucket}"   # Default bucket (change as needed)
TMP_DIR="/tmp"
TIMESTAMP=$(date +"%Y%m%d-%H%M%S")
TMP_FILE="${TMP_DIR}/ipsum-${TIMESTAMP}.txt"

# --- Sanity checks ---
if ! command -v aws >/dev/null 2>&1;
then

  echo "Error: The aws CLI not found. Please install and configure it with 'aws configure'." >&2
  exit 1

else

  echo "Found the aws CLI installed."

fi

# --- Generate Lorem Ipsum text ---
generate_ipsum() {

  local words=(
    lorem ipsum dolor sit amet consectetur adipiscing elit sid di eiusmod tempor incididunt ut labore et dolore magna aliqua
    ut enim ad minim veniam quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat
    duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur
    excepteur sint occaecat cupidatat non proident sunt in culpa qui officia deserunt mollit anim id est laborum
  )

  local word_count="${#words[@]}"

  echo "Generating Lorem Ipsum text ..."

  while [ "$(du -k "$TMP_FILE" 2>/dev/null | awk '{print $1}')" -lt "$SIZE_KB" ];
  do

    echo -n "${words[RANDOM % word_count]} " >> "$TMP_FILE"

  done

  echo "... file created."
}

echo "[$(date)] Generating ${SIZE_KB}KB of random Lorem Ipsum text..." > "$TMP_FILE"

generate_ipsum

echo "[$(date)] File created at: $TMP_FILE ($(du -h "$TMP_FILE" | awk '{print $1}'))"

# --- Upload to S3 ---
S3_KEY="ipsum/${TIMESTAMP}.txt"

echo "[$(date)] Uploading to s3://${S3_BUCKET}/${S3_KEY} ..."

aws s3 cp "$TMP_FILE" "s3://${S3_BUCKET}/${S3_KEY}" --only-show-errors

# --- Cleanup ---
rm -f "$TMP_FILE"

echo "[$(date)] Upload complete and temp file removed."

exit 0
