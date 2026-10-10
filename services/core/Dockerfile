FROM ghcr.io/hyperledger-firefly/firefly:v1.5.0

USER root
RUN apk add --no-cache gettext

COPY firefly.core.yml.template /app/firefly.core.yml.template
COPY entrypoint.sh /app/entrypoint.sh
RUN chmod +x /app/entrypoint.sh

EXPOSE 5000

ENTRYPOINT ["/app/entrypoint.sh"]
