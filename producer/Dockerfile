FROM yardbirdsax/kafka:2.13-2.7.0

RUN apk add openssl

COPY producer.properties /opt/kafka/config/producer.properties
COPY start-producer.sh /opt/kafka/start-producer.sh

RUN chmod +x /opt/kafka/start-producer.sh

ENTRYPOINT [ "/bin/bash","-c","/opt/kafka/start-producer.sh" ]