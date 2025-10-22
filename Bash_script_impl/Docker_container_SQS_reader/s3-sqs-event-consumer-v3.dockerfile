# ----------------------------------------
# Dockerfile for SQS→S3 Consumer (with syslog-style logging)
# ----------------------------------------
FROM amazonlinux:2023

RUN dnf install -y jq awscli bash coreutils && dnf clean all

WORKDIR /app

COPY sqs_s3_event_consumer.sh /app/sqs_s3_event_consumer.sh
RUN chmod +x /app/sqs_s3_event_consumer.sh

VOLUME ["/data/downloads"]
VOLUME ["/data/rcvd_sqs_msgs"]

ENV MAX_MESSAGES=10 \
    WAIT_TIME_SECONDS=10 \
    VISIBILITY_TIMEOUT_SECONDS=30 \
    DOWNLOAD_DIR=/data/downloads \
    HEALTHCHECK_FILE=/tmp/sqs_consumer_healthy \
    MAX_RETRIES=5 \
    BASE_BACKOFF_SECONDS=2 \
    LOG_LEVEL=INFO

HEALTHCHECK --interval=60s --timeout=10s --retries=3 CMD \
  test -f /tmp/sqs_consumer_healthy && \
  [ $(( $(date +%s) - $(cat /tmp/sqs_consumer_healthy 2>/dev/null || echo 0) )) -lt 120 ] \
  || exit 2

CMD ["/app/sqs_s3_event_consumer.sh"]