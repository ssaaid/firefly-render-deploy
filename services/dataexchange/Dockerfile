FROM ghcr.io/hyperledger-firefly/dataexchange-https:v1.4.0

USER root
RUN apk add --no-cache gettext openssl

COPY config.json.template /app/config.json.template
COPY entrypoint.sh /app/entrypoint.sh
RUN chmod +x /app/entrypoint.sh

EXPOSE 3000 3001

ENTRYPOINT ["/app/entrypoint.sh"]
