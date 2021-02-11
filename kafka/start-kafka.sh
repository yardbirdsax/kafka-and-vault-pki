#!/usr/bin/env bash

# Log in to Vault
VAULT_TOKEN=`curl -XPOST -d"{\"role_id\":\"${VAULT_ROLE_ID}\",\"secret_id\":\"${VAULT_ROLE_SECRET_ID}\"}" ${VAULT_ADDR}/v1/auth/approle/login | jq '.auth.client_token' -r`

# Get the certificate
CERT_RESULT=`curl -H"X-Vault-Token:${VAULT_TOKEN}" -XPOST ${VAULT_ADDR}/v1/pki/kafka/issue/kafka-broker -d'{"common_name":"kafka1.broker.kafka.local","ttl":"8760h"}' | jq`
echo ${CERT_RESULT} | jq '.data.certificate' -r >> server.crt
echo ${CERT_RESULT} | jq '.data.certificate' -r >> server.key