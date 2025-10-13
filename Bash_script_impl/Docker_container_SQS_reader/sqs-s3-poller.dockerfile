FROM amazonlinux:2023

# Install dependencies
RUN yum -y install \
      awscli \
      jq \
      bash \
      && yum clean all

# Add script
COPY sqs-s3-poller.sh /usr/local/bin/sqs-s3-poller.sh
RUN chmod +x /usr/local/bin/sqs-s3-poller.sh

# Default env vars
ENV DEST_DIR=/data \
    AWS_REGION=us-east-1 \
    POLL_INTERVAL=600

# Create mount point
RUN mkdir -p /data

# Loop forever: run poller then sleep
CMD while true; do \
      /usr/local/bin/sqs-s3-poller.sh; \
      echo "Sleeping for $POLL_INTERVAL seconds..."; \
      sleep $POLL_INTERVAL; \
    done
