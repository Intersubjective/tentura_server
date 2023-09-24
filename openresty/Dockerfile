FROM openresty/openresty:alpine

RUN apk add --no-cache curl perl libsodium libsodium-dev

RUN opm get bungle/lua-resty-template \
  && opm get antonheryanto/lua-resty-post \
  && opm get spacewander/luafilesystem \
  && opm get fffonion/lua-resty-acme \
  && opm get jprjr/luasodium \
  && echo "All done!"

ADD ./app /usr/local/openresty/site/lualib/

ADD ./conf/* /etc/nginx/
