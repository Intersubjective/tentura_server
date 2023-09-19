#!/bin/sh
cd ../conf

# Key for resty-acme
if test -f account_key.pem; then
  echo "skip: account_key.pem exists"
else
  openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:4096 -out account_key.pem
fi

# Fallback ec_cert for nginx config
if test -f ec_key.pem || test -f ec_cert.pem; then
  echo "skip: ec_key.pem or ec_cert.pem exists"
else
  openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:secp256k1 -days 3650 -nodes -keyout ec_key.pem -out ec_cert.pem
fi

# Fallback rsa_cert for nginx config
if test -f rsa_key.pem || test -f rsa_cert.pem; then
  echo "skip: rsa_key.pem or rsa_cert.pem exists"
else
  openssl req -x509 -nodes -days 3650 -newkey rsa:2048 -nodes -keyout rsa_key.pem -out rsa_cert.pem
fi

# DH params for nginx
if test -f dhparam.pem; then
  echo "skip: dhparam.pem exists"
else
  openssl dhparam -out dhparam.pem 4096
fi

# Keys for resty-jwt
if test -f jwt_private.pem || test -f jwt_public.pem; then
  echo "skip: jwt_private.pem exists"
else
  openssl ecparam -name secp256k1 > jwt_private.pem
  openssl ecparam -name secp256k1 -genkey -noout >> jwt_private.pem
  openssl ec -in jwt_private.pem -pubout -out jwt_public.pem
fi
