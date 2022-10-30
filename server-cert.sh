#!/bin/bash

if [ $# -lt 4 ]; then
  echo "usage:  server-cert.sh Password DomainName ServerName K8S_Namespace"
  echo "   ex:  server-cert.sh yuletide example.com server example"
  exit
fi


#----------------------------------------------------------------
# Prepare Default Values
#----------------------------------------------------------------

DEFAULT_PW=${1}
DEFAULT_SAN=${2}
DEFAULT_SERVER=${3}
DEFAULT_NS=${4}


#----------------------------------------------------------------
# SIGNED CERTS
#----------------------------------------------------------------

# create server request
SAN=DNS:${DEFAULT_SAN} \
SERVER=${DEFAULT_SERVER} \
openssl req -new \
    -config etc/${DEFAULT_SERVER}.conf \
    -out certs/${DEFAULT_SERVER}.csr \
    -keyout certs/${DEFAULT_SERVER}.key \
    -passout pass:${DEFAULT_PW} \
    -batch

# create server certificate
openssl ca \
    -config etc/signing-ca.conf \
    -md sha256 \
    -in certs/${DEFAULT_SERVER}.csr \
    -passin pass:${DEFAULT_PW}$ \
    -out certs/${DEFAULT_SERVER}.crt \
    -extensions server_ext \
    -batch


# create k8s service request
NAMESPACE=${DEFAULT_NS} \
openssl req -new \
    -config etc/k8s-wildcard.conf \
    -out certs/k8s-${DEFAULT_NS}-wildcard.csr \
    -keyout certs/k8s-${DEFAULT_NS}-wildcard.key \
    -passout pass:${DEFAULT_PW} \
    -batch

# create k8s service certificate
NAMESPACE=${DEFAULT_NS} \
openssl ca \
    -config etc/signing-ca.conf \
    -md sha256 \
    -in certs/k8s-${DEFAULT_NS}-wildcard.csr \
    -passin pass:${DEFAULT_PW}$ \
    -out certs/k8s-${DEFAULT_NS}-wildcard.crt \
    -policy any_pol \
    -extensions server_ext \
    -batch


#----------------------------------------------------------------
# Keystores
#----------------------------------------------------------------

# create directories
mkdir -p keystores
chmod 700 keystores

openssl pkcs12 \
  -export \
  -aes256 \
  -in certs/${DEFAULT_SERVER}.crt \
  -inkey certs/${DEFAULT_SERVER}.key \
  -out keystores/keystore.${DEFAULT_SERVER}.p12 \
  -passout pass:${DEFAULT_PW} \
  -CAfile ca/signing-ca-chain.pem \
  -chain \
  -caname signingca \
  -caname rootca \
  -name ${DEFAULT_SERVER}

keytool \
  -importkeystore \
  -srcalias ${DEFAULT_SERVER} \
  -srckeypass ${DEFAULT_PW} \
  -srckeystore keystores/keystore.${DEFAULT_SERVER}.p12 \
  -srcstorepass ${DEFAULT_PW} \
  -srcstoretype pkcs12 \
  -destalias ${DEFAULT_SERVER} \
  -destkeypass ${DEFAULT_PW} \
  -destkeystore keystores/keystore.${DEFAULT_SERVER}.jks \
  -deststorepass ${DEFAULT_PW} \
  -deststoretype jks

if [[ "$OSTYPE" == "darwin"* ]]; then
  base64 \
    -b 0 \
    -i keystores/keystore.${DEFAULT_SERVER}.jks \
    -o keystores/keystore.${DEFAULT_SERVER}.jks.b64
else
  base64 \
    -w 0 \
    -i keystores/keystore.${DEFAULT_SERVER}.jks \
    -o keystores/keystore.${DEFAULT_SERVER}.jks.b64
fi
