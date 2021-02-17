#!/usr/bin/env bash

set -e

# Log in to Vault
VAULT_TOKEN=`curl -v -XPOST -d"{\"role_id\":\"${VAULT_ROLE_ID}\",\"secret_id\":\"${VAULT_ROLE_SECRET_ID}\"}" ${VAULT_ADDR}/v1/auth/approle/login | jq '.auth.client_token' -r`

# Get the client certificate
CERT_RESULT=`curl -v -H"X-Vault-Token:${VAULT_TOKEN}" -XPOST ${VAULT_ADDR}/v1/pki/kafka/issue/kafka-producer -d"{\"common_name\":\"${HOSTNAME}\",\"ttl\":\"8760h\"}" | jq`
echo ${CERT_RESULT} | jq '.data.certificate' -r >> producer.crt
echo ${CERT_RESULT} | jq '.data.private_key' -r >> producer.key
echo ${CERT_RESULT} | jq '.data.issuing_ca' -r >> ca.crt

# Import into keystores
openssl pkcs12 -export -in producer.crt -inkey producer.key -out /tmp/producer.p12 -name localhost -password pass:hellothere
rm -f /tmp/producer.keystore.jks
keytool -importkeystore -destkeystore /tmp/producer.keystore.jks -alias localhost -srcstoretype PKCS12 -srckeystore /tmp/producer.p12  -srcstorepass hellothere -noprompt -deststorepass hellothere
rm -f /tmp/producer.truststore.jks
keytool -keystore /tmp/producer.truststore.jks -alias CARoot -import -file ca.crt -noprompt -storepass hellothere

# Start Kafka producer
/opt/kafka/bin/kafka-producer-perf-test.sh --topic producer-topic --throughput 1 --num-records 300 --producer.config /opt/kafka/config/producer.properties --record-size 100
