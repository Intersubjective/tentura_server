envsubst < /etc/nginx/nginx.conf > /srv/nginx.conf \
    && openresty -t \
    && openresty -s reload
