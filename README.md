## Installation

1. Set secrets described in `compose.yaml` in `.env` file
2. If need, copy `compose.override.example.yaml` to `compose.override.yaml` and modify
3. Run containers (docker compose up -d)
4. `chown nobody:nogroup /etc/nginx/cert`(acme.autossl cert storage)
5. apply SQL commands in `hasura/schema.sql` to Postgres (Hasura schema and MeritRank-related triggers)
6. upload `hasura/metadata.json` in Hasura console


## Development

1. Run `./openresty/scripts/create_cert_and_keys.sh`
2. Build images (docker build --no-cache -t vbulavintsev/openresty-tentura:vX.Y.Z .)


## Backup and restore data

backup schema and data:
`docker exec -t postgres pg_dump --inserts -U postgres --schema public > dump_all.sql`

restore:
`cat dump_all.sql | docker exec -i postgres psql -U postgres`
