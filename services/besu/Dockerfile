FROM hyperledger/besu:23.4.1

USER root
COPY genesis.json /app/genesis.json
COPY entrypoint.sh /app/entrypoint.sh
RUN chmod +x /app/entrypoint.sh

EXPOSE 8545

ENTRYPOINT ["/app/entrypoint.sh"]
