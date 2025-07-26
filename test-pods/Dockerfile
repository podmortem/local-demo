FROM busybox:1.36-uclibc

RUN mkdir -p /logs /scripts

COPY logs/ /logs/
COPY scripts/ /scripts/

RUN chmod +x /scripts/* 2>/dev/null || echo "No scripts to make executable"

WORKDIR /

CMD ["sh", "-c", "echo 'Available log files:' && ls -la /logs/ && echo 'Use: cat /logs/<filename>' && sh"]
