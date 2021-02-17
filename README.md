# Using Hashicorp Vault for mTLS Authentication with Apache Kafka

This repository contains a reference implementation for utilizing Hashicorp Vault's PKI back-end to allow mutual TLS authentication with Apache Kafka.

## Pre-Requisites and Assumptions

- You must have Docker installed locally.
- This implementation runs all services in Docker for the sake of simplicity.
- We will use the built-in Kafka command line tools rather than custom programs for ease of use.

## Goals and Requirements

- [X] The Kafka start-up process must include authenticating against Vault, retrieving certificates, and then starting the Kafka broker with those certificates bound.
- [X] Kafka consumers and producers must follow a similar pattern, where certificates are retrieved every time they start up.
- [ ] Different consumers and producers must be able to obtain certificates from Vault that only allow them access to resources they are authorized for (i.e. different certificates allow different sets of privileges)
- [ ] AppRole authentication against Vault is used for both Kafka brokers and consumers / producers. 

## Setup and Execution

### Vault Setup

- Start up the Vault container by running the following command:
  ```
  docker-compose -f vault/docker-compose.yml up -d vault
  ```
- Initialize Vault and retrieve the token and unseal keys. **Keep these because if you lose them you'll have to start over.**
  ```
  docker exec -it vault vault operator init -key-shares=1 -key-threshold=1
  Unseal Key 1: tGrC3TUtfTduX5k3n0qAntXS5bIIztTnB9s4n/IL2Xk=

  Initial Root Token: s.Zucw52GK3JUAlHNKAMrexCVP
  ```
- Unseal Vault. When prompted, enter the **unseal key** shown in the output from above.
  ```
  docker exec -it vault vault operator unseal
  Unseal Key (will be hidden): 
  Key             Value
  ---             -----
  Seal Type       shamir
  Initialized     true
  Sealed          false
  Total Shares    1
  Threshold       1
  Version         1.6.2
  Storage Type    file
  Cluster Name    vault-cluster-1ddb6440
  Cluster ID      0f4da39b-4caf-b1f2-9827-e984064e0329
  HA Enabled      false
  ```
- Set an environment variable with the root token value for ease of use. **The space before the `export` command is intentional as it prevents this from being put in your command history.**
  ```
   export VAULT_TOKEN=s.Zucw52GK3JUAlHNKAMrexCVP
  ```
- Enable the PKI back end.
  ```
  curl -H"X-Vault-Token:${VAULT_TOKEN}" -XPUT -d@json/enable-pki.json http://localhost:8200/v1/sys/mounts/pki/kafka -v
  *   Trying 127.0.0.1...
  * TCP_NODELAY set
  * Connected to localhost (127.0.0.1) port 8200 (#0)
  > PUT /v1/sys/mounts/pki HTTP/1.1
  > Host: localhost:8200
  > User-Agent: curl/7.64.1
  > Accept: */*
  > X-Vault-Token:s.Zucw52GK3JUAlHNKAMrexCVP
  > Content-Length: 17
  > Content-Type: application/x-www-form-urlencoded
  > 
  * upload completely sent off: 17 out of 17 bytes
  < HTTP/1.1 204 No Content
  < Cache-Control: no-store
  < Content-Type: application/json
  < Date: Thu, 11 Feb 2021 18:12:03 GMT
  < 
  * Connection #0 to host localhost left intact
  * Closing connection 0
  ```
- Adjust the max TTL length to 10 years
  ```
  docker exec -e VAULT_TOKEN=${VAULT_TOKEN} vault vault secrets tune -max-lease-ttl=87600h pki/kafka
  ```
- Create a root CA certificate
  ```
  curl -H"X-Vault-Token:${VAULT_TOKEN}" -XPOST -d@json/generate-root.json http://localhost:8200/v1/pki/kafka/root/generate/internal -v
  ```
  You can ignore the output of this command.
- Set the issuing URL.
  ```
  curl -H"X-Vault-Token:${VAULT_TOKEN}" -XPOST -d@json/set-url.json http://localhost:8200/v1/pki/kafka/config/urls
  ```
- Enable AppRole authentication.
  ```
  curl -H"X-Vault-Token:${VAULT_TOKEN}" -XPOST -d@json/enable-approle.json http://localhost:8200/v1/sys/auth/approle
  ```

## Configure for Kafka Brokers

- Create a role for issuing certificates.
  ```
  curl -H"X-Vault-Token:${VAULT_TOKEN}" -XPOST -d@json/create-role.json http://localhost:8200/v1/pki/kafka/roles/kafka-broker
  ```
- Create a policy for Kafka servers.
  ```
  docker exec -e VAULT_TOKEN=${VAULT_TOKEN} vault vault policy write kafka-broker /repo/policies/kafka-broker.hcl
  ```
- Create an AppRole for Kafka servers.
  ```
  curl -H"X-Vault-Token:${VAULT_TOKEN}" -XPOST -d@json/create-kafka-broker-approle.json http://localhost:8200/v1/auth/approle/role/kafka-broker -v
  ```
- Fetch a RoleID and SecretID for the AppRole.
  ```
  $ export VAULT_ROLE_ID=`docker exec -e VAULT_TOKEN=${VAULT_TOKEN} vault vault read -field=role_id auth/approle/role/kafka-broker/role-id`
  Key        Value
  ---        -----
  role_id    7b69c952-f05c-6d5a-a5b7-c5130163ca61
  $ export VAULT_ROLE_SECRET_ID=`docker exec -e VAULT_TOKEN=${VAULT_TOKEN} vault vault write -field=secret_id -f auth/approle/role/kafka-broker/secret-id`
  Key                   Value
  ---                   -----
  secret_id             766db74c-6a86-7937-1b18-cd2a09ca29dd
  secret_id_accessor    973c078c-d552-ec72-6532-9625bfdf846f
- Build the customized Docker image that includes the customized start-up script.
  ```
  $ docker build -t kafka_vault kafka
  ```
- Run a Kafka broker with the configured Vault tokens and IDs.
  ```
  $ docker-compose -f vault/docker-compose.yml up --build -d kafka1
  ```
- Grant cluster admin rights to the broker.
  ```
  $ docker run -it --rm --entrypoint bash --network kafka kafka_vault /opt/kafka/bin/kafka-acls.sh --authorizer-properties zookeeper.connect=zookeeper:2181 --add --allow-principal 'User:CN=kafka1.broker.kafka.local' --cluster
  ```

## Configure for Kafka Producers

- Create a role for issuing certificates.
  ```
  curl -H"X-Vault-Token:${VAULT_TOKEN}" -XPOST -d@json/create-producer-role.json http://localhost:8200/v1/pki/kafka/roles/kafka-producer
  ```
- Create a policy for Kafka servers.
  ```
  $ docker exec -e VAULT_TOKEN=${VAULT_TOKEN} vault vault policy write kafka-producer /repo/policies/kafka-producer.hcl
  Success! Uploaded policy: kafka-producer
  ```
- Create an AppRole for Kafka servers.
  ```
  curl -H"X-Vault-Token:${VAULT_TOKEN}" -XPOST -d@json/create-kafka-producer-approle.json http://localhost:8200/v1/auth/approle/role/kafka-producer -v
  ```
- Fetch a RoleID and SecretID for the AppRole.
  ```
  $ export VAULT_PRODUCER_ROLE_ID=`docker exec -e VAULT_TOKEN=${VAULT_TOKEN} vault vault read -field=role_id auth/approle/role/kafka-producer/role-id`
  $ export VAULT_PRODUCER_ROLE_SECRET_ID=`docker exec -e VAULT_TOKEN=${VAULT_TOKEN} vault vault write -field=secret_id -f auth/approle/role/kafka-producer/secret-id`
- Grant producing rights to the producer.
  ```
  $ docker run -it --rm --entrypoint bash --network kafka kafka_vault /opt/kafka/bin/kafka-acls.sh --authorizer-properties zookeeper.connect=zookeeper:2181 --add --allow-principal 'User:CN=producer1.producer.kafka.local' --topic producer-topic --operation Write --operation Describe
  ```
- Create the new topic.
  ```
  $ docker exec kafka1.broker.kafka.local /opt/kafka/bin/kafka-topics.sh --bootstrap-server kafka1.broker.kafka.local:9093 --if-not-exists --topic producer-topic --create --replication-factor 1 --partitions 1 --command-config /opt/kafka/config/adminconfig.properties
  ```
- Run a Kafka producer with the configured Vault tokens and IDs.
  ```
  $ docker-compose -f vault/docker-compose.yml up --build -d kafka1
  ```
## Configure for Kafka Consumers

- Create a role for issuing certificates.
  ```
  curl -H"X-Vault-Token:${VAULT_TOKEN}" -XPOST -d@json/create-consumer-role.json http://localhost:8200/v1/pki/kafka/roles/kafka-consumer
  ```
- Create a policy for Kafka consumers.
  ```
  $ docker exec -e VAULT_TOKEN=${VAULT_TOKEN} vault vault policy write kafka-consumer /repo/policies/kafka-consumer.hcl
  Success! Uploaded policy: kafka-consumer
  ```
- Create an AppRole for Kafka consumers.
  ```
  curl -H"X-Vault-Token:${VAULT_TOKEN}" -XPOST -d@json/create-kafka-consumer-approle.json http://localhost:8200/v1/auth/approle/role/kafka-consumer -v
  ```
- Fetch a RoleID and SecretID for the AppRole.
  ```
  $ export VAULT_CONSUMER_ROLE_ID=`docker exec -e VAULT_TOKEN=${VAULT_TOKEN} vault vault read -field=role_id auth/approle/role/kafka-consumer/role-id`
  $ export VAULT_CONSUMER_ROLE_SECRET_ID=`docker exec -e VAULT_TOKEN=${VAULT_TOKEN} vault vault write -field=secret_id -f auth/approle/role/kafka-consumer/secret-id`
- Grant producing rights to the consumer.
  ```
  $ docker run -it --rm --entrypoint bash --network kafka kafka_vault /opt/kafka/bin/kafka-acls.sh --authorizer-properties zookeeper.connect=zookeeper:2181 --add --allow-principal 'User:CN=consumer1.consumer.kafka.local' --topic producer-topic --operation Read --operation Describe
  $ docker run -it --rm --entrypoint bash --network kafka kafka_vault /opt/kafka/bin/kafka-acls.sh --authorizer-properties zookeeper.connect=zookeeper:2181 --add --allow-principal 'User:CN=consumer1.consumer.kafka.local' --group consumer-group --operation Read
  ```
- Run a Kafka producer with the configured Vault tokens and IDs.
  ```
  $ docker-compose -f vault/docker-compose.yml up --build -d kafka1
  ```