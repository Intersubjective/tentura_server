Copyright: Vadim Bulavintsev (GPL v2)

# MeritRank Python Web service

This repository contains an ASGI and a Dockerfile for a web service calculating and serving MeritRank scores.

## HTTP API usage (ASGI)
The basic usage is covered in the test suite. 
To run the FastAPI-based ASGI implementation:
```commandline
poetry install
poetry shell
uvicorn meritrank_service.asgi:create_meritrank_app --reload --factory
```
If all runs fine, you should be able to point your browser 
to `http://127.0.0.1:8000/docs`, see the autogenerated Swagger documentation
and experiment with the API in-browser.

### Loading edges at service startup
To load edges from Postgres database on init, add the database URL to
the environment variable `POSTGRES_DB_URL`. If the variable is non-null, 
the ASGI will try to connect to the database and load all the contents
of the `edges` table. The table is expected to be in the format `src(str), dst(str), amount(float)`

Example:
```commandline
env POSTGRES_DB_URL="postgres://postgres:12345678@localhost:54321/postgres" uvicorn meritrank_service.asgi:create_meritrank_app --reload --factory

```

### Subscribing to updates from Postgres
Meritrank-service can subscribe to receive edges data from Postgres in real-time by using Postgres `NOTIFY-LISTEN` mechanism.
To use it, you first have to add some `NOTIFY` triggers to Postgres:
   <details>
     <summary> Example SQL trigger for notification </summary>

```SQL
CREATE OR REPLACE FUNCTION notify_trigger() RETURNS trigger AS $$
DECLARE
    json_message text;
BEGIN
    -- Serialize the tuple into a JSON string
    json_message := row_to_json(row(NEW.src, NEW.dest, NEW.weight))::text;
    
    -- Notify the channel with the JSON string
    PERFORM pg_notify('edges', json_message);
    
    -- Return the new row to indicate a successful operation
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER my_trigger
AFTER INSERT OR UPDATE ON my_table
FOR EACH ROW EXECUTE FUNCTION notify_trigger();
```

 </details>

Meritrank-service expects the data to be in JSON format, the same as used in `add_edge` REST call.
To enable the listen feature, run the service with
`POSTGRES_EDGES_CHANNEL` envirionment variable set to the corresponding
Postgres `NOTIFY` channel, e.g. `POSTGRES_EDGES_CHANNEL=edges`. (And don't forget to set `POSTGRES_DB_URL` too, of course)


### Logging
You can enable logging by setting the environment variable `MERITRANK_DEBUG_LEVEL` to the desirable Python logging level, e.g. `MERITRANK_DEBUG_LEVEL=INFO`. By default, the error level is set to `ERROR`, meaning that only errors are logged.


## Docker
To build and run the docker container:

```commandline
sudo docker build --no-cache -t meritrank  .
docker run -d -p 127.0.0.1:8888:8000 meritrank
```
