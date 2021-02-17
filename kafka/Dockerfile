FROM yardbirdsax/kafka:2.13-2.7.0

COPY server.properties /opt/kafka/config/server.properties
COPY start-kafka.sh /opt/kafka/start-kafka.sh

RUN chmod +x /opt/kafka/start-kafka.sh

RUN apk add openssl

ENTRYPOINT [ "/bin/bash","-c","/opt/kafka/start-kafka.sh" ]
