FROM openresty/openresty:alpine

ADD https://github.com/a8m/envsubst/releases/download/v1.4.2/envsubst-Linux-x86_64 /usr/local/bin/envsubst
# ADD --checksum=sha256:a216fad03fb21a5459f57b3e8e02598679229d52e4b24d0c6ed0c46d90d5af3b https://github.com/a8m/envsubst/releases/download/v1.4.2/envsubst-Linux-x86_64 /usr/local/bin/envsubst

RUN chmod +x /usr/local/bin/envsubst \
  && apk add --no-cache curl perl libsodium libsodium-dev

RUN opm get jprjr/luasodium \
  && opm get spacewander/luafilesystem \
  && opm install fffonion/lua-resty-acme \
  # && opm get openresty/lua-resty-upload \
  # && opm get antonheryanto/lua-resty-post \
  && echo "All done!"

# ADD ./lib/* /usr/local/openresty/site/lualib/
