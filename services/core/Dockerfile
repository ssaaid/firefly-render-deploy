FROM hyperledger/firefly:latest

USER root
RUN apt-get update && apt-get install -y --no-install-recommends gettext-base \
    && rm -rf /var/lib/apt/lists/*

COPY firefly.core.yml.template /app/firefly.core.yml.template
COPY entrypoint.sh /app/entrypoint.sh
RUN chmod +x /app/entrypoint.sh

EXPOSE 5000 5001

ENTRYPOINT ["/app/entrypoint.sh"]
