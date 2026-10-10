FROM hyperledger/firefly-dataexchange-https:latest

USER root
RUN apk add --no-cache gettext

COPY dataexchange.yml.template /app/dataexchange.yml.template
COPY entrypoint.sh /app/entrypoint.sh
RUN chmod +x /app/entrypoint.sh

EXPOSE 3000 3001

ENTRYPOINT ["/app/entrypoint.sh"]
