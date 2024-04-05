FROM rust:1.75.0-alpine as compile
WORKDIR /usr/project
RUN apk add cmake make gcc clang15 musl-dev postgresql16 postgresql16-dev openssl-dev git
RUN head -c 5 /dev/random > random_bytes && git clone https://github.com/Intersubjective/meritrank-psql-connector.git
WORKDIR /usr/project/meritrank-psql-connector
ENV RUSTFLAGS="-Ctarget-feature=-crt-static"
RUN cargo install --locked --version=0.11.2 cargo-pgrx
RUN cargo pgrx init --pg16 pg_config
RUN cargo pgrx package

FROM postgis/postgis:16-3.4-alpine
COPY --from=compile /usr/project/meritrank-psql-connector/target/release/pgmer2-pg16/usr/lib/postgresql16/pgmer2.so /usr/local/lib/postgresql/pgmer2.so
COPY --from=compile /usr/project/meritrank-psql-connector/target/release/pgmer2-pg16/usr/share/postgresql16/extension/pgmer2.control /usr/local/share/postgresql/extension/pgmer2.control
COPY --from=compile /usr/project/meritrank-psql-connector/target/release/pgmer2-pg16/usr/share/postgresql16/extension/pgmer2--0.1.0.sql /usr/local/share/postgresql/extension/pgmer2--0.1.0.sql
ADD 20_pgmer2.sh /docker-entrypoint-initdb.d/20_pgmer2.sh
# ENV POSTGRES_PASSWORD=1
ENV POSTGRES_HOST_AUTH_METHOD=trust
# ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh", "postgres"]
