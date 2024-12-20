--
-- PostgreSQL database dump
--

-- Dumped from database version 16.4
-- Dumped by pg_dump version 16.4

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: public; Type: SCHEMA; Schema: -; Owner: pg_database_owner
--

CREATE SCHEMA public;


ALTER SCHEMA public OWNER TO pg_database_owner;

--
-- Name: SCHEMA public; Type: COMMENT; Schema: -; Owner: pg_database_owner
--

COMMENT ON SCHEMA public IS 'standard public schema';


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: beacon; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.beacon (
    id text DEFAULT concat('B', "substring"((gen_random_uuid())::text, '\w{12}'::text)) NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    user_id text NOT NULL,
    title text NOT NULL,
    description text NOT NULL,
    timerange tstzrange,
    enabled boolean DEFAULT true NOT NULL,
    has_picture boolean DEFAULT false NOT NULL,
    comments_count integer DEFAULT 0 NOT NULL,
    lat double precision,
    long double precision,
    context text,
    CONSTRAINT beacon__description_len CHECK ((char_length(description) <= 2048)),
    CONSTRAINT beacon__title_len CHECK ((char_length(title) <= 128)),
    CONSTRAINT beacon_context_name_length CHECK (((char_length(context) >= 3) AND (char_length(context) <= 32)))
);


ALTER TABLE public.beacon OWNER TO postgres;

--
-- Name: beacon_get_is_pinned(public.beacon, json); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.beacon_get_is_pinned(beacon_row public.beacon, hasura_session json) RETURNS boolean
    LANGUAGE sql STABLE
    AS $$

SELECT COALESCE(

(SELECT true AS "is_pinned" FROM beacon_pinned WHERE

  user_id = (hasura_session ->> 'x-hasura-user-id')::TEXT AND beacon_id = beacon_row.id),

  false);

$$;


ALTER FUNCTION public.beacon_get_is_pinned(beacon_row public.beacon, hasura_session json) OWNER TO postgres;

--
-- Name: beacon_get_my_vote(public.beacon, json); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.beacon_get_my_vote(beacon_row public.beacon, hasura_session json) RETURNS integer
    LANGUAGE sql IMMUTABLE
    AS $$
SELECT COALESCE((SELECT amount FROM vote_beacon WHERE subject = (hasura_session ->> 'x-hasura-user-id')::TEXT AND object = beacon_row.id), 0);
$$;


ALTER FUNCTION public.beacon_get_my_vote(beacon_row public.beacon, hasura_session json) OWNER TO postgres;

--
-- Name: mutual_score; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.mutual_score AS
 SELECT ''::text AS src,
    ''::text AS dst,
    (0)::double precision AS src_score,
    (0)::double precision AS dst_score
  WHERE false;


ALTER VIEW public.mutual_score OWNER TO postgres;

--
-- Name: beacon_get_scores(public.beacon, json); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.beacon_get_scores(beacon_row public.beacon, hasura_session json) RETURNS SETOF public.mutual_score
    LANGUAGE sql IMMUTABLE
    AS $$
SELECT
  src,
  dst,
  score_of_src AS src_score,
  score_of_dst AS dst_score
FROM mr_node_score(
  hasura_session ->> 'x-hasura-user-id',
  beacon_row.id,
  COALESCE(hasura_session ->> 'x-hasura-query-context', beacon_row.context)
);
$$;


ALTER FUNCTION public.beacon_get_scores(beacon_row public.beacon, hasura_session json) OWNER TO postgres;

--
-- Name: comment; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.comment (
    id text DEFAULT concat('C', "substring"((gen_random_uuid())::text, '\w{12}'::text)) NOT NULL,
    user_id text NOT NULL,
    content text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    beacon_id text NOT NULL
);


ALTER TABLE public.comment OWNER TO postgres;

--
-- Name: comment_get_my_vote(public.comment, json); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.comment_get_my_vote(comment_row public.comment, hasura_session json) RETURNS integer
    LANGUAGE sql STABLE
    AS $$

  SELECT COALESCE((SELECT amount FROM vote_comment WHERE subject = (hasura_session ->> 'x-hasura-user-id')::TEXT AND object = comment_row.id), 0);

$$;


ALTER FUNCTION public.comment_get_my_vote(comment_row public.comment, hasura_session json) OWNER TO postgres;

--
-- Name: comment_get_scores(public.comment, json); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.comment_get_scores(comment_row public.comment, hasura_session json) RETURNS SETOF public.mutual_score
    LANGUAGE sql IMMUTABLE
    AS $$
SELECT
  src,
  dst,
  score_of_src AS src_score,
  score_of_dst AS dst_score
FROM mr_node_score(
    hasura_session ->> 'x-hasura-user-id',
    comment_row.id,
    COALESCE(
        hasura_session ->> 'x-hasura-query-context',
        (SELECT context FROM (SELECT context FROM beacon WHERE beacon.id = comment_row.beacon_id))
    )
);
$$;


ALTER FUNCTION public.comment_get_scores(comment_row public.comment, hasura_session json) OWNER TO postgres;

--
-- Name: decrement_beacon_comments_count(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.decrement_beacon_comments_count() RETURNS trigger
    LANGUAGE plpgsql
    AS $$

BEGIN

    UPDATE beacon SET comments_count = comments_count - 1 WHERE id = NEW.beacon_id;

    RETURN NEW;

END;

$$;


ALTER FUNCTION public.decrement_beacon_comments_count() OWNER TO postgres;

--
-- Name: graph(text, text, boolean, json); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.graph(focus text, context text, positive_only boolean, hasura_session json) RETURNS SETOF public.mutual_score
    LANGUAGE sql IMMUTABLE
    AS $$
SELECT
  src,
  dst,
  score_of_src AS src_score,
  score_of_dst AS dst_score
FROM
  mr_graph(
    hasura_session ->> 'x-hasura-user-id',
    focus,
    context,
    positive_only,
    0,
    100
  );
$$;


ALTER FUNCTION public.graph(focus text, context text, positive_only boolean, hasura_session json) OWNER TO postgres;

--
-- Name: increment_beacon_comments_count(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.increment_beacon_comments_count() RETURNS trigger
    LANGUAGE plpgsql
    AS $$

BEGIN

    UPDATE beacon SET comments_count = comments_count + 1 WHERE id = NEW.beacon_id;

    RETURN NEW;

END;

$$;


ALTER FUNCTION public.increment_beacon_comments_count() OWNER TO postgres;

--
-- Name: meritrank_init(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.meritrank_init() RETURNS integer
    LANGUAGE plpgsql IMMUTABLE
    AS $$
DECLARE
  _count integer := 0;
  _total integer := 0;
BEGIN
  -- Edge from User to Zero
  SELECT count(*) INTO STRICT _count FROM (
    SELECT mr_put_edge(edges.src, edges.dst, 1, '') FROM (
      SELECT "user".id AS src,
        'U000000000000' AS dst
      FROM "user" WHERE ("user".id <> 'U000000000000'::text)
    ) AS edges);
  _total := _count;

  -- Edge from User to User (votes)
  SELECT count(*) INTO STRICT _count FROM (
    SELECT mr_put_edge(edges.src, edges.dst, edges.amount, '') FROM (
      SELECT vote_user.subject AS src,
        vote_user.object AS dst,
        vote_user.amount AS amount
      FROM vote_user
    ) AS edges);
  _total := _total + _count;

  -- Edge from User to Beacon
  SELECT count(*) INTO STRICT _count FROM (
    SELECT mr_put_edge(edges.src, edges.dst, 1, edges.context) FROM (
      SELECT beacon.user_id AS src,
        beacon.id AS dst,
        beacon.context AS context
      FROM beacon
    ) AS edges);
  _total := _total + _count;

  -- Edge from Beacon to User
  SELECT count(*) INTO STRICT _count FROM (
    SELECT mr_put_edge(edges.src, edges.dst, 1, edges.context) FROM (
      SELECT beacon.id AS src,
        beacon.user_id AS dst,
        beacon.context AS context
      FROM beacon
    ) AS edges);
  _total := _total + _count;

  -- Edge from User to Beacon (votes)
  SELECT count(*) INTO STRICT _count FROM (
    SELECT mr_put_edge(edges.src, edges.dst, edges.amount, edges.context) FROM (
      SELECT vote_beacon.subject AS src,
        vote_beacon.object AS dst,
        vote_beacon.amount AS amount,
        beacon.context AS context
      FROM vote_beacon JOIN beacon ON beacon.id = vote_beacon.object
    ) AS edges);
  _total := _total + _count;

  -- Edge from User to Comment
  SELECT count(*) INTO STRICT _count FROM (
    SELECT mr_put_edge(edges.src, edges.dst, 1, edges.context) FROM (
      SELECT "comment".user_id AS src,
        "comment".id AS dst,
        beacon.context AS context
      FROM "comment" JOIN beacon ON "comment".beacon_id = beacon.id
    ) AS edges);
  _total := _total + _count;

  -- Edge from Comment to User
  SELECT count(*) INTO STRICT _count FROM (
    SELECT mr_put_edge(edges.src, edges.dst, 1, edges.context) FROM (
      SELECT "comment".id AS src,
        "comment".user_id AS dst,
        beacon.context AS context
      FROM "comment" JOIN beacon ON "comment".beacon_id = beacon.id
    ) AS edges);
  _total := _total + _count;

  -- Edge from User to Comment (votes)
  SELECT count(*) INTO STRICT _count FROM (
    SELECT mr_put_edge(edges.src, edges.dst, edges.amount, edges.context) FROM (
      SELECT vote_comment.subject AS src,
        vote_comment.object AS dst,
        vote_comment.amount AS amount,
        beacon.context AS context
      FROM vote_comment JOIN "comment" ON "comment".id = vote_comment.object JOIN beacon ON beacon.id = "comment".beacon_id
    ) AS edges);
  _total := _total + _count;

  -- Read Updates Filters
  SELECT count(*) INTO STRICT _count FROM (
    SELECT mr_set_new_edges_filter(user_id, filter) FROM user_updates
  );
  _total := _total + _count;

  RETURN _total;
END;
$$;


ALTER FUNCTION public.meritrank_init() OWNER TO postgres;

--
-- Name: my_field(text, json); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.my_field(context text, hasura_session json) RETURNS SETOF public.mutual_score
    LANGUAGE sql IMMUTABLE
    AS $$
SELECT
  src,
  dst,
  score_of_src AS src_score,
  score_of_dst AS dst_score
FROM
  mr_scores(
    hasura_session ->> 'x-hasura-user-id',
    true,
    context,
    'B',
    null,
    null,
    '0',
    null,
    0,
    100
  );
$$;


ALTER FUNCTION public.my_field(context text, hasura_session json) OWNER TO postgres;

--
-- Name: notify_meritrank_beacon_mutation(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.notify_meritrank_beacon_mutation() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    IF (TG_OP = 'INSERT') THEN
        PERFORM mr_put_edge(NEW.id, NEW.user_id, 1::double precision, NEW.context);
        PERFORM mr_put_edge(NEW.user_id, NEW.id, 1::double precision, NEW.context);
    ELSIF (TG_OP = 'DELETE') THEN
        PERFORM mr_delete_edge(OLD.id, OLD.user_id, OLD.context);
        PERFORM mr_delete_edge(OLD.user_id, OLD.id, OLD.context);
    END IF;
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.notify_meritrank_beacon_mutation() OWNER TO postgres;

--
-- Name: notify_meritrank_comment_mutation(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.notify_meritrank_comment_mutation() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    context text;
BEGIN
    SELECT beacon.context INTO context FROM beacon WHERE beacon.id = NEW.beacon_id;
    IF (TG_OP = 'INSERT') THEN
        PERFORM mr_put_edge(NEW.id, NEW.user_id, 1::double precision, context);
        PERFORM mr_put_edge(NEW.user_id, NEW.id, 1::double precision, context);
    ELSIF (TG_OP = 'DELETE') THEN
        PERFORM mr_delete_edge(OLD.id, OLD.user_id, context);
        PERFORM mr_delete_edge(OLD.user_id, OLD.id, context);
    END IF;
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.notify_meritrank_comment_mutation() OWNER TO postgres;

--
-- Name: notify_meritrank_context_mutation(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.notify_meritrank_context_mutation() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    IF (TG_OP = 'INSERT') THEN
        PERFORM mr_create_context(NEW.context_name);
    END IF;
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.notify_meritrank_context_mutation() OWNER TO postgres;

--
-- Name: notify_meritrank_user_mutation(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.notify_meritrank_user_mutation() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    IF (TG_OP = 'INSERT') THEN
        PERFORM mr_put_edge(NEW.id, 'U000000000000', 1::double precision, ''::text);
    ELSIF (TG_OP = 'DELETE') THEN
        PERFORM mr_delete_edge(OLD.id, 'U000000000000', ''::text);
    END IF;
  RETURN NEW;
END;
$$;


ALTER FUNCTION public.notify_meritrank_user_mutation() OWNER TO postgres;

--
-- Name: notify_meritrank_vote_beacon_mutation(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.notify_meritrank_vote_beacon_mutation() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    context text;
BEGIN
    SELECT beacon.context INTO STRICT context FROM beacon WHERE beacon.id = NEW.object;
    IF (TG_OP = 'INSERT' OR TG_OP = 'UPDATE') THEN
        PERFORM mr_put_edge(NEW.subject, NEW.object, (NEW.amount)::double precision, context);
    ELSIF (TG_OP = 'DELETE') THEN
        PERFORM mr_delete_edge(OLD.subject, OLD.object, context);
    END IF;
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.notify_meritrank_vote_beacon_mutation() OWNER TO postgres;

--
-- Name: notify_meritrank_vote_comment_mutation(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.notify_meritrank_vote_comment_mutation() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    context text;
    beacon_id text;
BEGIN
    SELECT comment.beacon_id INTO beacon_id FROM comment WHERE comment.id = NEW.object;
    SELECT beacon.context INTO context FROM beacon WHERE beacon.id = beacon_id;
    IF (TG_OP = 'INSERT' OR TG_OP = 'UPDATE') THEN
        PERFORM mr_put_edge(NEW.subject, NEW.object, (NEW.amount)::double precision, context);
    ELSIF (TG_OP = 'DELETE') THEN
        PERFORM mr_delete_edge(OLD.subject, OLD.object, context);
    END IF;
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.notify_meritrank_vote_comment_mutation() OWNER TO postgres;

--
-- Name: notify_meritrank_vote_user_mutation(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.notify_meritrank_vote_user_mutation() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    IF (TG_OP = 'INSERT' OR TG_OP = 'UPDATE') THEN
        PERFORM mr_put_edge(NEW.subject, NEW.object, (NEW.amount)::double precision, ''::text);
    ELSIF (TG_OP = 'DELETE') THEN
        PERFORM mr_delete_edge(OLD.subject, OLD.object, ''::text);
    END IF;
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.notify_meritrank_vote_user_mutation() OWNER TO postgres;

--
-- Name: rating(text, json); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.rating(context text, hasura_session json) RETURNS SETOF public.mutual_score
    LANGUAGE sql IMMUTABLE
    AS $$
SELECT
    src,
    dst,
    score_of_src AS src_score,
    score_of_dst AS dst_score
FROM mr_mutual_scores(hasura_session->>'x-hasura-user-id', context);
$$;


ALTER FUNCTION public.rating(context text, hasura_session json) OWNER TO postgres;

--
-- Name: set_current_timestamp_updated_at(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.set_current_timestamp_updated_at() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
  _new record;
BEGIN
  _new := NEW;
  _new."updated_at" = NOW();
  RETURN _new;
END;
$$;


ALTER FUNCTION public.set_current_timestamp_updated_at() OWNER TO postgres;

--
-- Name: edge; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.edge AS
 SELECT ''::text AS src,
    ''::text AS dst,
    (0)::double precision AS score
  WHERE false;


ALTER VIEW public.edge OWNER TO postgres;

--
-- Name: updates(text, json); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.updates(prefix text, hasura_session json) RETURNS SETOF public.edge
    LANGUAGE sql
    AS $$
WITH new_edges AS (
  SELECT
    *
  FROM
    mr_fetch_new_edges(hasura_session ->> 'x-hasura-user-id', prefix)
),
new_filter AS (
  INSERT INTO
    user_updates
  VALUES(
      hasura_session ->> 'x-hasura-user-id',
      mr_get_new_edges_filter(hasura_session ->> 'x-hasura-user-id')
    ) ON CONFLICT DO NOTHING
)
SELECT
  *
FROM
  new_edges;
$$;


ALTER FUNCTION public.updates(prefix text, hasura_session json) OWNER TO postgres;

--
-- Name: user; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public."user" (
    id text DEFAULT concat('U', "substring"((gen_random_uuid())::text, '\w{12}'::text)) NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    title text DEFAULT ''::text NOT NULL,
    description text DEFAULT ''::text NOT NULL,
    has_picture boolean DEFAULT false NOT NULL,
    public_key text NOT NULL,
    CONSTRAINT user__description_len CHECK ((char_length(description) <= 2048)),
    CONSTRAINT user__title_len CHECK ((char_length(title) <= 128))
);


ALTER TABLE public."user" OWNER TO postgres;

--
-- Name: user_get_my_vote(public."user", json); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.user_get_my_vote(user_row public."user", hasura_session json) RETURNS integer
    LANGUAGE sql STABLE
    AS $$
SELECT COALESCE((SELECT amount FROM vote_user WHERE subject = (hasura_session ->> 'x-hasura-user-id')::TEXT AND object = user_row.id), 0);
$$;


ALTER FUNCTION public.user_get_my_vote(user_row public."user", hasura_session json) OWNER TO postgres;

--
-- Name: user_get_scores(public."user", json); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.user_get_scores(user_row public."user", hasura_session json) RETURNS SETOF public.mutual_score
    LANGUAGE sql IMMUTABLE
    AS $$
SELECT
  src,
  dst,
  score_of_src AS src_score,
  score_of_dst AS dst_score
FROM mr_node_score(
    hasura_session ->> 'x-hasura-user-id',
    user_row.id,
    hasura_session ->> 'x-hasura-query-context'
)
$$;


ALTER FUNCTION public.user_get_scores(user_row public."user", hasura_session json) OWNER TO postgres;

--
-- Name: beacon_pinned; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.beacon_pinned (
    user_id text NOT NULL,
    beacon_id text NOT NULL
);


ALTER TABLE public.beacon_pinned OWNER TO postgres;

--
-- Name: message; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.message (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    subject text NOT NULL,
    object text NOT NULL,
    message text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    delivered boolean DEFAULT false NOT NULL,
    CONSTRAINT message_message_length CHECK ((char_length(message) > 0))
);


ALTER TABLE public.message OWNER TO postgres;

--
-- Name: user_context; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.user_context (
    user_id text NOT NULL,
    context_name text NOT NULL,
    CONSTRAINT user_context_name_length CHECK (((char_length(context_name) >= 3) AND (char_length(context_name) <= 32)))
);


ALTER TABLE public.user_context OWNER TO postgres;

--
-- Name: user_updates; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.user_updates (
    user_id text NOT NULL,
    filter bytea NOT NULL
);


ALTER TABLE public.user_updates OWNER TO postgres;

--
-- Name: vote_beacon; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.vote_beacon (
    subject text NOT NULL,
    object text NOT NULL,
    amount integer NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


ALTER TABLE public.vote_beacon OWNER TO postgres;

--
-- Name: vote_comment; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.vote_comment (
    subject text NOT NULL,
    object text NOT NULL,
    amount integer NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


ALTER TABLE public.vote_comment OWNER TO postgres;

--
-- Name: vote_user; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.vote_user (
    subject text NOT NULL,
    object text NOT NULL,
    amount integer NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


ALTER TABLE public.vote_user OWNER TO postgres;

--
-- Data for Name: user; Type: TABLE DATA; Schema: public; Owner: postgres
--

INSERT INTO public."user" VALUES ('U000000000000', '2023-12-20 23:37:34.043065+00', '2024-07-23 22:35:05.950428+00', 'Tentura', 'Kind a black hole', true, 'nologin');

--
-- Name: beacon_pinned beacon_pinned_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.beacon_pinned
    ADD CONSTRAINT beacon_pinned_pkey PRIMARY KEY (user_id, beacon_id);


--
-- Name: beacon beacon_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.beacon
    ADD CONSTRAINT beacon_pkey PRIMARY KEY (id);


--
-- Name: comment comment_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.comment
    ADD CONSTRAINT comment_pkey PRIMARY KEY (id);


--
-- Name: message message_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.message
    ADD CONSTRAINT message_pkey PRIMARY KEY (id);


--
-- Name: user_context user_context_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.user_context
    ADD CONSTRAINT user_context_pkey PRIMARY KEY (user_id, context_name);


--
-- Name: user user_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."user"
    ADD CONSTRAINT user_pkey PRIMARY KEY (id);


--
-- Name: user user_public_key_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."user"
    ADD CONSTRAINT user_public_key_key UNIQUE (public_key);


--
-- Name: user_updates user_updates_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.user_updates
    ADD CONSTRAINT user_updates_pkey PRIMARY KEY (user_id);


--
-- Name: vote_beacon vote_beacon_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.vote_beacon
    ADD CONSTRAINT vote_beacon_pkey PRIMARY KEY (subject, object);


--
-- Name: vote_comment vote_comment_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.vote_comment
    ADD CONSTRAINT vote_comment_pkey PRIMARY KEY (subject, object);


--
-- Name: vote_user vote_user_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.vote_user
    ADD CONSTRAINT vote_user_pkey PRIMARY KEY (subject, object);


--
-- Name: beacon_author_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX beacon_author_id ON public.beacon USING btree (user_id);


--
-- Name: message_by_object; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX message_by_object ON public.message USING btree (object);


--
-- Name: message_by_subject; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX message_by_subject ON public.message USING btree (subject);


--
-- Name: comment decrement_beacon_comments_count; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER decrement_beacon_comments_count AFTER DELETE ON public.comment FOR EACH ROW EXECUTE FUNCTION public.decrement_beacon_comments_count();


--
-- Name: comment increment_beacon_comments_count; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER increment_beacon_comments_count AFTER INSERT ON public.comment FOR EACH ROW EXECUTE FUNCTION public.increment_beacon_comments_count();


--
-- Name: beacon notify_meritrank_beacon_mutation; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER notify_meritrank_beacon_mutation AFTER INSERT OR DELETE ON public.beacon FOR EACH ROW EXECUTE FUNCTION public.notify_meritrank_beacon_mutation();


--
-- Name: comment notify_meritrank_comment_mutation; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER notify_meritrank_comment_mutation AFTER INSERT OR DELETE ON public.comment FOR EACH ROW EXECUTE FUNCTION public.notify_meritrank_comment_mutation();


--
-- Name: user_context notify_meritrank_context_mutation; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER notify_meritrank_context_mutation AFTER INSERT ON public.user_context FOR EACH ROW EXECUTE FUNCTION public.notify_meritrank_context_mutation();


--
-- Name: user notify_meritrank_user_mutation; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER notify_meritrank_user_mutation AFTER INSERT OR DELETE ON public."user" FOR EACH ROW EXECUTE FUNCTION public.notify_meritrank_user_mutation();


--
-- Name: vote_beacon notify_meritrank_vote_beacon_mutation; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER notify_meritrank_vote_beacon_mutation AFTER INSERT OR UPDATE ON public.vote_beacon FOR EACH ROW EXECUTE FUNCTION public.notify_meritrank_vote_beacon_mutation();


--
-- Name: vote_comment notify_meritrank_vote_comment_mutation; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER notify_meritrank_vote_comment_mutation AFTER INSERT OR UPDATE ON public.vote_comment FOR EACH ROW EXECUTE FUNCTION public.notify_meritrank_vote_comment_mutation();


--
-- Name: vote_user notify_meritrank_vote_user_mutation; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER notify_meritrank_vote_user_mutation AFTER INSERT OR UPDATE ON public.vote_user FOR EACH ROW EXECUTE FUNCTION public.notify_meritrank_vote_user_mutation();


--
-- Name: beacon set_public_beacon_updated_at; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER set_public_beacon_updated_at BEFORE UPDATE ON public.beacon FOR EACH ROW EXECUTE FUNCTION public.set_current_timestamp_updated_at();


--
-- Name: TRIGGER set_public_beacon_updated_at ON beacon; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON TRIGGER set_public_beacon_updated_at ON public.beacon IS 'trigger to set value of column "updated_at" to current timestamp on row update';


--
-- Name: message set_public_message_updated_at; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER set_public_message_updated_at BEFORE UPDATE ON public.message FOR EACH ROW EXECUTE FUNCTION public.set_current_timestamp_updated_at();


--
-- Name: TRIGGER set_public_message_updated_at ON message; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON TRIGGER set_public_message_updated_at ON public.message IS 'trigger to set value of column "updated_at" to current timestamp on row update';


--
-- Name: user set_public_user_updated_at; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER set_public_user_updated_at BEFORE UPDATE ON public."user" FOR EACH ROW EXECUTE FUNCTION public.set_current_timestamp_updated_at();


--
-- Name: TRIGGER set_public_user_updated_at ON "user"; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON TRIGGER set_public_user_updated_at ON public."user" IS 'trigger to set value of column "updated_at" to current timestamp on row update';


--
-- Name: vote_beacon set_public_vote_beacon_updated_at; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER set_public_vote_beacon_updated_at BEFORE UPDATE ON public.vote_beacon FOR EACH ROW EXECUTE FUNCTION public.set_current_timestamp_updated_at();


--
-- Name: TRIGGER set_public_vote_beacon_updated_at ON vote_beacon; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON TRIGGER set_public_vote_beacon_updated_at ON public.vote_beacon IS 'trigger to set value of column "updated_at" to current timestamp on row update';


--
-- Name: vote_comment set_public_vote_comment_updated_at; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER set_public_vote_comment_updated_at BEFORE UPDATE ON public.vote_comment FOR EACH ROW EXECUTE FUNCTION public.set_current_timestamp_updated_at();


--
-- Name: TRIGGER set_public_vote_comment_updated_at ON vote_comment; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON TRIGGER set_public_vote_comment_updated_at ON public.vote_comment IS 'trigger to set value of column "updated_at" to current timestamp on row update';


--
-- Name: vote_user set_public_vote_user_updated_at; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER set_public_vote_user_updated_at BEFORE UPDATE ON public.vote_user FOR EACH ROW EXECUTE FUNCTION public.set_current_timestamp_updated_at();


--
-- Name: TRIGGER set_public_vote_user_updated_at ON vote_user; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON TRIGGER set_public_vote_user_updated_at ON public.vote_user IS 'trigger to set value of column "updated_at" to current timestamp on row update';


--
-- Name: beacon_pinned beacon_pinned_beacon_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.beacon_pinned
    ADD CONSTRAINT beacon_pinned_beacon_id_fkey FOREIGN KEY (beacon_id) REFERENCES public.beacon(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: beacon_pinned beacon_pinned_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.beacon_pinned
    ADD CONSTRAINT beacon_pinned_user_id_fkey FOREIGN KEY (user_id) REFERENCES public."user"(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: beacon beacon_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.beacon
    ADD CONSTRAINT beacon_user_id_fkey FOREIGN KEY (user_id) REFERENCES public."user"(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: comment comment_beacon_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.comment
    ADD CONSTRAINT comment_beacon_id_fkey FOREIGN KEY (beacon_id) REFERENCES public.beacon(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: comment comment_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.comment
    ADD CONSTRAINT comment_user_id_fkey FOREIGN KEY (user_id) REFERENCES public."user"(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: message message_object_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.message
    ADD CONSTRAINT message_object_fkey FOREIGN KEY (object) REFERENCES public."user"(id) ON UPDATE RESTRICT ON DELETE CASCADE;


--
-- Name: message message_subject_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.message
    ADD CONSTRAINT message_subject_fkey FOREIGN KEY (subject) REFERENCES public."user"(id) ON UPDATE RESTRICT ON DELETE CASCADE;


--
-- Name: user_context user_context_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.user_context
    ADD CONSTRAINT user_context_user_id_fkey FOREIGN KEY (user_id) REFERENCES public."user"(id) ON UPDATE RESTRICT ON DELETE CASCADE;


--
-- Name: user_updates user_updates_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.user_updates
    ADD CONSTRAINT user_updates_user_id_fkey FOREIGN KEY (user_id) REFERENCES public."user"(id) ON UPDATE RESTRICT ON DELETE CASCADE;


--
-- Name: vote_beacon vote_beacon_object_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.vote_beacon
    ADD CONSTRAINT vote_beacon_object_fkey FOREIGN KEY (object) REFERENCES public.beacon(id) ON UPDATE RESTRICT ON DELETE CASCADE;


--
-- Name: vote_beacon vote_beacon_subject_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.vote_beacon
    ADD CONSTRAINT vote_beacon_subject_fkey FOREIGN KEY (subject) REFERENCES public."user"(id) ON UPDATE RESTRICT ON DELETE CASCADE;


--
-- Name: vote_comment vote_comment_object_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.vote_comment
    ADD CONSTRAINT vote_comment_object_fkey FOREIGN KEY (object) REFERENCES public.comment(id) ON UPDATE RESTRICT ON DELETE CASCADE;


--
-- Name: vote_comment vote_comment_subject_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.vote_comment
    ADD CONSTRAINT vote_comment_subject_fkey FOREIGN KEY (subject) REFERENCES public."user"(id) ON UPDATE RESTRICT ON DELETE CASCADE;


--
-- Name: vote_user vote_user_object_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.vote_user
    ADD CONSTRAINT vote_user_object_fkey FOREIGN KEY (object) REFERENCES public."user"(id) ON UPDATE RESTRICT ON DELETE CASCADE;


--
-- Name: vote_user vote_user_subject_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.vote_user
    ADD CONSTRAINT vote_user_subject_fkey FOREIGN KEY (subject) REFERENCES public."user"(id) ON UPDATE RESTRICT ON DELETE CASCADE;


--
-- PostgreSQL database dump complete
--
