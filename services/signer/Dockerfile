FROM ghcr.io/hyperledger-firefly/signer:v1.2.1

USER root
RUN apt-get update && apt-get install -y --no-install-recommends gettext-base nodejs npm \
    && npm install -g ethers@6 \
    && mkdir -p /app \
    && ln -s "$(npm root -g)" /app/node_modules \
    && rm -rf /var/lib/apt/lists/*

COPY ffsigner.yml.template /app/ffsigner.yml.template
COPY make-keystore.js /app/make-keystore.js
COPY entrypoint.sh /app/entrypoint.sh
RUN chmod +x /app/entrypoint.sh

EXPOSE 8545

ENTRYPOINT ["/app/entrypoint.sh"]
