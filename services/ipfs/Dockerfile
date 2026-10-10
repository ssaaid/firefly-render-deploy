FROM ipfs/kubo:latest

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

EXPOSE 4001 5001 8080

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
