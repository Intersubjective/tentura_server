#!/bin/ash
envsubst < /etc/nginx/nginx.conf > /var/run/openresty/nginx.conf \
    && openresty -t -c /var/run/openresty/nginx.conf \
    && openresty -s reload -c /var/run/openresty/nginx.conf
