#!/usr/bin/env bash
#
# NiFi Template Manager
# Usage:
#   ./nifi-templates.sh list
#   ./nifi-templates.sh download <template-id> <output-file>
#   ./nifi-templates.sh delete <template-id>
#

NIFI_HOST="${NIFI_HOST:-http://localhost:8080}"

list_templates() {
  echo "📋 Listing templates from $NIFI_HOST"
  curl -s "$NIFI_HOST/nifi-api/templates" | jq '.templates[] | {id, name, description}'
}

download_template() {
  local template_id="$1"
  local output="$2"
  if [[ -z "$template_id" || -z "$output" ]]; then
    echo "Usage: $0 download <template-id> <output-file>"
    exit 1
  fi
  echo "⬇️  Downloading template $template_id to $output"
  curl -s "$NIFI_HOST/nifi-api/templates/$template_id/download" -o "$output"
}

delete_template() {
  local template_id="$1"
  if [[ -z "$template_id" ]]; then
    echo "Usage: $0 delete <template-id>"
    exit 1
  fi
  echo "🗑️  Deleting template $template_id"
  curl -s -X DELETE "$NIFI_HOST/nifi-api/templates/$template_id"
  echo
}

case "$1" in
  list)
    list_templates
    ;;
  download)
    download_template "$2" "$3"
    ;;
  delete)
    delete_template "$2"
    ;;
  *)
    echo "Usage: $0 {list|download <id> <file>|delete <id>}"
    exit 1
    ;;
esac

exit 0