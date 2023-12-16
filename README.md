## Installation

1. Run `./openresty/scripts/create_cert_and_keys.sh`
2. Build images
3. Run containers
4. `chown nobody:nogroup /etc/nginx/cert`(acme.autossl cert storage)
5. apply SQL commands in `hasura/schema.sql` to Postgres (Hasura schema
   and MeritRank-related triggers)
