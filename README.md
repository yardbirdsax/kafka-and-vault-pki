# Using Hashicorp Vault for mTLS Authentication with Apache Kafka

This repository contains a reference implementation for utilizing Hashicorp Vault's PKI back-end to allow mutual TLS authentication with Apache Kafka.

## Pre-Requisites and Assumptions

- You must have Docker installed locally.
- This implementation runs all services in Docker for the sake of simplicity.
- We will use the built-in Kafka command line tools rather than custom programs for ease of use.

## Goals and Requirements

- The Kafka start-up process must include authenticating against Vault, retrieving certificates, and then starting the Kafka broker with those certificates bound.
- Kafka consumers and producers must follow a similar pattern, where certificates are retrieved every time they start up.
- AppRole authentication against Vault is used for both Kafka brokers and consumers / producers. 

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
  curl -H"X-Vault-Token:${VAULT_TOKEN}" -XPUT -d@json/enable-pki.json http://localhost:8200/v1/sys/mounts/pki -v
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
