# ------------------------------
# Dockerfile for SQS→S3 Consumer
# ------------------------------
FROM amazonlinux:2023

# Install dependencies
RUN dnf install -y jq awscli bash && dnf clean all

# Create app directory
WORKDIR /app

# Copy script
COPY sqs_s3_event_consumer.sh /app/sqs_s3_event_consumer.sh
RUN chmod +x /app/sqs_s3_event_consumer.sh

# Create download directory
RUN mkdir -p /data/downloads

# Set environment defaults (can be overridden in Docker Compose)
ENV MAX_MESSAGES=10 \
    WAIT_TIME_SECONDS=10 \
    VISIBILITY_TIMEOUT_SECONDS=30 \
    DOWNLOAD_DIR=/data/downloads

# Volume for local downloads
VOLUME ["/data/downloads"]

# Run the consumer
CMD ["/app/sqs_s3_event_consumer.sh"]
