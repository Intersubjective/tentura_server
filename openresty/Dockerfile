FROM openresty/openresty:alpine

RUN /usr/local/openresty/openssl/bin/openssl dhparam -out /etc/nginx/dhparam.pem 4096 \
  && /usr/local/openresty/openssl/bin/openssl genpkey -algorithm RSA \
    -pkeyopt rsa_keygen_bits:4096 -out /etc/nginx/account.key

RUN apk add --no-cache curl perl libsodium libsodium-dev

RUN opm get jprjr/luasodium \
  && opm get fffonion/lua-resty-acme \
  && opm get antonheryanto/lua-resty-post \
  && echo "All done!"

# TODO: --checksum=sha256:a216fad03fb21a5459f57b3e8e02598679229d52e4b24d0c6ed0c46d90d5af3b
ADD --chmod=755 https://github.com/a8m/envsubst/releases/download/v1.4.2/envsubst-Linux-x86_64 /usr/local/bin/envsubst

ADD --chmod=755 ./reload.sh /usr/local/bin/

ADD ./app /usr/local/openresty/site/lualib/

ADD ./conf/* /etc/nginx/
