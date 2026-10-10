FROM ghcr.io/hyperledger-firefly/evmconnect:v1.5.1

USER root
RUN apk add --no-cache gettext

COPY evmconnect.yml.template /app/evmconnect.yml.template
COPY entrypoint.sh /app/entrypoint.sh
RUN chmod +x /app/entrypoint.sh

EXPOSE 5008

ENTRYPOINT ["/app/entrypoint.sh"]
