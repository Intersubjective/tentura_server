## Installation

1. Run `./openresty/scripts/create_cert_and_keys.sh`
2. Build images (docker build --no-cache -t vbulavintsev/openresty-tentura:latest -t vbulavintsev/openresty-tentura:v0.0.0 .)
3. Run containers (docker compose up -d)
4. `chown nobody:nogroup /etc/nginx/cert`(acme.autossl cert storage)
5. apply SQL commands in `hasura/schema.sql` to Postgres (Hasura schema and MeritRank-related triggers)
