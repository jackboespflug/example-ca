#!/bin/bash

if [ $# -lt 1 ]; then
  echo "usage:  ca-certs.sh Password"
  echo "   ex:  ca-certs.sh yuletide"
  exit
fi


#----------------------------------------------------------------
# Prepare Default Values
#----------------------------------------------------------------

DEFAULT_PW=${1}


#----------------------------------------------------------------
# ROOT CA
#----------------------------------------------------------------

# Prepare Root CA diretories
mkdir -p ca/root-ca/private ca/root-ca/db crl certs keystores
chmod 700 ca/root-ca/private
chmod 700 keystores

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
# Truststores
#----------------------------------------------------------------

keytool \
  -import \
  -file ca/root-ca.crt \
  -alias rootca \
  -noprompt \
  -keystore keystores/truststore.jks \
  -storepass ${DEFAULT_PW}


keytool \
  -importkeystore \
  -srckeystore keystores/truststore.jks \
  -srcstorepass ${DEFAULT_PW} \
  -srcstoretype jks \
  -destkeystore keystores/truststore.p12 \
  -deststorepass ${DEFAULT_PW} \
  -deststoretype pkcs12


if [[ "$OSTYPE" == "darwin"* ]]; then
  base64 \
    -b 0 \
    -i keystores/truststore.jks \
    -o keystores/truststore.jks.b64
else
  base64 \
    -w 0 \
    -i keystores/truststore.jks \
    -o keystores/truststore.jks.b64
fi
