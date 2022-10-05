#!/bin/bash

if [ $# -lt 4 ]; then
  echo "usage:  script.sh Password DomainName ServerName K8S_Namespace"
  echo "   ex:  script.sh yuletide example.com server example"
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
# ROOT CA
#----------------------------------------------------------------

# Prepare Root CA diretories
mkdir -p ca/root-ca/private ca/root-ca/db crl certs
chmod 700 ca/root-ca/private

# Prepare Root CA database
cp /dev/null ca/root-ca/db/root-ca.db
cp /dev/null ca/root-ca/db/root-ca.db.attr
echo 01 > ca/root-ca/db/root-ca.crt.srl
echo 01 > ca/root-ca/db/root-ca.crl.srl

# create Root CA request
openssl req -new \
    -config etc/root-ca.conf \
    -out ca/root-ca.csr \
    -keyout ca/root-ca/private/root-ca.key \
    -passout pass:${DEFAULT_PW}!

# create Root CA certificate
openssl ca -selfsign \
    -config etc/root-ca.conf \
    -md sha256 \
    -in ca/root-ca.csr \
    -passin pass:${DEFAULT_PW}! \
    -out ca/root-ca.crt \
    -extensions root_ca_ext \
    -batch


#----------------------------------------------------------------
# SIGNING CA
#----------------------------------------------------------------

# Prepare Signing CA directories
mkdir -p ca/signing-ca/private ca/signing-ca/db crl certs
chmod 700 ca/signing-ca/private

# Prepare Signing CA database
cp /dev/null ca/signing-ca/db/signing-ca.db
cp /dev/null ca/signing-ca/db/signing-ca.db.attr
echo 01 > ca/signing-ca/db/signing-ca.crt.srl
echo 01 > ca/signing-ca/db/signing-ca.crl.srl

# create Signing CA request
openssl req -new \
    -config etc/signing-ca.conf \
    -out ca/signing-ca.csr \
    -keyout ca/signing-ca/private/signing-ca.key \
    -passout pass:"${DEFAULT_PW}$"


# create Signing CA certificate
openssl ca \
    -config etc/root-ca.conf \
    -md sha256 \
    -in ca/signing-ca.csr \
    -passin pass:${DEFAULT_PW}! \
    -out ca/signing-ca.crt \
    -extensions signing_ca_ext \
    -batch


#----------------------------------------------------------------
# CA PEM Bundle
#----------------------------------------------------------------

cat ca/signing-ca.crt ca/root-ca.crt > \
    ca/signing-ca-chain.pem


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
  -out keystores/keystore.p12 \
  -passout pass:${DEFAULT_PW}-ks \
  -CAfile ca/signing-ca-chain.pem \
  -chain \
  -caname signingca \
  -caname rootca \
  -name ${DEFAULT_SERVER}

keytool \
  -importkeystore \
  -srcalias ${DEFAULT_SERVER} \
  -srckeypass ${DEFAULT_PW}-ks \
  -srckeystore keystores/keystore.p12 \
  -srcstorepass ${DEFAULT_PW}-ks \
  -srcstoretype PKCS12 \
  -destalias ${DEFAULT_SERVER} \
  -destkeypass ${DEFAULT_PW}-ks \
  -destkeystore keystores/keystore.jks \
  -deststorepass ${DEFAULT_PW}-ks \
  -deststoretype JKS
