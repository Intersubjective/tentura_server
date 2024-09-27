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
  SELECT COALESCE(
    (SELECT amount FROM vote_beacon WHERE subject = (hasura_session ->> 'x-hasura-user-id')::TEXT AND object = beacon_row.id),
    0
  );
$$;


ALTER FUNCTION public.beacon_get_my_vote(beacon_row public.beacon, hasura_session json) OWNER TO postgres;

--
-- Name: beacon_get_score(public.beacon, json); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.beacon_get_score(beacon_row public.beacon, hasura_session json) RETURNS double precision
    LANGUAGE sql IMMUTABLE
    AS $$
SELECT score FROM mr_node_score(hasura_session ->> 'x-hasura-user-id', beacon_row.id, beacon_row.context);
$$;


ALTER FUNCTION public.beacon_get_score(beacon_row public.beacon, hasura_session json) OWNER TO postgres;

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
-- Name: comment_get_score(public.comment, json); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.comment_get_score(comment_row public.comment, hasura_session json) RETURNS double precision
    LANGUAGE sql IMMUTABLE
    AS $$
WITH beacon_row AS (SELECT context FROM beacon WHERE beacon.id = comment_row.beacon_id)
  SELECT score FROM mr_node_score(hasura_session ->> 'x-hasura-user-id', comment_row.id, (SELECT context FROM beacon_row));
$$;


ALTER FUNCTION public.comment_get_score(comment_row public.comment, hasura_session json) OWNER TO postgres;

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
-- Name: edge; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.edge AS
 SELECT ''::text AS src,
    ''::text AS dst,
    (0)::double precision AS score
  WHERE false;


ALTER VIEW public.edge OWNER TO postgres;

--
-- Name: graph(text, text, boolean, json); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.graph(focus text, context text, positive_only boolean, hasura_session json) RETURNS SETOF public.edge
    LANGUAGE sql IMMUTABLE
    AS $$
SELECT src, dst, score FROM mr_graph(
    hasura_session->>'x-hasura-user-id',
    focus,
    context,
    positive_only,
    0,
    100);
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

CREATE FUNCTION public.my_field(context text, hasura_session json) RETURNS SETOF public.edge
    LANGUAGE sql IMMUTABLE
    AS $$
SELECT src, dst, score FROM mr_scores(
    hasura_session->>'x-hasura-user-id',
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
-- Name: rating(text, json); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.rating(context text, hasura_session json) RETURNS SETOF public.mutual_score
    LANGUAGE sql IMMUTABLE
    AS $$
SELECT src, dst, src_score, dst_score FROM mr_mutual_scores(hasura_session->>'x-hasura-user-id', context);
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
-- Name: updates(text, json); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.updates(prefix text, hasura_session json) RETURNS SETOF public.edge
    LANGUAGE sql
    AS $$
WITH new_edges AS (
  SELECT * FROM mr_fetch_new_edges(hasura_session->>'x-hasura-user-id', prefix)
), new_filter AS (
  INSERT INTO user_updates VALUES(
    hasura_session->>'x-hasura-user-id',
    mr_get_new_edges_filter(hasura_session->>'x-hasura-user-id')
  ) ON CONFLICT DO NOTHING
)
  SELECT * FROM new_edges;
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
  SELECT amount FROM vote_user WHERE subject = (hasura_session ->> 'x-hasura-user-id')::TEXT AND object = user_row.id;
$$;


ALTER FUNCTION public.user_get_my_vote(user_row public."user", hasura_session json) OWNER TO postgres;

--
-- Name: user_get_score(public."user", json); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.user_get_score(user_row public."user", hasura_session json) RETURNS double precision
    LANGUAGE sql IMMUTABLE
    AS $$
SELECT score FROM mr_node_score(hasura_session ->> 'x-hasura-user-id', user_row.id, null);
$$;


ALTER FUNCTION public.user_get_score(user_row public."user", hasura_session json) OWNER TO postgres;

--
-- Name: beacon_pinned; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.beacon_pinned (
    user_id text NOT NULL,
    beacon_id text NOT NULL
);


ALTER TABLE public.beacon_pinned OWNER TO postgres;

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
-- Data for Name: beacon; Type: TABLE DATA; Schema: public; Owner: postgres
--

INSERT INTO public.beacon VALUES ('B191f781ace43', '2024-07-17 13:54:44.290498+00', '2024-07-17 13:54:44.290498+00', 'U95f3426b8e5d', 'The new one', 'Could be deleted', '["2024-07-17 00:00:00+00","2024-07-17 00:00:00+00"]', true, false, 0, 30.813015590005648, 31.409375667572064, NULL);
INSERT INTO public.beacon VALUES ('B83ef002b8120', '2024-08-01 15:06:56.121477+00', '2024-08-01 15:06:56.121477+00', 'Ucc76e1b73be0', 'bla bla', 'djsjsjdjs', NULL, true, true, 0, NULL, NULL, NULL);
INSERT INTO public.beacon VALUES ('B03a6fe7fba8a', '2024-08-05 01:24:45.006861+00', '2024-08-05 01:24:45.006861+00', 'Ub01f4ad1b03f', 'First topic with context', 'All in title ', '["2024-08-05 00:00:00+00","2024-08-05 00:00:00+00"]', true, false, 0, NULL, NULL, NULL);
INSERT INTO public.beacon VALUES ('Bed48703df71d', '2024-08-05 22:32:52.709725+00', '2024-08-09 20:47:25.146801+00', 'U0ae9f5d0bf02', 'default con bec', 'jjgchiv', NULL, true, false, 2, NULL, NULL, NULL);
INSERT INTO public.beacon VALUES ('Be64122664ec6', '2024-08-08 18:43:05.631347+00', '2024-08-10 17:25:24.755034+00', 'U0ae9f5d0bf02', 'lala2', 'yct g', NULL, true, true, 1, NULL, NULL, 'tentura-test');
INSERT INTO public.beacon VALUES ('Bea6112348aa2', '2024-08-21 11:13:02.047669+00', '2024-08-21 11:13:02.047669+00', 'U0be96c3b9883', 'Hello world! ', 'say hello to everyone', NULL, true, true, 0, NULL, NULL, NULL);
INSERT INTO public.beacon VALUES ('B91796a98a225', '2024-08-20 12:40:38.315204+00', '2024-08-21 14:13:04.185504+00', 'Uf82dbb4708ba', 'New project for a group ', 'We are running out a new volunteer project and looking forward for a new participants', '["2024-09-01 00:00:00+00","2024-09-07 00:00:00+00"]', true, true, 2, NULL, NULL, NULL);
INSERT INTO public.beacon VALUES ('Baa2a0467a706', '2024-08-22 20:41:10.86845+00', '2024-08-22 20:41:10.86845+00', 'Ub4b46ee7a5e4', 'Мир полон', 'Мир полон физики или чудес - зависит от образования!', NULL, true, true, 0, NULL, NULL, 'Magic');
INSERT INTO public.beacon VALUES ('B500ed1ecb236', '2024-08-05 22:26:44.022367+00', '2024-08-22 20:42:24.144983+00', 'U0ae9f5d0bf02', 'лалалэнд', '', NULL, true, true, 2, NULL, NULL, 'tentura-test');
INSERT INTO public.beacon VALUES ('Bc4603804bacf', '2024-08-25 12:17:10.683889+00', '2024-08-29 16:31:53.064397+00', 'U55272fd6c264', 'Games night', 'Stay up all night ', '["2024-08-30 00:00:00+00","2024-08-31 00:00:00+00"]', true, true, 1, 60.12941309631004, 25.128523528996105, 'game');
INSERT INTO public.beacon VALUES ('Bca63d8a2057b', '2024-08-30 12:50:41.19054+00', '2024-08-30 12:50:41.19054+00', 'Ub01f4ad1b03f', 'Catsar', '', '["2024-08-30 00:00:00+00","2024-08-31 00:00:00+00"]', true, true, 0, NULL, NULL, NULL);
INSERT INTO public.beacon VALUES ('Bc173d5552e2e', '2024-07-11 23:22:01.775678+00', '2024-07-11 23:22:01.775678+00', 'U95f3426b8e5d', 'Okey well do', 'it''s worth to watch', '["2024-07-12 00:00:00+00","2024-07-19 00:00:00+00"]', true, false, 0, NULL, NULL, NULL);
INSERT INTO public.beacon VALUES ('B24f9f2026cec', '2024-07-17 14:36:16.711823+00', '2024-07-17 14:36:16.711823+00', 'U95f3426b8e5d', 'hair the cat', '', NULL, true, false, 0, NULL, NULL, NULL);
INSERT INTO public.beacon VALUES ('Bf97103a947f5', '2024-08-22 21:50:48.933393+00', '2024-08-22 21:50:48.933393+00', 'U3ea0a229ad85', 'The Moon', 'Through telescope!', NULL, true, true, 0, NULL, NULL, 'Photo');
INSERT INTO public.beacon VALUES ('Bf88b19c1112a', '2024-08-21 13:07:02.489575+00', '2024-08-21 13:07:02.489575+00', 'U9de057150efc', 'Test', 'testtettstst', '["2024-08-21 00:00:00+00","2024-09-04 00:00:00+00"]', true, false, 0, 13.209674915095887, 2.0073263985770056, 'tetset');
INSERT INTO public.beacon VALUES ('Bed5126bc655d', '2023-12-21 21:59:41.320134+00', '2024-07-09 12:54:02.863073+00', 'Uc4ebbce44401', 'Hello Tentura Stage', 'первонах', NULL, true, false, 0, NULL, NULL, NULL);
INSERT INTO public.beacon VALUES ('B5e7178dd70bb', '2023-12-22 14:44:47.110205+00', '2024-07-09 12:54:02.863073+00', 'Ucbd309d6fcc0', 'apexiq', 'xcpybr
', NULL, true, false, 0, NULL, NULL, NULL);
INSERT INTO public.beacon VALUES ('Be7145faf15cb', '2023-12-23 12:22:48.44643+00', '2024-07-09 12:54:02.863073+00', 'Ud982a6dee46f', 'apexiq', 'xcpybr
', NULL, false, false, 0, NULL, NULL, NULL);
INSERT INTO public.beacon VALUES ('B47cc49866c37', '2023-12-23 21:52:53.763828+00', '2024-07-09 12:54:02.863073+00', 'Uf5ee43a1b729', 'apexiq', 'xcpybr
', NULL, false, false, 1, NULL, NULL, NULL);
INSERT INTO public.beacon VALUES ('B30bf91bf5845', '2023-12-22 19:07:47.764089+00', '2024-07-09 12:54:02.863073+00', 'Ue6cc7bfa0efd', 'some beacon 3', '', NULL, true, false, 2, NULL, NULL, NULL);
INSERT INTO public.beacon VALUES ('Bb5f87c1621d5', '2023-12-28 08:07:53.80383+00', '2024-07-09 12:54:02.863073+00', 'Ub01f4ad1b03f', 'Titanic', '', NULL, true, false, 1, NULL, NULL, NULL);
INSERT INTO public.beacon VALUES ('Bc896788cd2ef', '2023-11-11 13:58:12.836572+00', '2024-07-09 12:54:02.863073+00', 'U1bcba4fd7175', 'yhvxx', 'hbj
', NULL, true, false, 1, NULL, NULL, NULL);
INSERT INTO public.beacon VALUES ('B5a1c1d3d0140', '2023-09-26 10:56:06.009191+00', '2024-07-09 12:54:02.863073+00', 'Uc3c31b8a022f', 'Cursus turpis massa tincidunt dui ut.', 'Aliquam nulla facilisi cras fermentum.
Nibh venenatis cras sed felis eget.
Eget aliquet nibh praesent tristique magna.
Nibh venenatis cras sed felis eget.', NULL, true, false, 4, NULL, NULL, NULL);
INSERT INTO public.beacon VALUES ('B10d3f548efc4', '2023-10-06 15:17:56.14831+00', '2024-07-09 12:54:02.863073+00', 'U99a0f1f7e6ee', 'титл', 'дескрипл', '["2023-10-06 00:00:00+00","2023-10-31 00:00:00+00"]', true, false, 0, NULL, NULL, NULL);
INSERT INTO public.beacon VALUES ('B8120aa1edccb', '2024-01-26 15:08:09.243372+00', '2024-07-09 12:54:02.863073+00', 'Ue40b938f47a4', 'fgghb', 'vvhhh', NULL, true, false, 0, NULL, NULL, NULL);
INSERT INTO public.beacon VALUES ('B19ea554faf29', '2023-10-08 05:21:13.540346+00', '2024-07-09 12:54:02.863073+00', 'U34252014c05b', 'Too short', '', NULL, true, false, 0, NULL, NULL, NULL);
INSERT INTO public.beacon VALUES ('Bb1e3630d2f4a', '2023-10-08 07:19:54.596971+00', '2024-07-09 12:54:02.863073+00', 'U34252014c05b', 'бикон', 'дескрипон', NULL, true, false, 0, NULL, NULL, NULL);
INSERT INTO public.beacon VALUES ('B944097cdd968', '2024-01-26 15:08:49.32675+00', '2024-07-09 12:54:02.863073+00', 'Ue40b938f47a4', 'gunn', 'vbbbh', '["2024-01-27 00:00:00+00","2024-02-08 00:00:00+00"]', true, false, 0, NULL, NULL, NULL);
INSERT INTO public.beacon VALUES ('Bea16f01b8cc5', '2023-11-21 21:50:05.515567+00', '2024-07-09 12:54:02.863073+00', 'U1df3e39ebe59', 'xbnaap', 'eitsyw
', NULL, true, false, 0, NULL, NULL, NULL);
INSERT INTO public.beacon VALUES ('B92e4a185c654', '2023-10-09 06:15:50.307415+00', '2024-07-09 12:54:02.863073+00', 'U41784ed376c3', 'Title', '', NULL, true, false, 0, NULL, NULL, NULL);
INSERT INTO public.beacon VALUES ('B63fbe1427d09', '2023-09-26 10:56:06.009191+00', '2024-07-09 12:54:02.863073+00', 'U1c285703fc63', 'Vulputate ut pharetra sit amet aliquam id diam maecenas ultricies.', '', NULL, true, false, 2, NULL, NULL, NULL);
INSERT INTO public.beacon VALUES ('Ba5d64165e5d5', '2023-10-19 22:46:03.477827+00', '2024-07-09 12:54:02.863073+00', 'U1e41b5f3adff', 'gggggg', 'hjjvccbvcc', NULL, true, false, 0, NULL, NULL, NULL);
INSERT INTO public.beacon VALUES ('B4f14b223b56d', '2023-10-23 19:56:08.460649+00', '2024-07-09 12:54:02.863073+00', 'Ud04c89aaf453', 'лшгрп', 'нрауц', NULL, true, false, 0, NULL, NULL, NULL);
INSERT INTO public.beacon VALUES ('Be5bb2f3d56cb', '2023-10-27 18:01:03.784898+00', '2024-07-09 12:54:02.863073+00', 'U3c63a9b6115a', '  test ', 'fhvjhff', NULL, true, false, 0, NULL, NULL, NULL);
INSERT INTO public.beacon VALUES ('Bf34ee3bfc12b', '2023-10-10 10:57:30.436727+00', '2024-07-09 12:54:02.863073+00', 'U6240251593cd', 'let s do som', 'bhff', NULL, true, false, 1, NULL, NULL, NULL);
INSERT INTO public.beacon VALUES ('B70df5dbab8c3', '2023-11-08 06:43:00.443136+00', '2024-07-09 12:54:02.863073+00', 'U09cf1f359454', 'Камчатка', '', NULL, true, false, 1, NULL, NULL, NULL);
INSERT INTO public.beacon VALUES ('B3c467fb437b2', '2023-09-26 10:56:06.009191+00', '2024-07-09 12:54:02.863073+00', 'U9e42f6dab85a', 'Imperdiet sed euismod nisi porta lorem mollis aliquam ut.', '', NULL, true, false, 4, NULL, NULL, NULL);
INSERT INTO public.beacon VALUES ('B506fff6cfc22', '2023-12-15 14:57:09.43291+00', '2024-07-09 12:54:02.863073+00', 'Ub7f9dfb6a7a5', 'ggh', '', NULL, true, false, 0, NULL, NULL, NULL);
INSERT INTO public.beacon VALUES ('Bd90a1cf73384', '2023-10-06 15:49:17.225304+00', '2024-07-09 12:54:02.863073+00', 'U99a0f1f7e6ee', 'бикон', '', NULL, true, false, 0, NULL, NULL, NULL);
INSERT INTO public.beacon VALUES ('B0a87a669fc28', '2023-10-07 10:57:31.966935+00', '2024-07-09 12:54:02.863073+00', 'U34252014c05b', 'title', '', NULL, true, false, 0, NULL, NULL, NULL);
INSERT INTO public.beacon VALUES ('B19d70698e3d8', '2024-01-26 12:53:28.488357+00', '2024-07-09 12:54:02.863073+00', 'Uf8bf10852d43', 'tgg', 'ty', NULL, true, false, 0, NULL, NULL, NULL);
INSERT INTO public.beacon VALUES ('B253177f84f08', '2024-01-26 12:53:39.4888+00', '2024-07-09 12:54:02.863073+00', 'Uf8bf10852d43', 'hjjjhhhh', '', NULL, true, false, 0, NULL, NULL, NULL);
INSERT INTO public.beacon VALUES ('B25c85fe0df2d', '2023-09-26 10:56:06.009191+00', '2024-07-09 12:54:02.863073+00', 'Uef7fbf45ef11', 'Magna sit amet purus gravida quis.', '', NULL, true, false, 6, NULL, NULL, NULL);
INSERT INTO public.beacon VALUES ('B4115d364e05b', '2024-01-26 12:54:00.780654+00', '2024-07-09 12:54:02.863073+00', 'Uf8bf10852d43', 'hahahhahaqj', '', NULL, true, false, 0, NULL, NULL, NULL);
INSERT INTO public.beacon VALUES ('Bd7a8bfcf3337', '2023-10-08 16:57:32.125959+00', '2024-07-09 12:54:02.863073+00', 'U02fbd7c8df4c', ' v2 beacon', 'bla', NULL, true, false, 0, NULL, NULL, NULL);
INSERT INTO public.beacon VALUES ('Bdf39d0e1daf5', '2023-09-26 10:56:06.009191+00', '2024-07-09 12:54:02.863073+00', 'Uc1158424318a', 'Cras pulvinar mattis nunc sed blandit libero volutpat sed.', 'Aliquet nec ullamcorper sit amet risus nullam eget felis eget.', NULL, true, false, 10, NULL, NULL, NULL);
INSERT INTO public.beacon VALUES ('Bb78026d99388', '2023-09-26 10:56:06.009191+00', '2024-07-09 12:54:02.863073+00', 'U9a89e0679dec', 'Enim blandit volutpat maecenas volutpat blandit aliquam etiam erat velit.', 'Est pellentesque elit ullamcorper dignissim cras tincidunt lobortis feugiat.', NULL, true, false, 5, NULL, NULL, NULL);
INSERT INTO public.beacon VALUES ('Be29b4af3f7a5', '2023-10-24 16:21:07.295112+00', '2024-07-09 12:54:02.863073+00', 'Uc35c445325f5', 'jugff', 'hjgfer', NULL, true, false, 0, NULL, NULL, NULL);
INSERT INTO public.beacon VALUES ('Bc4addf09b79f', '2023-10-30 17:26:31.185468+00', '2024-07-09 12:54:02.863073+00', 'U0cd6bd2dde4f', 'Фристайло', '', NULL, true, false, 0, NULL, NULL, NULL);
INSERT INTO public.beacon VALUES ('B4f00e7813add', '2023-11-08 07:31:46.106519+00', '2024-07-09 12:54:02.863073+00', 'U09cf1f359454', 'Го, кто-то создал!', '', NULL, true, false, 1, NULL, NULL, NULL);
INSERT INTO public.beacon VALUES ('Bf3a0a1165271', '2023-09-26 10:56:06.009191+00', '2024-07-09 12:54:02.863073+00', 'U9a89e0679dec', 'Orci porta non pulvinar neque laoreet suspendisse interdum consectetur.', 'Tortor id aliquet lectus proin nibh nisl condimentum id venenatis.
Vulputate enim nulla aliquet porttitor lacus luctus accumsan tortor.', '["2023-09-26 13:56:05.639793+00","2023-09-30 13:56:05.639793+00"]', true, false, 3, NULL, NULL, NULL);
INSERT INTO public.beacon VALUES ('B60d725feca77', '2023-09-26 10:56:06.009191+00', '2024-08-24 17:12:38.97049+00', 'U80e22da6d8c4', 'Nunc sed blandit libero volutpat sed.', 'Posuere morbi leo urna molestie at elementum eu facilisis sed.
Aliquam eleifend mi in nulla posuere sollicitudin.', NULL, true, false, 7, NULL, NULL, NULL);
INSERT INTO public.beacon VALUES ('B5eb4c6be535a', '2023-09-26 10:56:06.009191+00', '2024-08-20 22:36:01.952668+00', 'Uad577360d968', 'Ipsum nunc aliquet bibendum enim facilisis gravida.', 'Quisque egestas diam in arcu cursus euismod quis viverra.
Leo a diam sollicitudin tempor id.
Mattis nunc sed blandit libero volutpat sed.', NULL, true, false, 4, NULL, NULL, NULL);
INSERT INTO public.beacon VALUES ('Bd49e3dac97b0', '2023-09-26 10:56:06.009191+00', '2024-07-09 12:54:02.863073+00', 'Uadeb43da4abb', 'Sem et tortor consequat id.', '', '["2023-09-26 13:56:05.639793+00","2023-09-29 13:56:05.639793+00"]', true, false, 11, NULL, NULL, 'Test');
INSERT INTO public.beacon VALUES ('B9c01ce5718d1', '2023-10-05 13:31:36.970851+00', '2024-08-05 21:28:48.932921+00', 'U499f24158a40', 'Котик', 'КОТИК ЖЕ', NULL, true, false, 31, NULL, NULL, 'Fatum');
INSERT INTO public.beacon VALUES ('B79efabc4d8bf', '2023-10-05 13:31:39.977543+00', '2024-08-12 23:11:08.892582+00', 'U499f24158a40', 'Котик', 'КОТИК ЖЕ', NULL, true, false, 8, NULL, NULL, NULL);
INSERT INTO public.beacon VALUES ('Be2b46c17f1da', '2023-09-26 10:56:06.009191+00', '2024-08-24 17:06:11.638998+00', 'U80e22da6d8c4', 'Vitae proin sagittis nisl rhoncus mattis.', 'Ut porttitor leo a diam sollicitudin.', NULL, true, false, 16, NULL, NULL, NULL);
INSERT INTO public.beacon VALUES ('B491d307dfe01', '2023-10-05 13:32:37.746997+00', '2024-08-13 23:04:00.817073+00', 'U499f24158a40', 'для комплекта ', 'ВААГХ ', NULL, true, false, 12, NULL, NULL, NULL);
INSERT INTO public.beacon VALUES ('B4b8fafa86526', '2024-08-05 17:23:32.798477+00', '2024-08-16 13:51:31.773366+00', 'Ub01f4ad1b03f', 'Not little green man', 'They''ll come!', '["2024-08-11 00:00:00+00","2024-08-11 00:00:00+00"]', true, true, 1, 37.99058089301414, 23.73077920747473, 'Fatum');
INSERT INTO public.beacon VALUES ('Ba3c4a280657d', '2023-10-05 13:32:36.792734+00', '2024-08-12 23:09:49.049171+00', 'U499f24158a40', 'для комплекта ', 'ВААГХ ', NULL, true, false, 7, NULL, NULL, NULL);
INSERT INTO public.beacon VALUES ('B7f628ad203b5', '2023-09-26 10:56:06.009191+00', '2024-08-20 22:35:36.746381+00', 'U7a8d8324441d', 'Fermentum leo vel orci porta.', 'Massa enim nec dui nunc mattis enim.
Libero nunc consequat interdum varius sit amet mattis vulputate.', '["2023-09-26 13:56:05.639793+00","2023-10-15 13:56:05.639793+00"]', true, false, 30, NULL, NULL, NULL);
INSERT INTO public.beacon VALUES ('B848aea243dfc', '2024-08-21 13:07:23.777062+00', '2024-08-21 13:07:23.777062+00', 'U9de057150efc', 'test2', 'test2', '["2024-08-21 00:00:00+00","2024-08-21 00:00:00+00"]', true, false, 0, 4.184811870761927, 11.48342677525111, 'test2222');
INSERT INTO public.beacon VALUES ('B3f6f837bc345', '2023-11-01 23:09:36.777224+00', '2024-08-21 16:17:46.654222+00', 'U6d2f25cc4264', 'Избушка', 'Что за слово такое?', NULL, true, false, 2, NULL, NULL, 'Fatum');
INSERT INTO public.beacon VALUES ('B1533941e2773', '2023-11-24 21:53:03.707954+00', '2024-08-21 15:01:45.896041+00', 'U79466f73dc0c', 'Staying ahead of the Curve', 'Technology is constantly evolving and it''s crucial to stay up-to-date with the latest trends ', '["2023-11-30 00:00:00+00","2023-12-02 00:00:00+00"]', true, false, 2, NULL, NULL, NULL);
INSERT INTO public.beacon VALUES ('B5f6a16260bac', '2024-08-05 17:15:53.125214+00', '2024-08-22 21:52:19.540391+00', 'Ub01f4ad1b03f', 'Glamour example', '', NULL, true, true, 1, NULL, NULL, 'Glamour');
INSERT INTO public.beacon VALUES ('B8fabb952bc4b', '2024-08-25 12:19:14.29087+00', '2024-08-25 12:19:14.29087+00', 'U55272fd6c264', 'Был камыш, да спёрла мышь', '', NULL, true, false, 0, NULL, NULL, NULL);
INSERT INTO public.beacon VALUES ('B68d3b36887e4', '2024-08-30 13:18:00.181645+00', '2024-08-30 13:18:00.181645+00', 'U3ea0a229ad85', 'Doing like this', '', NULL, true, true, 0, NULL, NULL, NULL);
INSERT INTO public.beacon VALUES ('B0e230e9108dd', '2023-09-26 10:56:06.009191+00', '2024-07-09 12:54:02.863073+00', 'U9a89e0679dec', 'Tristique sollicitudin nibh sit amet commodo nulla facilisi.', 'Nisl nunc mi ipsum faucibus vitae aliquet nec.
Aliquet sagittis id consectetur purus ut faucibus.
In ornare quam viverra orci sagittis eu volutpat odio facilisis.', NULL, true, false, 5, NULL, NULL, NULL);
INSERT INTO public.beacon VALUES ('B499bfc56e77b', '2023-10-01 10:21:42.404783+00', '2024-07-09 12:54:02.863073+00', 'Uc1158424318a', 'Cras pulvinar mattis nunc sed blandit libero volutpat sed.', 'Risus nullam eget felis eget nunc lobortis.
Mattis rhoncus urna neque viverra justo.', NULL, true, false, 0, NULL, NULL, NULL);
INSERT INTO public.beacon VALUES ('Bf843e315d71b', '2024-01-26 14:27:49.418208+00', '2024-07-09 12:54:02.863073+00', 'Uf6ce05bc4e5a', 'john smith ', 'ghjfjfjfjjfjf', NULL, true, false, 1, NULL, NULL, NULL);
INSERT INTO public.beacon VALUES ('B75a44a52fa29', '2023-10-04 13:06:46.739475+00', '2024-07-09 12:54:02.863073+00', 'U01814d1ec9ff', 'Gravity Rulez!', 'Let''s make Gravity better together!', NULL, true, false, 18, NULL, NULL, NULL);
INSERT INTO public.beacon VALUES ('B68247950d9c0', '2024-02-16 15:12:52.036642+00', '2024-07-09 12:54:02.863073+00', 'U9ce5721e93cf', 'hih', 'hihi qwerty', NULL, true, false, 0, NULL, NULL, NULL);
INSERT INTO public.beacon VALUES ('B8a531802473b', '2023-09-26 10:56:06.009191+00', '2024-07-09 12:54:02.863073+00', 'U016217c34c6e', 'Sem nulla pharetra diam sit amet nisl suscipit adipiscing bibendum.', '', NULL, true, false, 3, NULL, NULL, NULL);
INSERT INTO public.beacon VALUES ('B69723edfec8a', '2023-12-20 08:29:26.708296+00', '2024-07-09 12:54:02.863073+00', 'U5c827d7de115', 'Mikhail Sh', '', NULL, true, false, 0, NULL, NULL, NULL);
INSERT INTO public.beacon VALUES ('Bfae1726e4e87', '2024-07-09 12:40:15.432508+00', '2024-07-09 12:54:02.863073+00', 'Uadeb43da4abb', 'Second', 'has no', NULL, true, false, 0, NULL, NULL, NULL);
INSERT INTO public.beacon VALUES ('B73574c119816', '2024-07-18 15:25:11.222845+00', '2024-07-18 15:25:11.222845+00', 'U95f3426b8e5d', 'Piece of shit', '', '["2024-07-18 00:00:00+00","2024-07-18 00:00:00+00"]', true, false, 0, NULL, NULL, NULL);
INSERT INTO public.beacon VALUES ('B73a44e2bbd44', '2023-10-04 16:06:20.658199+00', '2024-08-01 11:09:55.258615+00', 'U8a78048d60f7', 'Зима', 'Обсудим?', NULL, true, false, 1, NULL, NULL, NULL);
INSERT INTO public.beacon VALUES ('B3b3f2ecde430', '2023-09-26 10:56:06.009191+00', '2024-08-09 01:09:12.509733+00', 'U7a8d8324441d', 'In hac habitasse platea dictumst.', '', NULL, true, false, 12, NULL, NULL, NULL);
INSERT INTO public.beacon VALUES ('Bad1c69de7837', '2023-09-26 10:56:06.009191+00', '2024-08-24 17:07:53.432056+00', 'Uad577360d968', 'Morbi tristique senectus et netus et malesuada fames.', 'Nibh ipsum consequat nisl vel pretium lectus.
Parturient montes nascetur ridiculus mus mauris vitae ultricies leo.
Amet consectetur adipiscing elit pellentesque habitant morbi tristique senectus.
Non enim praesent elementum facilisis leo vel fringilla est.', '["2023-09-26 13:56:05.639793+00","2023-10-13 13:56:05.639793+00"]', true, false, 54, NULL, NULL, NULL);
INSERT INTO public.beacon VALUES ('Bf9c21e90c364', '2024-08-05 17:20:38.942022+00', '2024-08-05 17:20:38.942022+00', 'Ub01f4ad1b03f', 'Discourse', '', NULL, true, true, 0, NULL, NULL, 'Discourse');
INSERT INTO public.beacon VALUES ('B310b66ab31fb', '2023-10-03 20:34:31.230559+00', '2024-08-05 21:30:13.63672+00', 'U6d2f25cc4264', 'First post', '', NULL, true, false, 2, NULL, NULL, 'Fatum');
INSERT INTO public.beacon VALUES ('Beaa423fabf17', '2024-08-24 17:14:17.290704+00', '2024-08-24 17:14:27.33566+00', 'U29a00cc1c9c2', 'yum', '', NULL, true, false, 1, NULL, NULL, NULL);
INSERT INTO public.beacon VALUES ('B9cade9992fb9', '2023-12-15 17:21:14.985002+00', '2024-08-20 22:36:27.287326+00', 'U638f5c19326f', 'test for Tentura', 'test 123', NULL, true, false, 1, NULL, NULL, NULL);
INSERT INTO public.beacon VALUES ('Bfefe4e25c870', '2023-10-05 13:21:50.721901+00', '2024-08-20 22:40:10.941502+00', 'U499f24158a40', 'lorem', 'Ipsum', '["2023-10-05 00:00:00+00","2023-11-30 00:00:00+00"]', true, false, 5, NULL, NULL, NULL);
INSERT INTO public.beacon VALUES ('Bc0dc1870dcb1', '2024-08-21 13:54:46.222569+00', '2024-08-21 13:54:46.222569+00', 'Uf82dbb4708ba', 'New test project 02', '', '["2024-08-29 00:00:00+00","2024-08-30 00:00:00+00"]', true, true, 0, 52.2199338748197, 5.172569570464782, 'Volunteer');
INSERT INTO public.beacon VALUES ('B45d72e29f004', '2023-09-26 10:56:06.009191+00', '2024-08-05 22:20:43.13575+00', 'U26aca0e369c7', 'Interdum velit euismod in pellentesque massa placerat duis ultricies lacus.', 'Tempus iaculis urna id volutpat lacus laoreet.
Vel turpis nunc eget lorem dolor sed viverra ipsum nunc.
Purus viverra accumsan in nisl nisi scelerisque.
Sem viverra aliquet eget sit amet tellus.', NULL, true, false, 8, NULL, NULL, NULL);
INSERT INTO public.beacon VALUES ('Bc8526e892c5d', '2024-08-24 17:14:57.488731+00', '2024-08-24 17:16:03.58205+00', 'U55272fd6c264', 'Sibling', '', NULL, true, true, 1, 48.29586494544464, 16.248253188388347, 'cat');
INSERT INTO public.beacon VALUES ('B4b8f4cc22df5', '2024-08-21 13:55:10.327985+00', '2024-08-21 13:55:10.327985+00', 'U9de057150efc', 'ttttt', 'tt', NULL, true, false, 0, NULL, NULL, NULL);
INSERT INTO public.beacon VALUES ('B1b2e44f692d5', '2024-08-21 13:55:13.015931+00', '2024-08-21 13:55:13.015931+00', 'U9de057150efc', 'ttttt', 'tt', NULL, true, false, 0, NULL, NULL, NULL);
INSERT INTO public.beacon VALUES ('B97b0f2a030a6', '2024-08-24 17:02:18.431105+00', '2024-08-24 17:02:18.431105+00', 'U163b54808a6b', 'Like that', '', NULL, true, true, 0, NULL, NULL, 'Cats');


--
-- Data for Name: beacon_pinned; Type: TABLE DATA; Schema: public; Owner: postgres
--

INSERT INTO public.beacon_pinned VALUES ('U01814d1ec9ff', 'B5a1c1d3d0140');
INSERT INTO public.beacon_pinned VALUES ('U01814d1ec9ff', 'B9c01ce5718d1');
INSERT INTO public.beacon_pinned VALUES ('U8a78048d60f7', 'B5a1c1d3d0140');
INSERT INTO public.beacon_pinned VALUES ('U6d2f25cc4264', 'B9c01ce5718d1');
INSERT INTO public.beacon_pinned VALUES ('U6240251593cd', 'B75a44a52fa29');
INSERT INTO public.beacon_pinned VALUES ('U8a78048d60f7', 'Bad1c69de7837');
INSERT INTO public.beacon_pinned VALUES ('U8a78048d60f7', 'Ba3c4a280657d');
INSERT INTO public.beacon_pinned VALUES ('U6d2f25cc4264', 'B491d307dfe01');
INSERT INTO public.beacon_pinned VALUES ('Uc35c445325f5', 'B9c01ce5718d1');
INSERT INTO public.beacon_pinned VALUES ('U95f3426b8e5d', 'B9c01ce5718d1');
INSERT INTO public.beacon_pinned VALUES ('U95f3426b8e5d', 'B79efabc4d8bf');
INSERT INTO public.beacon_pinned VALUES ('Ua1342df2a349', 'B7f628ad203b5');
INSERT INTO public.beacon_pinned VALUES ('Uebf1ab7a1e6b', 'B7f628ad203b5');
INSERT INTO public.beacon_pinned VALUES ('Uc2fdcf17c2fe', 'B3b3f2ecde430');
INSERT INTO public.beacon_pinned VALUES ('Ua0ece646c249', 'B7f628ad203b5');
INSERT INTO public.beacon_pinned VALUES ('Ua0ece646c249', 'Bad1c69de7837');
INSERT INTO public.beacon_pinned VALUES ('U6fa666cd4b28', 'B491d307dfe01');
INSERT INTO public.beacon_pinned VALUES ('Ucc76e1b73be0', 'B3b3f2ecde430');
INSERT INTO public.beacon_pinned VALUES ('U09ce851f811d', 'B7f628ad203b5');
INSERT INTO public.beacon_pinned VALUES ('Ub01f4ad1b03f', 'B491d307dfe01');
INSERT INTO public.beacon_pinned VALUES ('Ub01f4ad1b03f', 'B9c01ce5718d1');
INSERT INTO public.beacon_pinned VALUES ('Ub01f4ad1b03f', 'Bfefe4e25c870');
INSERT INTO public.beacon_pinned VALUES ('Ub01f4ad1b03f', 'B310b66ab31fb');
INSERT INTO public.beacon_pinned VALUES ('Ub01f4ad1b03f', 'B3f6f837bc345');
INSERT INTO public.beacon_pinned VALUES ('Uc406b9444f78', 'B3b3f2ecde430');
INSERT INTO public.beacon_pinned VALUES ('U15333c20136a', 'B7f628ad203b5');
INSERT INTO public.beacon_pinned VALUES ('Uc406b9444f78', 'B7f628ad203b5');
INSERT INTO public.beacon_pinned VALUES ('U15333c20136a', 'B45d72e29f004');
INSERT INTO public.beacon_pinned VALUES ('U9f2ca949e629', 'B79efabc4d8bf');
INSERT INTO public.beacon_pinned VALUES ('Ubd4ba65ba102', 'Be2b46c17f1da');
INSERT INTO public.beacon_pinned VALUES ('U77a03e9a08af', 'Bed48703df71d');
INSERT INTO public.beacon_pinned VALUES ('Ub01f4ad1b03f', 'B500ed1ecb236');
INSERT INTO public.beacon_pinned VALUES ('U3de05e2162cb', 'B7f628ad203b5');
INSERT INTO public.beacon_pinned VALUES ('Uaea5ee26a787', 'B7f628ad203b5');
INSERT INTO public.beacon_pinned VALUES ('U2343287cf1f5', 'Be2b46c17f1da');
INSERT INTO public.beacon_pinned VALUES ('Uaea5ee26a787', 'B45d72e29f004');
INSERT INTO public.beacon_pinned VALUES ('U1ece3c01f2c1', 'Bad1c69de7837');
INSERT INTO public.beacon_pinned VALUES ('U1ece3c01f2c1', 'B5eb4c6be535a');
INSERT INTO public.beacon_pinned VALUES ('U5a89e961863e', 'B3b3f2ecde430');
INSERT INTO public.beacon_pinned VALUES ('U006251a762f0', 'B491d307dfe01');
INSERT INTO public.beacon_pinned VALUES ('Ub01f4ad1b03f', 'Be64122664ec6');
INSERT INTO public.beacon_pinned VALUES ('U1f8687088899', 'Bad1c69de7837');
INSERT INTO public.beacon_pinned VALUES ('U03f52ca325d0', 'Be2b46c17f1da');
INSERT INTO public.beacon_pinned VALUES ('Ue28a49e571f5', 'Bad1c69de7837');
INSERT INTO public.beacon_pinned VALUES ('U4389072867c2', 'Bad1c69de7837');
INSERT INTO public.beacon_pinned VALUES ('Uc2cb918a102c', 'Bad1c69de7837');
INSERT INTO public.beacon_pinned VALUES ('U77a03e9a08af', 'Bb78026d99388');
INSERT INTO public.beacon_pinned VALUES ('U14debbf04eba', 'B3b3f2ecde430');
INSERT INTO public.beacon_pinned VALUES ('U808cdf86e24f', 'Be2b46c17f1da');
INSERT INTO public.beacon_pinned VALUES ('Ud3f25372d084', 'B3b3f2ecde430');
INSERT INTO public.beacon_pinned VALUES ('U62360fd0833f', 'B79efabc4d8bf');
INSERT INTO public.beacon_pinned VALUES ('U62360fd0833f', 'Bfefe4e25c870');
INSERT INTO public.beacon_pinned VALUES ('Ud3f25372d084', 'B7f628ad203b5');
INSERT INTO public.beacon_pinned VALUES ('U62360fd0833f', 'Ba3c4a280657d');
INSERT INTO public.beacon_pinned VALUES ('U77a03e9a08af', 'B45d72e29f004');
INSERT INTO public.beacon_pinned VALUES ('Ue1c6ed610073', 'B3b3f2ecde430');
INSERT INTO public.beacon_pinned VALUES ('U1ccc3338ee60', 'B7f628ad203b5');
INSERT INTO public.beacon_pinned VALUES ('U0fc148d003b7', 'B491d307dfe01');
INSERT INTO public.beacon_pinned VALUES ('Ue1c6ed610073', 'B7f628ad203b5');
INSERT INTO public.beacon_pinned VALUES ('U1ccc3338ee60', 'B5eb4c6be535a');
INSERT INTO public.beacon_pinned VALUES ('U4bab0d326dee', 'Bad1c69de7837');
INSERT INTO public.beacon_pinned VALUES ('U77a03e9a08af', 'B4b8fafa86526');
INSERT INTO public.beacon_pinned VALUES ('Uf82dbb4708ba', 'B45d72e29f004');
INSERT INTO public.beacon_pinned VALUES ('Uf82dbb4708ba', 'B75a44a52fa29');
INSERT INTO public.beacon_pinned VALUES ('U01d7dc9f375f', 'Be2b46c17f1da');
INSERT INTO public.beacon_pinned VALUES ('U06f2343258bc', 'Bad1c69de7837');
INSERT INTO public.beacon_pinned VALUES ('U32f453dcedfc', 'B9cade9992fb9');
INSERT INTO public.beacon_pinned VALUES ('Uaebcaa080fa8', 'B5eb4c6be535a');
INSERT INTO public.beacon_pinned VALUES ('U06f2343258bc', 'B7f628ad203b5');
INSERT INTO public.beacon_pinned VALUES ('U9d5605fd67f3', 'Bad1c69de7837');
INSERT INTO public.beacon_pinned VALUES ('Uaebcaa080fa8', 'B25c85fe0df2d');
INSERT INTO public.beacon_pinned VALUES ('U6eba124741ce', 'Bfefe4e25c870');
INSERT INTO public.beacon_pinned VALUES ('Uc02f96c370bd', 'B60d725feca77');
INSERT INTO public.beacon_pinned VALUES ('U9de057150efc', 'B91796a98a225');
INSERT INTO public.beacon_pinned VALUES ('U0be96c3b9883', 'B1533941e2773');
INSERT INTO public.beacon_pinned VALUES ('U5d33a9be1633', 'B1533941e2773');
INSERT INTO public.beacon_pinned VALUES ('U0d2e9e0dc40e', 'B3f6f837bc345');
INSERT INTO public.beacon_pinned VALUES ('Ub4b46ee7a5e4', 'B9c01ce5718d1');
INSERT INTO public.beacon_pinned VALUES ('Ub4b46ee7a5e4', 'B500ed1ecb236');
INSERT INTO public.beacon_pinned VALUES ('Ub4b46ee7a5e4', 'Be64122664ec6');
INSERT INTO public.beacon_pinned VALUES ('U3ea0a229ad85', 'B500ed1ecb236');
INSERT INTO public.beacon_pinned VALUES ('U3ea0a229ad85', 'B5f6a16260bac');
INSERT INTO public.beacon_pinned VALUES ('U3ea0a229ad85', 'Be64122664ec6');
INSERT INTO public.beacon_pinned VALUES ('Ucfdea362a41c', 'B3b3f2ecde430');
INSERT INTO public.beacon_pinned VALUES ('Ucd6310f58337', 'B7f628ad203b5');
INSERT INTO public.beacon_pinned VALUES ('U163b54808a6b', 'B5f6a16260bac');
INSERT INTO public.beacon_pinned VALUES ('Ucfdea362a41c', 'Bad1c69de7837');
INSERT INTO public.beacon_pinned VALUES ('Uc9fc0531972e', 'Be2b46c17f1da');
INSERT INTO public.beacon_pinned VALUES ('U1715ceca6772', 'Be2b46c17f1da');
INSERT INTO public.beacon_pinned VALUES ('U163b54808a6b', 'B4f00e7813add');
INSERT INTO public.beacon_pinned VALUES ('U163b54808a6b', 'Be64122664ec6');
INSERT INTO public.beacon_pinned VALUES ('U99266e588f08', 'B7f628ad203b5');
INSERT INTO public.beacon_pinned VALUES ('U163b54808a6b', 'B500ed1ecb236');
INSERT INTO public.beacon_pinned VALUES ('U163b54808a6b', 'B4b8fafa86526');
INSERT INTO public.beacon_pinned VALUES ('U99266e588f08', 'Bad1c69de7837');
INSERT INTO public.beacon_pinned VALUES ('Uc9fc0531972e', 'B7f628ad203b5');
INSERT INTO public.beacon_pinned VALUES ('Uc9fc0531972e', 'B3b3f2ecde430');
INSERT INTO public.beacon_pinned VALUES ('U1715ceca6772', 'Bad1c69de7837');
INSERT INTO public.beacon_pinned VALUES ('Ue45a5234f456', 'B7f628ad203b5');
INSERT INTO public.beacon_pinned VALUES ('U29a00cc1c9c2', 'B60d725feca77');
INSERT INTO public.beacon_pinned VALUES ('Ub01f4ad1b03f', 'Bea6112348aa2');
INSERT INTO public.beacon_pinned VALUES ('Ub01f4ad1b03f', 'Bc8526e892c5d');
INSERT INTO public.beacon_pinned VALUES ('U0be96c3b9883', 'B79efabc4d8bf');
INSERT INTO public.beacon_pinned VALUES ('Ud23a6bb9874f', 'B79efabc4d8bf');


--
-- Data for Name: comment; Type: TABLE DATA; Schema: public; Owner: postgres
--

INSERT INTO public.comment VALUES ('Cb117f464e558', 'U26aca0e369c7', 'Facilisis leo vel fringilla est ullamcorper eget.
Ac tortor dignissim convallis aenean et tortor at.', '2023-09-26 10:56:06.176637+00', 'B7f628ad203b5');
INSERT INTO public.comment VALUES ('C3e84102071d1', 'U016217c34c6e', 'Scelerisque purus semper eget duis.
Metus aliquam eleifend mi in nulla posuere sollicitudin.', '2023-09-26 10:56:06.176637+00', 'Bb78026d99388');
INSERT INTO public.comment VALUES ('Ce1a7d8996eb0', 'Uf5096f6ab14e', 'Congue nisi vitae suscipit tellus.
Turpis in eu mi bibendum.
Viverra mauris in aliquam sem fringilla.
Sagittis id consectetur purus ut faucibus pulvinar elementum integer.', '2023-09-26 10:56:06.176637+00', 'Bdf39d0e1daf5');
INSERT INTO public.comment VALUES ('C30e7409c2d5f', 'U80e22da6d8c4', 'A lacus vestibulum sed arcu non odio euismod lacinia at.
Vivamus at augue eget arcu.
Quisque id diam vel quam elementum.
At in tellus integer feugiat scelerisque varius morbi.', '2023-09-26 10:56:06.176637+00', 'B45d72e29f004');
INSERT INTO public.comment VALUES ('Cfdde53c79a2d', 'Uef7fbf45ef11', 'Aliquet nibh praesent tristique magna sit amet purus gravida.
Tortor dignissim convallis aenean et tortor.
Fringilla est ullamcorper eget nulla facilisi etiam dignissim.', '2023-09-26 10:56:06.176637+00', 'B0e230e9108dd');
INSERT INTO public.comment VALUES ('C2bbd63b00224', 'U80e22da6d8c4', 'Donec massa sapien faucibus et molestie ac feugiat sed.
Arcu vitae elementum curabitur vitae nunc.
A cras semper auctor neque vitae tempus quam pellentesque.
Semper feugiat nibh sed pulvinar proin gravida hendrerit lectus a.', '2023-09-26 10:56:06.176637+00', 'B7f628ad203b5');
INSERT INTO public.comment VALUES ('C67e4476fda28', 'U1c285703fc63', 'Et malesuada fames ac turpis egestas maecenas.', '2023-09-26 10:56:06.176637+00', 'Bdf39d0e1daf5');
INSERT INTO public.comment VALUES ('C6aebafa4fe8e', 'U9a2c85753a6d', 'Id eu nisl nunc mi ipsum faucibus vitae aliquet nec.
Mattis pellentesque id nibh tortor.', '2023-09-26 10:56:06.176637+00', 'B25c85fe0df2d');
INSERT INTO public.comment VALUES ('Ca0a6aea6c82e', 'U016217c34c6e', 'Sagittis nisl rhoncus mattis rhoncus urna neque viverra justo.
Quis hendrerit dolor magna eget est lorem.
Diam quam nulla porttitor massa id neque aliquam vestibulum.', '2023-09-26 10:56:06.176637+00', 'B0e230e9108dd');
INSERT INTO public.comment VALUES ('Cbce32a9b256a', 'U389f9f24b31c', 'Amet cursus sit amet dictum sit amet justo donec.
Eleifend quam adipiscing vitae proin sagittis nisl rhoncus mattis.
Senectus et netus et malesuada fames ac turpis egestas integer.', '2023-09-26 10:56:06.176637+00', 'Bad1c69de7837');
INSERT INTO public.comment VALUES ('Cb76829a425d9', 'Ue7a29d5409f2', 'Nibh nisl condimentum id venenatis a condimentum vitae sapien pellentesque.
Pretium aenean pharetra magna ac placerat vestibulum.
Aliquam nulla facilisi cras fermentum odio eu feugiat.
Lacus vel facilisis volutpat est velit.', '2023-09-26 10:56:06.176637+00', 'Bf3a0a1165271');
INSERT INTO public.comment VALUES ('C94bb73c10a06', 'Uef7fbf45ef11', 'Vestibulum lectus mauris ultrices eros in cursus.', '2023-09-26 10:56:06.176637+00', 'B5eb4c6be535a');
INSERT INTO public.comment VALUES ('C599f6e6f6b64', 'U26aca0e369c7', 'Nibh cras pulvinar mattis nunc sed blandit.
Mattis enim ut tellus elementum sagittis vitae et leo.', '2023-09-26 10:56:06.176637+00', 'Bb78026d99388');
INSERT INTO public.comment VALUES ('Cd06fea6a395f', 'Uaa4e2be7a87a', 'Tortor id aliquet lectus proin nibh nisl condimentum id venenatis.', '2023-09-26 10:56:06.176637+00', 'B25c85fe0df2d');
INSERT INTO public.comment VALUES ('C35678a54ef5f', 'Uaa4e2be7a87a', 'Ac tortor vitae purus faucibus ornare.
Arcu cursus vitae congue mauris rhoncus aenean vel elit scelerisque.
Fringilla urna porttitor rhoncus dolor purus non.', '2023-09-26 10:56:06.176637+00', 'B25c85fe0df2d');
INSERT INTO public.comment VALUES ('Cfc639b9aa3e0', 'U389f9f24b31c', 'Consequat id porta nibh venenatis cras sed felis eget velit.', '2023-09-26 10:56:06.176637+00', 'Bb78026d99388');
INSERT INTO public.comment VALUES ('C0b19d314485e', 'Uaa4e2be7a87a', 'Aliquam faucibus purus in massa tempor nec feugiat nisl pretium.', '2023-09-26 10:56:06.176637+00', 'B0e230e9108dd');
INSERT INTO public.comment VALUES ('Cd59e6cd7e104', 'U80e22da6d8c4', 'Laoreet sit amet cursus sit amet dictum sit.
Ultrices in iaculis nunc sed augue lacus.
Orci a scelerisque purus semper eget duis at tellus.
Mi proin sed libero enim.', '2023-09-26 10:56:06.176637+00', 'B60d725feca77');
INSERT INTO public.comment VALUES ('C3fd1fdebe0e9', 'U7a8d8324441d', 'Cursus turpis massa tincidunt dui ut.
Lobortis mattis aliquam faucibus purus.
Lorem dolor sed viverra ipsum nunc aliquet.', '2023-09-26 10:56:06.176637+00', 'B45d72e29f004');
INSERT INTO public.comment VALUES ('C78d6fac93d00', 'Uc1158424318a', 'A condimentum vitae sapien pellentesque habitant morbi tristique senectus.
Facilisi etiam dignissim diam quis enim lobortis scelerisque.
Egestas sed sed risus pretium quam vulputate dignissim.
Faucibus nisl tincidunt eget nullam.', '2023-09-26 10:56:06.176637+00', 'B3c467fb437b2');
INSERT INTO public.comment VALUES ('C78ad459d3b81', 'U9a2c85753a6d', 'Pellentesque dignissim enim sit amet venenatis urna cursus eget nunc.
Magna sit amet purus gravida quis.
Proin nibh nisl condimentum id venenatis a condimentum vitae.
Id ornare arcu odio ut sem nulla pharetra diam sit.', '2023-09-26 10:56:06.176637+00', 'B3c467fb437b2');
INSERT INTO public.comment VALUES ('C9462ca240ceb', 'Uf5096f6ab14e', 'Fermentum et sollicitudin ac orci.
In vitae turpis massa sed elementum tempus egestas.
Dignissim sodales ut eu sem integer.', '2023-09-26 10:56:06.176637+00', 'Be2b46c17f1da');
INSERT INTO public.comment VALUES ('C30fef1977b4a', 'U7a8d8324441d', 'Velit ut tortor pretium viverra suspendisse potenti nullam ac.', '2023-09-26 10:56:06.176637+00', 'Be2b46c17f1da');
INSERT INTO public.comment VALUES ('C4e0db8dec53e', 'U0c17798eaab4', 'A diam sollicitudin tempor id.
Enim ut sem viverra aliquet eget.', '2023-09-26 10:56:06.176637+00', 'Bdf39d0e1daf5');
INSERT INTO public.comment VALUES ('C070e739180d6', 'U80e22da6d8c4', 'Vestibulum mattis ullamcorper velit sed ullamcorper morbi.', '2023-09-26 10:56:06.176637+00', 'B7f628ad203b5');
INSERT INTO public.comment VALUES ('C588ffef22463', 'Uef7fbf45ef11', 'Augue neque gravida in fermentum et sollicitudin ac orci phasellus.
Facilisi cras fermentum odio eu feugiat pretium nibh ipsum consequat.
Orci ac auctor augue mauris augue neque gravida in fermentum.
Amet dictum sit amet justo donec.', '2023-09-26 10:56:06.176637+00', 'Bb78026d99388');
INSERT INTO public.comment VALUES ('C357396896bd0', 'Udece0afd9a8b', 'Velit sed ullamcorper morbi tincidunt ornare massa eget.
Ultrices dui sapien eget mi proin sed libero.
Pellentesque pulvinar pellentesque habitant morbi tristique senectus et netus et.
Ornare arcu odio ut sem.', '2023-09-26 10:56:06.176637+00', 'Bad1c69de7837');
INSERT INTO public.comment VALUES ('C6acd550a4ef3', 'Uc1158424318a', 'Bibendum enim facilisis gravida neque.
Nunc non blandit massa enim nec dui nunc mattis enim.
Viverra nibh cras pulvinar mattis nunc.', '2023-09-26 10:56:06.176637+00', 'Bad1c69de7837');
INSERT INTO public.comment VALUES ('C4893c40e481d', 'Udece0afd9a8b', 'Dui accumsan sit amet nulla facilisi morbi tempus iaculis.', '2023-09-26 10:56:06.176637+00', 'Bdf39d0e1daf5');
INSERT INTO public.comment VALUES ('C399b6349ab02', 'Uf2b0a6b1d423', 'Elementum sagittis vitae et leo.', '2023-09-26 10:56:06.176637+00', 'B25c85fe0df2d');
INSERT INTO public.comment VALUES ('C15d8dfaceb75', 'U9e42f6dab85a', 'Habitasse platea dictumst vestibulum rhoncus.
Id porta nibh venenatis cras sed felis eget.
Dignissim convallis aenean et tortor.
Amet nisl purus in mollis nunc sed.', '2023-09-26 10:56:06.176637+00', 'B60d725feca77');
INSERT INTO public.comment VALUES ('Cc9f863ff681b', 'Uc1158424318a', 'Elit at imperdiet dui accumsan sit amet nulla.', '2023-09-26 10:56:06.176637+00', 'B45d72e29f004');
INSERT INTO public.comment VALUES ('C613f00c1333c', 'U80e22da6d8c4', 'Pharetra et ultrices neque ornare aenean.
Sed vulputate odio ut enim.
At risus viverra adipiscing at in tellus integer feugiat scelerisque.
Ipsum dolor sit amet consectetur adipiscing elit duis tristique.', '2023-09-26 10:56:06.176637+00', 'B0e230e9108dd');
INSERT INTO public.comment VALUES ('C6a2263dc469e', 'Uf2b0a6b1d423', 'Tempor id eu nisl nunc mi ipsum.
Nunc mattis enim ut tellus.
Pharetra vel turpis nunc eget lorem dolor sed viverra.', '2023-09-26 10:56:06.176637+00', 'B25c85fe0df2d');
INSERT INTO public.comment VALUES ('C9028c7415403', 'Udece0afd9a8b', 'Tincidunt dui ut ornare lectus.
Arcu cursus euismod quis viverra nibh cras pulvinar.', '2023-09-26 10:56:06.176637+00', 'Be2b46c17f1da');
INSERT INTO public.comment VALUES ('Cbbf2df46955b', 'U7a8d8324441d', 'Ut ornare lectus sit amet est.
Tellus in hac habitasse platea dictumst vestibulum rhoncus est pellentesque.
Purus viverra accumsan in nisl nisi scelerisque.', '2023-09-26 10:56:06.176637+00', 'Bb78026d99388');
INSERT INTO public.comment VALUES ('C0cd490b5fb6a', 'Uad577360d968', 'Cursus vitae congue mauris rhoncus aenean vel.
Sit amet nisl purus in mollis nunc sed.
Facilisi cras fermentum odio eu feugiat pretium nibh ipsum consequat.
Arcu cursus euismod quis viverra nibh cras pulvinar.', '2023-09-26 10:56:06.176637+00', 'B45d72e29f004');
INSERT INTO public.comment VALUES ('Cb14487d862b3', 'Uf5096f6ab14e', 'Ac tortor vitae purus faucibus ornare.
Nisl nunc mi ipsum faucibus vitae aliquet nec.
Non blandit massa enim nec.', '2023-09-26 10:56:06.176637+00', 'B5eb4c6be535a');
INSERT INTO public.comment VALUES ('Cdcddfb230cb5', 'Udece0afd9a8b', 'Nibh ipsum consequat nisl vel pretium lectus.
Nec dui nunc mattis enim ut.
Malesuada fames ac turpis egestas maecenas.
Tempus imperdiet nulla malesuada pellentesque elit eget.', '2023-09-26 10:56:06.176637+00', 'Bad1c69de7837');
INSERT INTO public.comment VALUES ('C4f2dafca724f', 'U7a8d8324441d', 'Eget nunc lobortis mattis aliquam faucibus purus in massa.', '2023-09-26 10:56:06.176637+00', 'Bf3a0a1165271');
INSERT INTO public.comment VALUES ('C888c86d096d0', 'U7a8d8324441d', 'Enim nec dui nunc mattis enim.', '2023-10-01 10:21:42.533175+00', 'B8a531802473b');
INSERT INTO public.comment VALUES ('C7062e90f7422', 'U01814d1ec9ff', 'добавляем комменты с идеями, не стесняемся 😁', '2023-10-04 13:09:52.043217+00', 'B75a44a52fa29');
INSERT INTO public.comment VALUES ('C1c86825bd597', 'U01814d1ec9ff', 'здравствуй бот', '2023-10-04 13:14:03.698899+00', 'B5a1c1d3d0140');
INSERT INTO public.comment VALUES ('Cf4b448ef8618', 'U499f24158a40', 'Lorem', '2023-10-05 13:22:38.999002+00', 'B63fbe1427d09');
INSERT INTO public.comment VALUES ('C96bdee4f11e2', 'U499f24158a40', 'Ipsum', '2023-10-05 13:22:49.247947+00', 'B8a531802473b');
INSERT INTO public.comment VALUES ('C4b2b6fd8fa9a', 'U499f24158a40', 'Ipsum', '2023-10-05 13:23:02.448698+00', 'B5a1c1d3d0140');
INSERT INTO public.comment VALUES ('C54972a5fbc16', 'U499f24158a40', 'Lorem', '2023-10-05 13:23:12.253504+00', 'B3b3f2ecde430');
INSERT INTO public.comment VALUES ('C4818c4ed20bf', 'U499f24158a40', 'В', '2023-10-05 13:23:22.458141+00', 'Bd49e3dac97b0');
INSERT INTO public.comment VALUES ('Cd172fb3fdc41', 'U499f24158a40', 'Лесу ', '2023-10-05 13:23:34.712229+00', 'B3c467fb437b2');
INSERT INTO public.comment VALUES ('C8d80016b8292', 'U499f24158a40', 'Родилась ', '2023-10-05 13:23:41.916949+00', 'B7f628ad203b5');
INSERT INTO public.comment VALUES ('C247501543b60', 'U499f24158a40', 'Ёлочка ', '2023-10-05 13:23:51.665361+00', 'Bdf39d0e1daf5');
INSERT INTO public.comment VALUES ('C0166be581dd4', 'U499f24158a40', 'В лесу ', '2023-10-05 13:24:04.283275+00', 'B60d725feca77');
INSERT INTO public.comment VALUES ('Cb95e21215efa', 'U499f24158a40', 'Она росла ', '2023-10-05 13:24:12.361718+00', 'B25c85fe0df2d');
INSERT INTO public.comment VALUES ('C6d52e861b366', 'U21769235b28d', 'а почему', '2023-10-05 13:41:21.989697+00', 'B9c01ce5718d1');
INSERT INTO public.comment VALUES ('C8ece5c618ac1', 'U21769235b28d', 'оно дублируется? ', '2023-10-05 13:41:35.20844+00', 'B79efabc4d8bf');
INSERT INTO public.comment VALUES ('C481cd737c873', 'U21769235b28d', 'всё позасрали своим аниме', '2023-10-05 13:42:17.351068+00', 'Ba3c4a280657d');
INSERT INTO public.comment VALUES ('C801f204d0da8', 'U21769235b28d', 'император вас благослови', '2023-10-05 13:42:31.491113+00', 'B491d307dfe01');
INSERT INTO public.comment VALUES ('Ccbd85b8513f3', 'U499f24158a40', 'Вот я пришёл по куар с телефона Антона ', '2023-10-05 13:43:34.486666+00', 'B5a1c1d3d0140');
INSERT INTO public.comment VALUES ('C6f84810d3cd9', 'U499f24158a40', 'А сюда пришёл по номеру кода ', '2023-10-05 13:44:29.882139+00', 'B3c467fb437b2');
INSERT INTO public.comment VALUES ('C279db553a831', 'U99a0f1f7e6ee', 'коммент', '2023-10-06 15:21:01.922934+00', 'B8a531802473b');
INSERT INTO public.comment VALUES ('C4d1d582c53c3', 'U99a0f1f7e6ee', ' ', '2023-10-06 15:34:57.810286+00', 'Bdf39d0e1daf5');
INSERT INTO public.comment VALUES ('Cfd59a206c07d', 'U99a0f1f7e6ee', ':', '2023-10-06 15:35:11.146447+00', 'Bdf39d0e1daf5');
INSERT INTO public.comment VALUES ('C22e1102411ce', 'U6661263fb410', 'hdjdjd', '2023-10-08 16:28:38.51938+00', 'B75a44a52fa29');
INSERT INTO public.comment VALUES ('Cf92f90725ffc', 'U6661263fb410', 'ьала', '2023-10-08 16:48:19.375798+00', 'B75a44a52fa29');
INSERT INTO public.comment VALUES ('Ce49159fe9d01', 'U6661263fb410', 'ыыыыааа', '2023-10-08 16:49:54.917115+00', 'B75a44a52fa29');
INSERT INTO public.comment VALUES ('C8343a6a576ff', 'U02fbd7c8df4c', 'yo brother', '2023-10-08 16:49:59.30401+00', 'B75a44a52fa29');
INSERT INTO public.comment VALUES ('C25639690ee57', 'U6d2f25cc4264', 'Anybody is there?', '2023-10-08 17:09:12.060573+00', 'Bdf39d0e1daf5');
INSERT INTO public.comment VALUES ('Cac6ca02355da', 'U6d2f25cc4264', 'Ipsum', '2023-10-08 17:09:42.355994+00', 'B3b3f2ecde430');
INSERT INTO public.comment VALUES ('Cab47a458295f', 'U6d2f25cc4264', 'Император задвоился слегка...', '2023-10-08 17:11:35.084595+00', 'B491d307dfe01');
INSERT INTO public.comment VALUES ('C992d8370db6b', 'U6d2f25cc4264', 'Кот - двойной агент!', '2023-10-08 17:12:39.291587+00', 'B79efabc4d8bf');
INSERT INTO public.comment VALUES ('Cd5983133fb67', 'U8a78048d60f7', 'From disc ', '2023-10-08 17:28:23.734397+00', 'B9c01ce5718d1');
INSERT INTO public.comment VALUES ('Cd6c9d5cba220', 'Ud5b22ebf52f2', 'I see you!', '2023-10-08 19:47:10.298807+00', 'B310b66ab31fb');
INSERT INTO public.comment VALUES ('Cd4417a5d718e', 'Ub93799d9400e', 'V3 comment', '2023-10-09 09:05:58.983007+00', 'B9c01ce5718d1');
INSERT INTO public.comment VALUES ('C7986cd8a648a', 'U682c3380036f', 'hdyxy', '2023-10-10 11:02:12.359431+00', 'B75a44a52fa29');
INSERT INTO public.comment VALUES ('C2e31b4b1658f', 'U8a78048d60f7', 'ipsum', '2023-10-19 14:39:49.270258+00', 'B63fbe1427d09');
INSERT INTO public.comment VALUES ('Cb11edc3d0bc7', 'U8a78048d60f7', 'Hello, bro!', '2023-10-20 06:50:19.525247+00', 'B310b66ab31fb');
INSERT INTO public.comment VALUES ('Cc42c3eeb9d20', 'U8a78048d60f7', 'Собери сам?', '2023-10-30 14:56:50.910381+00', 'Bf34ee3bfc12b');
INSERT INTO public.comment VALUES ('Cb07d467c1c5e', 'U8a78048d60f7', 'Предлагая предлагать идеи, предъявляй и свою!', '2023-10-30 15:01:11.541017+00', 'B75a44a52fa29');
INSERT INTO public.comment VALUES ('C5782d559baad', 'U0cd6bd2dde4f', 'Лучшее обсуждение за последний месяц :)', '2023-10-30 17:21:02.283555+00', 'B75a44a52fa29');
INSERT INTO public.comment VALUES ('C81f3f954b643', 'U09cf1f359454', 'Не знал, что Камчатка уже в составе Польши 😆', '2023-11-08 06:44:03.044221+00', 'B70df5dbab8c3');
INSERT INTO public.comment VALUES ('C0a576fc389d9', 'U1bcba4fd7175', 'коньки - это прекрасно!', '2023-11-08 10:03:17.038622+00', 'B4f00e7813add');
INSERT INTO public.comment VALUES ('C264c56d501db', 'U1bcba4fd7175', 'олнаа', '2023-11-10 17:07:52.159485+00', 'B9c01ce5718d1');
INSERT INTO public.comment VALUES ('C7c4d9ca4623e', 'U8aa2e2623fa5', 'qztpkm
', '2023-11-19 12:29:28.09386+00', 'B9c01ce5718d1');
INSERT INTO public.comment VALUES ('Ccc25a77bfa2a', 'U77f496546efa', 'bkhzpb
', '2023-11-20 17:51:43.925976+00', 'Be2b46c17f1da');
INSERT INTO public.comment VALUES ('C5060d0101429', 'U362d375c067c', 'yxgzkz
', '2023-11-25 23:53:14.785882+00', 'Bad1c69de7837');
INSERT INTO public.comment VALUES ('C637133747308', 'Ue202d5b01f8d', 'zcutgo
', '2023-11-25 23:54:27.444848+00', 'B9c01ce5718d1');
INSERT INTO public.comment VALUES ('Cfa08a39f9bb9', 'Ubebfe0c8fc29', 'tjeffz
', '2023-11-25 23:56:32.686068+00', 'Bfefe4e25c870');
INSERT INTO public.comment VALUES ('C63e21d051dda', 'U638f5c19326f', 'test
', '2023-12-15 17:16:25.554001+00', 'Bfefe4e25c870');
INSERT INTO public.comment VALUES ('Cb62aea64ea97', 'U0e6659929c53', 'х', '2023-12-27 13:13:29.109684+00', 'B9c01ce5718d1');
INSERT INTO public.comment VALUES ('Cc2b3069cbe5d', 'Ub01f4ad1b03f', 'What''s the silent fuck?', '2023-12-28 08:09:16.302457+00', 'B9c01ce5718d1');
INSERT INTO public.comment VALUES ('Cbe89905f07d3', 'Ub01f4ad1b03f', 'It''s not titanium...', '2024-01-13 17:59:42.27565+00', 'Bb5f87c1621d5');
INSERT INTO public.comment VALUES ('C13e2a35d917a', 'Uf6ce05bc4e5a', 'ghjjj', '2024-01-26 14:28:12.245616+00', 'Bf843e315d71b');
INSERT INTO public.comment VALUES ('C7722465c957a', 'U72f88cf28226', 'test
', '2024-01-26 14:47:55.112942+00', 'B3f6f837bc345');
INSERT INTO public.comment VALUES ('Cb3c476a45037', 'Ue40b938f47a4', 'g', '2024-01-26 15:10:52.527771+00', 'B9c01ce5718d1');
INSERT INTO public.comment VALUES ('C2d9ab331aed7', 'U4a82930ca419', 'тест', '2024-02-15 21:20:39.272152+00', 'B30bf91bf5845');
INSERT INTO public.comment VALUES ('C472b59eeafa5', 'U4a82930ca419', 'тест', '2024-02-15 21:20:56.335514+00', 'B30bf91bf5845');
INSERT INTO public.comment VALUES ('Cb18d30c672c7', 'U9f2ca949e629', 'hzpbxa
', '2024-08-05 22:20:21.230987+00', 'B79efabc4d8bf');
INSERT INTO public.comment VALUES ('C1aadfb8924d9', 'U77a03e9a08af', 'nmk', '2024-08-05 22:35:07.78793+00', 'Bed48703df71d');
INSERT INTO public.comment VALUES ('C978221bee128', 'Ub01f4ad1b03f', 'Забрало упало и забрало.', '2024-08-06 22:45:46.979073+00', 'B500ed1ecb236');
INSERT INTO public.comment VALUES ('Cacd928c3a8e2', 'U1ece3c01f2c1', 'uqoocb
', '2024-08-08 15:33:44.557209+00', 'Bad1c69de7837');
INSERT INTO public.comment VALUES ('Ce28175f0281e', 'U5a89e961863e', 'kbuybo
', '2024-08-08 15:37:40.282758+00', 'B7f628ad203b5');
INSERT INTO public.comment VALUES ('Cfcd84f06ae08', 'Uccbf9cc1fa1b', 'owxvmr
', '2024-08-09 01:20:00.280586+00', 'Ba3c4a280657d');
INSERT INTO public.comment VALUES ('C6c30787a4fae', 'U77a03e9a08af', 'пнснсри', '2024-08-09 20:47:25.146801+00', 'Bed48703df71d');
INSERT INTO public.comment VALUES ('C415d72e2693c', 'U77a03e9a08af', 'ололол', '2024-08-10 17:25:24.755034+00', 'Be64122664ec6');
INSERT INTO public.comment VALUES ('Ca45424255fa7', 'U05c63e1de554', 'gdxsol
', '2024-08-12 23:14:15.659128+00', 'Bad1c69de7837');
INSERT INTO public.comment VALUES ('Cd99672e62e8f', 'U85af6afd0809', 'wfsdts
', '2024-08-12 23:16:17.336147+00', 'Bad1c69de7837');
INSERT INTO public.comment VALUES ('C0f761a65e114', 'U77a03e9a08af', '"манта", ага. экипаж 4, как раз', '2024-08-16 13:51:31.773366+00', 'B4b8fafa86526');
INSERT INTO public.comment VALUES ('C8f4c0941cc9e', 'Uf82dbb4708ba', 'ghjjeie jdjdi ejdjdi', '2024-08-16 14:28:17.781884+00', 'Bad1c69de7837');
INSERT INTO public.comment VALUES ('Cea68dab28855', 'Uaebcaa080fa8', 'x ', '2024-08-20 22:36:01.952668+00', 'B5eb4c6be535a');
INSERT INTO public.comment VALUES ('C4e48075dc4da', 'U9de057150efc', 'Test comment 1', '2024-08-21 14:13:00.909811+00', 'B91796a98a225');
INSERT INTO public.comment VALUES ('C1b65b900a13a', 'U0be96c3b9883', 'hello anna', '2024-08-21 15:01:12.884004+00', 'B1533941e2773');
INSERT INTO public.comment VALUES ('C72ab5060f2cb', 'U5d33a9be1633', 'hello anna from bob', '2024-08-21 15:01:45.896041+00', 'B1533941e2773');
INSERT INTO public.comment VALUES ('Caf2370c548ce', 'U0d2e9e0dc40e', 'bla', '2024-08-21 16:17:46.654222+00', 'B3f6f837bc345');
INSERT INTO public.comment VALUES ('C6bda754da97b', 'Ub4b46ee7a5e4', 'Hello from Flutter web client :-)', '2024-08-22 20:42:24.144983+00', 'B500ed1ecb236');
INSERT INTO public.comment VALUES ('Cc3a1b76c43a1', 'U3ea0a229ad85', 'It is mine alter ego!', '2024-08-22 21:52:19.540391+00', 'B5f6a16260bac');
INSERT INTO public.comment VALUES ('Cc7c6ce4cba1c', 'U29a00cc1c9c2', 'bla
', '2024-08-24 17:12:38.97049+00', 'B60d725feca77');
INSERT INTO public.comment VALUES ('Ccbb443602977', 'U29a00cc1c9c2', 'lll
', '2024-08-24 17:14:27.33566+00', 'Beaa423fabf17');
INSERT INTO public.comment VALUES ('Cdc72f8f77531', 'U55272fd6c264', 'my first comment', '2024-08-24 17:16:03.58205+00', 'Bc8526e892c5d');
INSERT INTO public.comment VALUES ('C1f463ef711d7', 'U0be96c3b9883', 'bhesd', '2024-08-29 16:31:53.064397+00', 'Bc4603804bacf');


--
-- Data for Name: user; Type: TABLE DATA; Schema: public; Owner: postgres
--

INSERT INTO public."user" VALUES ('Ue072a0d01754', '2024-07-13 19:23:30.14055+00', '2024-07-13 19:23:30.14055+00', '', '', false, '5qUGTNjiQTXDHw-gXDKSNYQY6OdEceqy9IndgttzHL0');
INSERT INTO public."user" VALUES ('U93bb26f51197', '2024-07-13 19:23:51.636186+00', '2024-07-13 19:23:51.636186+00', '', '', false, 'crRX2GAdasNwKv4sIvZCsC9cvv3LsnFR8MwFgETDn4A');
INSERT INTO public."user" VALUES ('U53d9eaa11929', '2024-07-15 07:33:21.231838+00', '2024-07-15 07:33:21.231838+00', '', '', false, 'WWPrMOZryQL50Wd9kBTE7H_Qok5A1ouPB0URE_WTo7E');
INSERT INTO public."user" VALUES ('Uc2fdcf17c2fe', '2024-08-01 11:06:14.224837+00', '2024-08-01 11:06:14.224837+00', '', '', false, 'RIrNLUJOHcCtF_BUuZOLYgVIPZjjDAabSTmyb04UF9A');
INSERT INTO public."user" VALUES ('Ua1342df2a349', '2024-08-01 11:06:14.591088+00', '2024-08-01 11:06:14.591088+00', '', '', false, 'BKWoi7dufvboqSGkzn8nK6FoiwuWXWDbtdrsIdzmJA0');
INSERT INTO public."user" VALUES ('Uebf1ab7a1e6b', '2024-08-01 11:06:36.797892+00', '2024-08-01 11:06:36.797892+00', '', '', false, 'tHWF0NKEmd0DUJNppErX8mTSF28wBWno366g5lyHkLU');
INSERT INTO public."user" VALUES ('U0ae9f5d0bf02', '2024-08-04 22:37:31.75533+00', '2024-08-05 22:27:43.296302+00', 'Vadim 5-8', '', false, 'B8hMlFeYU6cWomlLrp0E7H8j5SwlM4ZUiT1D-hDUSRk');
INSERT INTO public."user" VALUES ('U12ae6809a644', '2024-08-06 13:43:12.657656+00', '2024-08-06 13:43:12.657656+00', '', '', false, '1ERSfSisei1foSkagRO0PrzLCq3xuq31oh9Qe1R0INk');
INSERT INTO public."user" VALUES ('Uaea5ee26a787', '2024-08-08 15:24:29.450447+00', '2024-08-08 15:24:29.450447+00', '', '', false, 'VsQtssjmXRkjbgHgNTc2aSvXOyYuDqijPOrW10GHtK8');
INSERT INTO public."user" VALUES ('U3de05e2162cb', '2024-08-08 15:24:34.910109+00', '2024-08-08 15:24:34.910109+00', '', '', false, 'O9KepjqBIgn18cZ8HgkZoc06j2wnTuWKjMBjJJCaE0g');
INSERT INTO public."user" VALUES ('U3e8df87e89aa', '2024-08-08 15:24:36.734032+00', '2024-08-08 15:24:36.734032+00', '', '', false, '-jNrNc5t2fromiYa2_KCy1D3osg7af7LqA2k2f0KItc');
INSERT INTO public."user" VALUES ('Ucd80daf02c58', '2024-08-08 15:24:48.019034+00', '2024-08-08 15:24:48.019034+00', '', '', false, 'SmUYwiyMU_KN7GFkqaZD2g2W9_VsptaQzZ8OeSOKyEU');
INSERT INTO public."user" VALUES ('U2343287cf1f5', '2024-08-08 15:24:49.941263+00', '2024-08-08 15:24:49.941263+00', '', '', false, '6afe8-go1v9u6gTEUXfGokFn-oi0gFYclXUdm1KAHqE');
INSERT INTO public."user" VALUES ('Uca1f8af28971', '2024-08-08 15:25:20.989898+00', '2024-08-08 15:25:20.989898+00', '', '', false, 'Do8mly9FNJuRc3sH9cjdcNL2XM5Wsp-T2DL9tq0uKhI');
INSERT INTO public."user" VALUES ('Uc2cb918a102c', '2024-08-09 01:07:48.430871+00', '2024-08-09 01:07:48.430871+00', '', '', false, 'HNDERWZgfwoY78wxeodY5wuyv0e7Uce0GIcIMRMlBMk');
INSERT INTO public."user" VALUES ('U4389072867c2', '2024-08-09 01:08:23.417555+00', '2024-08-09 01:08:23.417555+00', '', '', false, '6Mob0-d83kgnUYOGUNjZ3ZU8iy6TIC_9qwFYNHjq1LM');
INSERT INTO public."user" VALUES ('Uf28fa5b0a7d5', '2024-08-09 01:13:00.875511+00', '2024-08-09 01:13:00.875511+00', '', '', false, 'qicbE9F2Lr5oiaaBq8yCityf3mmYxAs5K66LgvgWTiI');
INSERT INTO public."user" VALUES ('Ud9bba649c185', '2024-08-13 07:49:54.905673+00', '2024-08-13 07:49:54.905673+00', '', '', false, 'PGMniauWTCNIp4veJn8tvx2i6lFxCyGM-aBhMibOrX8');
INSERT INTO public."user" VALUES ('Uf82dbb4708ba', '2024-08-16 14:24:42.493646+00', '2024-08-16 14:26:55.798131+00', 'Kato', 'ui ux designer', true, 'doSTLLdmAUFsW6VRRNfAOI_fo-KxigFGiWeMb88mIdQ');
INSERT INTO public."user" VALUES ('U0be96c3b9883', '2024-08-21 10:28:16.751659+00', '2024-08-21 10:48:18.245836+00', 'Alice', '', true, 'FHe6Q3adUpU4AuVunMqPYa6yJlVptH-__SoQUlrcyAM');
INSERT INTO public."user" VALUES ('Ub4b46ee7a5e4', '2024-08-22 20:29:36.831416+00', '2024-08-22 20:38:57.490672+00', 'First web user', 'Created with Flutter web', true, 'c2VlrhZBWD9AFlWniEXni69Jqp6eHZ1hk3jifYtkU5o');
INSERT INTO public."user" VALUES ('Ub4fca45d7b4d', '2024-08-25 09:33:57.363883+00', '2024-08-25 09:33:57.363883+00', '', '', false, 'A_K0HPcQlqMRn4YIw7Qocl2ZpDVAt_GYDXaSdDcTM1k');
INSERT INTO public."user" VALUES ('U23f731b62702', '2024-08-27 15:14:14.839711+00', '2024-08-27 15:14:14.839711+00', '', '', false, 'bSUtVQRtB21cG5ZLoizFE9IB37csW3kLWc_HTyJUm_o');
INSERT INTO public."user" VALUES ('Ue869379c5a35', '2024-08-30 13:43:03.09626+00', '2024-08-30 13:43:03.09626+00', '', '', false, 'dS1vFXWK5IJYBV12qLhTMZzOqQ9iRyzPsMfFhBOKaC8');
INSERT INTO public."user" VALUES ('U691ef45270ae', '2024-09-07 22:12:41.365632+00', '2024-09-07 22:12:41.365632+00', '', '', false, 'eUzsd6Q26nwPl_c6tweenO7C-6gDuu73imyCl59EUac');
INSERT INTO public."user" VALUES ('Ufe8cdd16cc19', '2024-09-08 15:12:18.379096+00', '2024-09-08 15:12:18.379096+00', '', '', false, '4D6HVcKoPKUL5HQiIjj8Ab3NdWRfK2z47ZDRwdaWN0I');
INSERT INTO public."user" VALUES ('U2c8e7b806cb4', '2024-07-13 19:23:43.338009+00', '2024-07-13 19:23:43.338009+00', '', '', false, '2TBu2DtjIqeQzwhTyy9sbyPtLjIu-C82MFyULrl3O4k');
INSERT INTO public."user" VALUES ('U998403e8a30d', '2024-07-13 19:24:27.470999+00', '2024-07-13 19:24:27.470999+00', '', '', false, 'RwwJ4W0uVnzi-cDxg_1wkCyNk4l_Ty9feyoerEkjIxs');
INSERT INTO public."user" VALUES ('Ud719123749e6', '2024-07-13 19:24:46.430149+00', '2024-07-13 19:24:46.430149+00', '', '', false, 'thITZk0ljwUO2d58epYlblhexR7XzRXekXiqMZMeZKg');
INSERT INTO public."user" VALUES ('Ued1594827196', '2024-07-13 19:24:53.181305+00', '2024-07-13 19:24:53.181305+00', '', '', false, 'HFQlido2QyBuZkqLo6khoKUmAPDhoUUmrpKSe3B6Owo');
INSERT INTO public."user" VALUES ('U9d12c9682206', '2024-07-13 19:28:04.777045+00', '2024-07-13 19:28:04.777045+00', '', '', false, '6v8RcfJRRluTCcFNqL1ngy_iDiOSqsypwl693Ibsirs');
INSERT INTO public."user" VALUES ('Ue5c836f6e6b5', '2024-07-13 19:28:15.407039+00', '2024-07-13 19:28:15.407039+00', '', '', false, '_A7QUOY04pu08qaz5e3AckmHPTMj-MQgoiS8iEhJjic');
INSERT INTO public."user" VALUES ('U64bb80ebf463', '2024-07-15 07:41:43.394268+00', '2024-07-15 07:41:43.394268+00', '', '', false, 'olr7c56T5CPgjJu10KKdZ5nmm84nkANIgittc04mhgI');
INSERT INTO public."user" VALUES ('Uad7e22db9014', '2024-08-01 11:06:35.469549+00', '2024-08-01 11:06:35.469549+00', '', '', false, 'og07ii7LSQwI1oXhkAwR6lE8oVNZowhTHq-ov7BWw9k');
INSERT INTO public."user" VALUES ('Ua0ece646c249', '2024-08-01 11:08:14.164847+00', '2024-08-01 11:08:14.164847+00', '', '', false, 'F9ya6zcarxLQ_XAi64LvVhoAkA-yt-JkXTkpMAV2-jU');
INSERT INTO public."user" VALUES ('Ua5c4a6b171b2', '2024-08-01 11:11:52.74816+00', '2024-08-01 11:11:52.74816+00', '', '', false, 'gSSDsJ5Cmri6v0-vLxJTwx3hi3w_UIa5HtDYVTq7E-Q');
INSERT INTO public."user" VALUES ('U6fa666cd4b28', '2024-08-01 11:11:59.690533+00', '2024-08-01 11:11:59.690533+00', '', '', false, 'PlOqK_mKt_v5OqvM_yOrLUNwLRCsoc9ex_Nzl5CAMoA');
INSERT INTO public."user" VALUES ('Ucc76e1b73be0', '2024-08-01 11:08:05.534327+00', '2024-08-01 15:06:15.924485+00', 'Vadim 1/08', '', false, 'sIH5f8cJW7RJBg3BFUGZ5T1HnR--2HCn3PTpYA9VYE8');
INSERT INTO public."user" VALUES ('Ub01f4ad1b03f', '2023-12-28 08:03:57.807111+00', '2024-08-04 22:42:18.478347+00', 'Bonnie Nem', 'Descriptor', true, 'RLg-iRpmpiA2v19PCzmd7strVTK5hMPhqln_cEJNmnk');
INSERT INTO public."user" VALUES ('Udac87a2966dc', '2024-08-08 15:25:20.988254+00', '2024-08-08 15:25:20.988254+00', '', '', false, 'yDn8X4NyAkm1aVyS8zKmawFJvDDsOCzny_rA5efFLgE');
INSERT INTO public."user" VALUES ('Uccbf9cc1fa1b', '2024-08-09 01:16:33.532837+00', '2024-08-09 01:16:33.532837+00', '', '', false, 'gEzREOTCEWEVgi42C_OsYpwUWKVsFLqB5hWVY81dA-g');
INSERT INTO public."user" VALUES ('U1ccc3338ee60', '2024-08-13 23:01:03.736179+00', '2024-08-13 23:01:03.736179+00', '', '', false, 'hnDNOThF87N_6_rddBHUmqGMVzIMiA9Ro3Q7gZW8iv0');
INSERT INTO public."user" VALUES ('U222feac6e72c', '2024-08-17 01:14:46.383233+00', '2024-08-17 01:14:46.383233+00', '', '', false, 'BsQg8xRUYbr9het5OcHzY8yIfL9X_abF8LShjwPSGzY');
INSERT INTO public."user" VALUES ('U5d33a9be1633', '2024-08-21 10:48:32.191808+00', '2024-08-21 10:49:09.516861+00', 'Bob', '', true, 'mSh-R8397hgWUU2rOC5Koz2c88ibGH3FkCrNR_0Qf38');
INSERT INTO public."user" VALUES ('U17b825d673df', '2024-08-21 10:49:21.750515+00', '2024-08-21 10:49:36.891057+00', 'Sybil', '', true, 'dgyYsMBy_BDh-WlUzsWLp17_KHjULq89VfmFYByw3tA');
INSERT INTO public."user" VALUES ('U0d2e9e0dc40e', '2024-08-21 10:49:58.516425+00', '2024-08-21 10:54:38.632963+00', 'Sybil''s bot', '', true, '_bS_5no6K00SpMcOSrmI43WRpK1nNN_5xbGK4c20y7g');
INSERT INTO public."user" VALUES ('U3ea0a229ad85', '2024-08-22 21:46:13.95243+00', '2024-08-22 21:48:42.886082+00', 'Pussy Cat', 'This is it!
Yet another account created with Flutter Web.', true, '1UMBnxgxeRBL4037219_35CPvRbPmsP2QU1RURytihw');
INSERT INTO public."user" VALUES ('Ufcf26f390e3c', '2024-08-26 19:59:36.958905+00', '2024-08-26 19:59:36.958905+00', '', '', false, 'ufr9xzEVNK-kuQxm62FsxlvIsnK-_-FfhuZo8z0jE2E');
INSERT INTO public."user" VALUES ('U90b0d3d5d688', '2024-08-27 15:15:58.668687+00', '2024-08-27 15:15:58.668687+00', '', '', false, 'kfkTCcZrzuo9jP1-Xl4rbFuPPsNOz1bLsqqKn8oXf9g');
INSERT INTO public."user" VALUES ('U5cd67e57a766', '2024-08-30 14:16:13.05826+00', '2024-08-30 14:16:13.05826+00', '', '', false, 'T8zFoUtaB9x8Bj45f5pdLZM_8xeNi3f1vVORTzL2FLc');
INSERT INTO public."user" VALUES ('U7d494d508e5e', '2024-09-08 04:25:30.495454+00', '2024-09-08 04:25:30.495454+00', '', '', false, 'hWYsRhf4lkN5uh3z7GT7My9ccDYh76WnDkc1h3gXAfc');
INSERT INTO public."user" VALUES ('U878e125bdaac', '2024-09-08 04:30:26.547737+00', '2024-09-08 04:30:26.547737+00', '', '', false, 'ZW582huCrFlS2Ujn7A3XvXJ8Ul3ozRPo1yjNxhqewnI');
INSERT INTO public."user" VALUES ('Ud23a6bb9874f', '2024-09-08 04:33:25.313897+00', '2024-09-08 04:33:25.313897+00', '', '', false, 'ToJ1symoIZfNhq4IgJFvKy6fjyQ5idJ3r_cd8ujyzyk');
INSERT INTO public."user" VALUES ('U07550344f328', '2024-07-14 11:16:06.196973+00', '2024-07-14 11:16:06.196973+00', '', '', false, 'j_5-M_dPTamkz6Gslby9QZ3EiTD06D_p5_Ib4h1TsO0');
INSERT INTO public."user" VALUES ('U5fca8e8b4184', '2024-07-15 12:03:22.083639+00', '2024-07-15 12:03:22.083639+00', '', '', false, 'g3axw4yzg5uDfg8tReorE7rFk99e9g-rPs-NPctxUh0');
INSERT INTO public."user" VALUES ('U3f893817ccc2', '2024-07-15 12:03:39.754827+00', '2024-07-15 12:03:39.754827+00', '', '', false, '-IXh3v5liHoeh414LcDAQ5onBUKiKvlY_g-f9FqFa24');
INSERT INTO public."user" VALUES ('Uad8134e80ae1', '2024-07-15 12:03:40.552247+00', '2024-07-15 12:03:40.552247+00', '', '', false, 'UxXprev0VqxXjqlKmG5aXTtT8AH8WvitTGUKlEjfJ44');
INSERT INTO public."user" VALUES ('Uc92c678769f6', '2024-07-15 12:04:10.02876+00', '2024-07-15 12:04:10.02876+00', '', '', false, 'q6wuMk4kf7dASABRZMx9im0EQUeLTH5arIzSV3Z4DR4');
INSERT INTO public."user" VALUES ('U78d15bf5156f', '2024-07-15 12:06:30.169945+00', '2024-07-15 12:06:30.169945+00', '', '', false, 'GDp66oImLJg01g2Yzt80l8Dm3zSWMGLAQVQPhX5jewE');
INSERT INTO public."user" VALUES ('Uaf38ffff522d', '2024-07-15 12:09:28.999875+00', '2024-07-15 12:09:28.999875+00', '', '', false, 'QdoXC2WnhY8_8jIHbV50SywyszEYinL7bAR_QWRbgVA');
INSERT INTO public."user" VALUES ('U09ce851f811d', '2024-08-04 11:51:56.354237+00', '2024-08-04 11:51:56.354237+00', '', '', false, '2iEHIr3wylusPHTnsPnyRGxx1Ey9O91Zi9LgrU_pXMg');
INSERT INTO public."user" VALUES ('Uf07cfc181d70', '2024-08-05 22:11:59.876091+00', '2024-08-05 22:11:59.876091+00', '', '', false, 'HRY-Dj2eKE6aU9qGxhH6WdaHelcz9DOeLkBE-WFIvno');
INSERT INTO public."user" VALUES ('U9f2ca949e629', '2024-08-05 22:19:09.511934+00', '2024-08-05 22:19:09.511934+00', '', '', false, 'usov67PDI37SR0Bjnd7UjVxOLHcH2aeB1D9ktRxTr-M');
INSERT INTO public."user" VALUES ('Ubd4ba65ba102', '2024-08-05 22:19:13.150994+00', '2024-08-05 22:19:13.150994+00', '', '', false, 'Q-vkaid1uiO2gUM0BrHgU9JfEclEavyxT4GM0nE2Iug');
INSERT INTO public."user" VALUES ('U2a3519a5a091', '2024-08-08 15:25:21.002267+00', '2024-08-08 15:25:21.002267+00', '', '', false, 'lIkUVpeNBtKL9h6SzIkKevpTzjZFZSN8mc7cO9ASOLg');
INSERT INTO public."user" VALUES ('U2baf1fc3bc0d', '2024-08-10 00:59:31.868489+00', '2024-08-10 00:59:31.868489+00', '', '', false, 'pro8p3D-p9EEVRl28vlexkk_ExitJCILRza5iaCI7B4');
INSERT INTO public."user" VALUES ('U7d4884eabf34', '2024-08-13 23:01:34.742776+00', '2024-08-13 23:01:34.742776+00', '', '', false, 'nmkjdWrWmPUL9VUzXQz94opGdMxC-7JpKBQIUChSAsA');
INSERT INTO public."user" VALUES ('Ue1c6ed610073', '2024-08-13 23:01:40.263458+00', '2024-08-13 23:01:40.263458+00', '', '', false, 'HRBqF71vOZjTY_xrpTUlXbkei2JQDQ7BOi-lOij04bw');
INSERT INTO public."user" VALUES ('U0fc148d003b7', '2024-08-13 23:01:43.674259+00', '2024-08-13 23:01:43.674259+00', '', '', false, 'UMbKxpPNMd0VP44_ENsL3WwUJQnrUJIerIzcsHH29q4');
INSERT INTO public."user" VALUES ('U4bab0d326dee', '2024-08-13 23:05:14.184482+00', '2024-08-13 23:05:14.184482+00', '', '', false, 'FRDsueAd638h-uLrHGkaKoxdxnP6NkK2WDpaNX8-Ypk');
INSERT INTO public."user" VALUES ('Ue70081ae1455', '2024-08-13 23:07:41.415077+00', '2024-08-13 23:07:41.415077+00', '', '', false, '4LcI55TOhFwtFYEzOdwYWCJufZ1kc0TR9dWp-TgnmO0');
INSERT INTO public."user" VALUES ('Ub47d8c364c9e', '2024-08-17 13:35:26.832349+00', '2024-08-17 13:35:39.251192+00', 'Carol', '', false, 'uKZkn3JF0XIdZAiZtaMZQfqH9FdfxmYJMWYxCFTP5o4');
INSERT INTO public."user" VALUES ('Uc02f96c370bd', '2024-08-21 11:38:49.737535+00', '2024-08-21 11:38:49.737535+00', '', '', false, 'D9a81FOVUI0S0bQSyBS31aRZucyPTPJgLSMhovOxvJ8');
INSERT INTO public."user" VALUES ('U163b54808a6b', '2024-08-24 16:59:56.382475+00', '2024-08-24 17:01:36.92293+00', 'Pussycat', 'And no need words', true, 'DdvPZJtqKDXEo4fra7XTdUlkolQpnhWrOKeAoVTVYPI');
INSERT INTO public."user" VALUES ('U20c0f211a102', '2024-08-27 17:41:37.225455+00', '2024-08-27 17:41:37.225455+00', '', '', false, 'S8pdVwFeDr9oJXjZ0rN2yYypK-1uic8yGoLbv2IUlPQ');
INSERT INTO public."user" VALUES ('U64deda622d4d', '2024-09-05 20:18:31.117659+00', '2024-09-05 20:18:31.117659+00', '', '', false, 'QWxnLgen5haJRlD_0GJSqnr3cERHR5QQ7_7sBQJMu14');
INSERT INTO public."user" VALUES ('U9254ac689880', '2024-09-08 06:53:20.580264+00', '2024-09-08 06:53:20.580264+00', '', '', false, 'kPqn8PI9WShgVECtkmJ85x1dy7iYDDgU69TKYtMHsS4');
INSERT INTO public."user" VALUES ('U8b4a27f32216', '2024-07-15 12:03:36.582951+00', '2024-07-15 12:03:36.582951+00', '', '', false, '-sWEb5QOCXwBoEwVAxzeE9UnePm8XJa9yjkkyuh8NwY');
INSERT INTO public."user" VALUES ('U6d7505511a4c', '2024-08-05 22:12:19.861064+00', '2024-08-05 22:12:19.861064+00', '', '', false, 'B89ToRZULG9yPrDQCzSh0BuxGU2kB1Cm73eFnm--tvs');
INSERT INTO public."user" VALUES ('Uc406b9444f78', '2024-08-05 22:12:35.93573+00', '2024-08-05 22:12:35.93573+00', '', '', false, '9RUWnUbxQLCUKo0iTvt5PN2bz0cJGmq3cNTcjg8UKoo');
INSERT INTO public."user" VALUES ('U15333c20136a', '2024-08-05 22:12:46.485508+00', '2024-08-05 22:12:46.485508+00', '', '', false, 'IWTCAT-y-FUqewKUHlq1tw1jvyxzRvIzMmoHBVptqLU');
INSERT INTO public."user" VALUES ('U38c58796a985', '2024-08-05 22:12:46.868509+00', '2024-08-05 22:12:46.868509+00', '', '', false, 'w7V12M_fNsej_1pvlLmR8Y_rBJmUyQxBIjCkJN0bCbs');
INSERT INTO public."user" VALUES ('U1ece3c01f2c1', '2024-08-08 15:32:48.325998+00', '2024-08-08 15:32:48.325998+00', '', '', false, 'PFyHqCngqkpb_lYja6tFHbr0HrsYDgdFWXAuAkwZQfc');
INSERT INTO public."user" VALUES ('U5a89e961863e', '2024-08-08 15:34:53.020468+00', '2024-08-08 15:34:53.020468+00', '', '', false, 'dKBp0ywWoObu7Rbxwr41qw7UcAY-X4bxEU4LXzeZbQs');
INSERT INTO public."user" VALUES ('U14debbf04eba', '2024-08-10 11:18:41.23108+00', '2024-08-10 11:18:41.23108+00', '', '', false, 'QVumUacxWdr8iLNXn_rEmLOISokz0dhCDCWuObcmaxw');
INSERT INTO public."user" VALUES ('U7debdb69f42f', '2024-08-13 23:16:35.061163+00', '2024-08-13 23:16:35.061163+00', '', '', false, '_xIpkaMdisZB9nLGjzAX4QLukT-atjOntFwdwl4F3gg');
INSERT INTO public."user" VALUES ('U605b0f5ff7c3', '2024-08-18 23:32:30.699382+00', '2024-08-18 23:32:30.699382+00', '', '', false, 'nklHBXPVWqRu2_mmLWV6r3aNFFWRAcvgBpsKFc2GehY');
INSERT INTO public."user" VALUES ('U093523c2ff6a', '2024-08-18 23:32:31.709981+00', '2024-08-18 23:32:31.709981+00', '', '', false, '8_6SMvssK_WgZDtopoty95nP4yKPHIEJgjJacqcJUGc');
INSERT INTO public."user" VALUES ('U0d088ca75803', '2024-08-18 23:32:34.679437+00', '2024-08-18 23:32:34.679437+00', '', '', false, 'Rn6r9f0JrCaKnvEDLVuv7FYceBLfEb6Drz_4QzRyzpg');
INSERT INTO public."user" VALUES ('U78ac2807b784', '2024-08-21 12:34:42.862528+00', '2024-08-21 12:34:42.862528+00', '', '', false, 's3dik7NTIIchsNeudY5e-raNipy4YOLX2nftPSZzTEY');
INSERT INTO public."user" VALUES ('U18727b34482c', '2024-08-21 12:35:15.418697+00', '2024-08-21 12:35:15.418697+00', '', '', false, 'M212B-Zm_caJwC-uAhtd28-F79y-iZy6IauYn5Im2PI');
INSERT INTO public."user" VALUES ('Ucfdea362a41c', '2024-08-24 17:04:17.035045+00', '2024-08-24 17:04:17.035045+00', '', '', false, 'bn_pw8EduvhiXdGlab9ajGuBEzxh9EPCvGq5kOQuiXk');
INSERT INTO public."user" VALUES ('Uc9fc0531972e', '2024-08-24 17:04:44.378491+00', '2024-08-24 17:04:44.378491+00', '', '', false, 'GsSfodSlBW0mkk3kg7PMFUGm_0DhQTsuSdmoj4RCC3s');
INSERT INTO public."user" VALUES ('U55272fd6c264', '2024-08-24 17:03:51.135596+00', '2024-08-24 17:07:43.393127+00', 'KleoCatra', 'Mum''s cat', true, 'JlZRI3Row31FwHKvltG05CJW1KyTEMineRrmU8aoRWc');
INSERT INTO public."user" VALUES ('Ue45a5234f456', '2024-08-24 17:11:41.208431+00', '2024-08-24 17:11:41.208431+00', '', '', false, 'pnUPn_xCbPy8zGBlIRgB6ODJbUoS_gHcLXA7cM1w-8Y');
INSERT INTO public."user" VALUES ('U29a00cc1c9c2', '2024-08-24 17:11:48.334045+00', '2024-08-24 17:12:03.062212+00', 'web v', '', false, 'EuZJxtrnqrl02q8oNy3dQMWWtoH8YjEyTx59AmhL6w4');
INSERT INTO public."user" VALUES ('Ue8faa533ace5', '2024-08-27 17:42:40.74717+00', '2024-08-27 17:42:40.74717+00', '', '', false, 'QjqfPvG96ylgAGYvcymaTGDYJ7SDy1J_rXBtFBRbF4g');
INSERT INTO public."user" VALUES ('Ua91cd34052a5', '2024-08-27 17:43:22.654194+00', '2024-08-27 17:43:22.654194+00', '', '', false, '5RhC8Vj7xL_KzkzWHzBscSAnr1XH4h0i3EJF-JLbV6Y');
INSERT INTO public."user" VALUES ('U89f659e858be', '2024-09-05 23:45:32.297094+00', '2024-09-05 23:45:32.297094+00', '', '', false, 's_dGp_pj0MiXlm3QqXGjuRaRIxErd-FS4xQmfZA6SLs');
INSERT INTO public."user" VALUES ('U8fc18a35ee3b', '2024-09-08 07:10:01.385854+00', '2024-09-08 07:10:01.385854+00', '', '', false, 'bKHKnOCIWo4Y1xoSqgxtLTb4ibMwkaopYM-uXznB8x0');
INSERT INTO public."user" VALUES ('U2dad9535aaae', '2024-07-15 13:13:33.686418+00', '2024-07-15 13:13:33.686418+00', '', '', false, 'wUPjvwrzI3OumExpMr5ZWj34i0qA9ELPlRYRM2WG1KQ');
INSERT INTO public."user" VALUES ('U000000000000', '2023-12-20 23:37:34.043065+00', '2024-07-23 22:35:05.950428+00', 'Tentura', 'Kind a black hole', true, 'nologin');
INSERT INTO public."user" VALUES ('U57c0388e5cb5', '2024-07-15 13:16:45.502313+00', '2024-07-26 19:59:06.004758+00', 'v26', '', false, 'UsEfeCSOyf0lB9nj2wQlrC5uGju4Qc5pSsMipS-xpE8');
INSERT INTO public."user" VALUES ('U006251a762f0', '2024-08-08 17:15:44.197091+00', '2024-08-08 17:15:44.197091+00', '', '', false, 'aExPFkN4SkveUQt1VuLo7Fxb6zgjjI9JBFoYeRTwUJw');
INSERT INTO public."user" VALUES ('U808cdf86e24f', '2024-08-12 23:06:27.87267+00', '2024-08-12 23:06:27.87267+00', '', '', false, 'ECIpbSfu7VFKYQuEOGsjokCFCqQVexowpxfk_VpDbEY');
INSERT INTO public."user" VALUES ('U62360fd0833f', '2024-08-12 23:07:05.823202+00', '2024-08-12 23:07:05.823202+00', '', '', false, 'RK2lwjWzX1zdV_bUG-EGmSJ5QeYxRkpd34kJXuZtBiI');
INSERT INTO public."user" VALUES ('Ud3f25372d084', '2024-08-12 23:07:06.070158+00', '2024-08-12 23:07:06.070158+00', '', '', false, 'ihCl-_NBCPeDcV5Q8xUrKExuQPmQaMllMOwxy3TLItY');
INSERT INTO public."user" VALUES ('U15e4831e566e', '2024-08-14 17:07:53.668609+00', '2024-08-14 17:07:53.668609+00', '', '', false, '5GzsT2cygwx0sszPQu7UlHupgNrb_Wnec4-6v6nx900');
INSERT INTO public."user" VALUES ('U77a03e9a08af', '2024-08-05 22:28:05.909683+00', '2024-08-17 13:22:43.390466+00', 'V-subs', '', false, 'pZv94BOAfjZzFgwm23aWjb-sYuOTzM9IEp3A9gnFixg');
INSERT INTO public."user" VALUES ('Uaebcaa080fa8', '2024-08-20 22:31:53.471478+00', '2024-08-20 22:31:53.471478+00', '', '', false, 'KSIOnxEGbjEO8hGnogt50YfVLmRK8aSW890s4oAkOhA');
INSERT INTO public."user" VALUES ('U06f2343258bc', '2024-08-20 22:32:00.034524+00', '2024-08-20 22:32:00.034524+00', '', '', false, 'fT2nsruEBqMz36o4KJQNjXpytSP8CaaVC1eNyjVDGdo');
INSERT INTO public."user" VALUES ('U9d5605fd67f3', '2024-08-20 22:32:20.637213+00', '2024-08-20 22:32:20.637213+00', '', '', false, '4cKSvHsB4ABEzyqCkUrLZzpLhdpGoBMkP2hnBr2zfBM');
INSERT INTO public."user" VALUES ('U01d7dc9f375f', '2024-08-20 22:32:24.72092+00', '2024-08-20 22:32:24.72092+00', '', '', false, '1bmdLr-FheZ8Qur_GuaJYnncpRE46zhuzl-0Vnsp8Lw');
INSERT INTO public."user" VALUES ('U9de057150efc', '2024-08-21 12:55:02.448228+00', '2024-08-21 13:09:29.190677+00', 'Test User', 'Lorem ipsum dolor sit amet, consectetur adipiscing elit. Ut in felis a tellus gravida dapibus. Quisque gravida odio quam, at tincidunt libero ullamcorper non. Ut tempus ante at gravida pharetra. Curabitur nec mattis eros. Donec faucibus libero sit amet convallis semper. Maecenas at tellus vel ipsum pharetra vehicula. Fusce ornare eu ipsum vel malesuada. Praesent ac leo erat. Fusce ligula leo, finibus sit amet lacinia sit amet, dignissim in mauris. Sed auctor magna sit amet congue ultrices.', false, '5hgTfYTavsGrG0ZnlylN1WHSbEIG1EmfQxFb2LVHdK0');
INSERT INTO public."user" VALUES ('Ucd6310f58337', '2024-08-24 17:04:05.496023+00', '2024-08-24 17:04:05.496023+00', '', '', false, 'eog7IMcIrv5HtRWBfnTNxLzFBS6flInBNycNuPzn4aQ');
INSERT INTO public."user" VALUES ('U99266e588f08', '2024-08-24 17:04:27.441757+00', '2024-08-24 17:04:27.441757+00', '', '', false, 'VT2auemppbTQn9SCQUOCt6d2dEj4UC1XrwrvHkX7-3U');
INSERT INTO public."user" VALUES ('U1715ceca6772', '2024-08-24 17:04:39.649719+00', '2024-08-24 17:04:39.649719+00', '', '', false, 'UEtaG7CfYWYY_VohfpKP8dh5sV6v5hNzkDKzMaGZfIw');
INSERT INTO public."user" VALUES ('U70a397181807', '2024-08-29 14:07:38.265144+00', '2024-08-29 14:07:38.265144+00', '', '', false, '5qZO98MGBTOsTCfhzJDOd_WSEwQfRFx3crdHu7wLR-Q');
INSERT INTO public."user" VALUES ('U0080a5f2547d', '2024-09-07 21:01:08.931614+00', '2024-09-07 21:20:01.582019+00', 'KillMeSoftly', '', true, 'cQPAf2M8EuwtufkglwVeC_lce4cr1pGWJ8bAksCAmU0');
INSERT INTO public."user" VALUES ('Ud21004c2382a', '2024-09-08 09:31:20.710071+00', '2024-09-08 09:34:51.334406+00', 'dmm', '', false, '4liBMRMESBr4VrhDSh0Td-pK_E2wMafeVgOkhJIDHmE');
INSERT INTO public."user" VALUES ('Uadeb43da4abb', '2023-09-26 10:54:45.133958+00', '2024-07-09 12:54:29.214478+00', 'Alberta Schamberger Sr.', 'Quam vulputate dignissim suspendisse in est ante in.', false, 'GeneratedeM9Mf80UgH58X3EOF7C');
INSERT INTO public."user" VALUES ('U016217c34c6e', '2023-09-26 10:54:45.133958+00', '2024-07-09 12:54:29.214478+00', 'Dr Samir Cassin IV', '', false, 'Generatedilbqsl56EGYrADTCBgh');
INSERT INTO public."user" VALUES ('U7a8d8324441d', '2023-09-26 10:54:45.133958+00', '2024-07-09 12:54:29.214478+00', 'Natalie Thiel', 'Tortor dignissim convallis aenean et tortor.', false, 'GeneratedUuKwHtPBoSzbLuGwBfd');
INSERT INTO public."user" VALUES ('Uad577360d968', '2023-09-26 10:54:45.133958+00', '2024-07-09 12:54:29.214478+00', 'Adaline Gibson', 'Proin nibh nisl condimentum id venenatis a condimentum vitae.', false, 'GeneratedzKUq423YphwPvRPbOji');
INSERT INTO public."user" VALUES ('U5c827d7de115', '2023-12-20 08:28:59.33022+00', '2024-07-09 12:54:29.214478+00', '', '', false, 'tpIPuCyXDPTTrEMgHsE2UzOf9NkibO-tgOFdh8-JIKs');
INSERT INTO public."user" VALUES ('U861750348e9f', '2023-10-08 20:27:55.002482+00', '2024-07-09 12:54:29.214478+00', 'vadim 3', '', false, 'LPKlUEQArmt86glcp-I1fBXoWKAZo_qF8nB_LodKlE4');
INSERT INTO public."user" VALUES ('Uc4ebbce44401', '2023-12-21 17:22:50.669432+00', '2024-07-09 12:54:29.214478+00', 'Vadim 1', '', false, 'E0WyJCktP-_cuq0BPMLeZI0A-xamDpS3v_pMF0eXBFs');
INSERT INTO public."user" VALUES ('Ue55b928fa8dd', '2023-12-21 22:00:09.931491+00', '2024-07-09 12:54:29.214478+00', 'Vadim 2', '', false, 'pK7mg_PeZK9pJlYYgim5JFLSzyclEx6qpbECK7YWdd4');
INSERT INTO public."user" VALUES ('Ub22f9ca70b59', '2023-12-22 14:38:26.283632+00', '2024-07-09 12:54:29.214478+00', '', '', false, 'Y1yuBIzBFg6RicWrPwYke504QjZrjeZ9wbBx9622cQ8');
INSERT INTO public."user" VALUES ('Ud7186ef65120', '2023-12-22 14:38:31.376903+00', '2024-07-09 12:54:29.214478+00', '', '', false, 'qUSAG9iAbK_xy_e6zgbS_d0DYoBGiR8qAgZYEXevy9Y');
INSERT INTO public."user" VALUES ('U1eafbaaf9536', '2023-12-22 14:39:06.028441+00', '2024-07-09 12:54:29.214478+00', '', '', false, 'Ltrbi0MPZvVVVhHQ0n1N7x6ScYxLxYh6sgREuLhrwwU');
INSERT INTO public."user" VALUES ('U918f8950c4e5', '2023-12-27 13:09:56.657057+00', '2024-07-09 12:54:29.214478+00', '', '', false, 'dvZkqf3OdgI0NOYPTMeYqg5vHhJ4DRAprw3YYcf4URw');
INSERT INTO public."user" VALUES ('U7cdd7999301e', '2023-12-27 13:10:07.822416+00', '2024-07-09 12:54:29.214478+00', '', '', false, 'DX9lCrV0cJbJOX3RsN3xlQIwRBp9n6hdTupB4rW3eXE');
INSERT INTO public."user" VALUES ('U430a8328643b', '2023-12-27 13:10:52.158982+00', '2024-07-09 12:54:29.214478+00', '', '', false, 'BdMe2QknB22kqli2Q-FH6bHtjduxW8y9laCnyv8fwDk');
INSERT INTO public."user" VALUES ('U99deecf5a281', '2023-12-27 13:12:41.123366+00', '2024-07-09 12:54:29.214478+00', '', '', false, 'C24ykO5Kh5O4StTmt9IQLA_dj-MZPmfDyyNykDyreUY');
INSERT INTO public."user" VALUES ('U707f9ed34910', '2023-12-27 13:13:13.189077+00', '2024-07-09 12:54:29.214478+00', '', '', false, 'sf8us8YbGczNnUkYIc-3e84pSKui0my6j26Dj1e1BBs');
INSERT INTO public."user" VALUES ('U7399d6656581', '2023-12-27 13:13:38.981422+00', '2024-07-09 12:54:29.214478+00', '', '', false, 'p1kIRMuEMhxfkN0AaBTOVD_NwdFBCvP1b2aYFO-E7Rg');
INSERT INTO public."user" VALUES ('Uc4f728b0d87f', '2023-12-27 13:13:54.950128+00', '2024-07-09 12:54:29.214478+00', '', '', false, 'XbCBhPswHEguurW9Nxtr9zv9MCFevVMUeBsHxXr7kNo');
INSERT INTO public."user" VALUES ('Ubd48a3c8df1e', '2023-12-22 14:39:10.739686+00', '2024-07-09 12:54:29.214478+00', '', '', false, '4JnBfMaOzHii3l_6J-Yy-euhNzDKMp8_5TS0PU53DLc');
INSERT INTO public."user" VALUES ('U431131a166be', '2023-12-22 14:43:12.578091+00', '2024-07-09 12:54:29.214478+00', '', '', false, 'ydYVEWv4yeaVnUPm2z5F3TgYmcHK7vHIA1MY0QAygxw');
INSERT INTO public."user" VALUES ('Uc8bb404462a4', '2023-12-22 14:43:17.359079+00', '2024-07-09 12:54:29.214478+00', '', '', false, 'PSZoDqe1mBJzGwuBkQqHURXjSmlQoC8lb3i4f1Y5zQI');
INSERT INTO public."user" VALUES ('U48dcd166b0bd', '2023-12-22 14:43:20.672166+00', '2024-07-09 12:54:29.214478+00', '', '', false, 'pE03cGMohvz9hhpxdDm1C64tr37Ezz0M4MjnL_trNU0');
INSERT INTO public."user" VALUES ('Ucbd309d6fcc0', '2023-12-22 14:43:24.651393+00', '2024-07-09 12:54:29.214478+00', '', '', false, 'WCx8As4-EjTOigRdnkQsxEcbptBzIfHBrZzaeIK2kKU');
INSERT INTO public."user" VALUES ('U3f840973f9b5', '2023-12-22 15:44:12.509537+00', '2024-07-09 12:54:29.214478+00', '', '', false, 'lLrBKHi0ZP6Hva9EVost5Gi-JvRvb9dwV_cInD0kiEo');
INSERT INTO public."user" VALUES ('Ub0205d5d96d0', '2023-12-22 15:44:28.262419+00', '2024-07-09 12:54:29.214478+00', '', '', false, '4fPSLxojfFEuZKNToF8OPKiR3KeTRtALIStGCbkDHag');
INSERT INTO public."user" VALUES ('U7c88b933c58d', '2023-12-22 15:44:52.051527+00', '2024-07-09 12:54:29.214478+00', '', '', false, '1ZrjMjCaMyn3qW7DYaUyl8ymMFUT3Z-6R69swlrqVgw');
INSERT INTO public."user" VALUES ('Ua50dd76e5a75', '2023-12-22 15:44:57.410503+00', '2024-07-09 12:54:29.214478+00', '', '', false, 'OohXoNpCH4h2M3r0TywcNVD9rLpwvAbp8zC_-ill39E');
INSERT INTO public."user" VALUES ('Uc3a349f521e1', '2023-12-22 15:44:58.497961+00', '2024-07-09 12:54:29.214478+00', '', '', false, '9QWyLYDkxVb1j6oseVcJ8_dtJb_YCIcP3xCSh_LpUh8');
INSERT INTO public."user" VALUES ('U8ec514590d15', '2023-12-22 15:44:59.379529+00', '2024-07-09 12:54:29.214478+00', '', '', false, 'jZUcDOTy2Lr_t8euMtqjl7jdIqfy-pSQ95TJ7gocv7A');
INSERT INTO public."user" VALUES ('Ud2c791d9e879', '2023-12-22 15:45:02.24659+00', '2024-07-09 12:54:29.214478+00', '', '', false, 'cZ4XjiXaLE4Vib7EcFtllXBTY4nC_FqsNnL-sAv7v70');
INSERT INTO public."user" VALUES ('Uceaf0448e060', '2023-12-22 15:45:07.217731+00', '2024-07-09 12:54:29.214478+00', '', '', false, 'jutfVcIhKOkO-w3xkGZGsVXHMnUEwWgY2SlXotSlCXk');
INSERT INTO public."user" VALUES ('U732b06e17fc6', '2023-12-22 15:45:08.516769+00', '2024-07-09 12:54:29.214478+00', '', '', false, 'HWrNY9Op98TGh3hdAtvYoyoer6yuCZeDUfJlNNHuntU');
INSERT INTO public."user" VALUES ('U88137a4bf483', '2023-12-22 15:45:12.762352+00', '2024-07-09 12:54:29.214478+00', '', '', false, 'CLuMHXbQ-lCTLGmewdHy6vLQIuvHSQxZBCRdkMLAqlo');
INSERT INTO public."user" VALUES ('U0a5d1c56f5a1', '2023-12-22 15:45:13.710746+00', '2024-07-09 12:54:29.214478+00', '', '', false, 'Hj2LNZQJ3naw5fAZNufn4ASC1M52s64WTTQoUp9Leh4');
INSERT INTO public."user" VALUES ('U290a1ab9d54a', '2023-12-22 15:45:39.492895+00', '2024-07-09 12:54:29.214478+00', '', '', false, 'J7trprMV_AvXYgWLFNHxn50ynPvH2N678FYE9wOEGqc');
INSERT INTO public."user" VALUES ('Ub901d5e0edca', '2023-12-22 15:46:04.644174+00', '2024-07-09 12:54:29.214478+00', '', '', false, '1iGnBBFhEVaKBoh2a7RLSXGiKTCtpl-g2Ppz5RTflSs');
INSERT INTO public."user" VALUES ('Ucbca544d500f', '2023-12-22 15:46:08.719943+00', '2024-07-09 12:54:29.214478+00', '', '', false, 'gz9x8qjo17C9wqHFNJjpRLsjKauNNc_xGCB1P2e94c4');
INSERT INTO public."user" VALUES ('Uf5a84bada7fb', '2023-12-22 15:46:23.239054+00', '2024-07-09 12:54:29.214478+00', '', '', false, 'G8o0a8pBtLbkSSztCM3Jr4NeVLjZBwyIPWdJFV-b_zc');
INSERT INTO public."user" VALUES ('U0667457dabfe', '2023-12-22 15:47:34.123911+00', '2024-07-09 12:54:29.214478+00', '', '', false, 'JVVfEQs55UoxBi99uCoEPI35kcSOqB-yDyd2SJ85FMg');
INSERT INTO public."user" VALUES ('Ua34e02cf30a6', '2023-12-22 15:48:24.230052+00', '2024-07-09 12:54:29.214478+00', '', '', false, '9BYm1wzNTY8UfsoHKaGDQUBwGrB-8fEqhJfPYizN3pQ');
INSERT INTO public."user" VALUES ('U161742354fef', '2023-12-22 15:48:34.363005+00', '2024-07-09 12:54:29.214478+00', '', '', false, 'bT5uoyy7gl9rC5WcA1isB8ofj12ERjzErMXMO0ewQNY');
INSERT INTO public."user" VALUES ('Uc76658319bfe', '2023-12-22 15:49:53.721146+00', '2024-07-09 12:54:29.214478+00', '', '', false, 'A7zN-04gLZ-MJV0_DCTp9A0AU8px_qLHkJrGTvfR_Mc');
INSERT INTO public."user" VALUES ('Ue4f003e63773', '2023-12-22 15:50:20.290483+00', '2024-07-09 12:54:29.214478+00', '', '', false, 'FnTShjgFp5jKcpBeKMZVqKEWfVF0CTF8xBL7r5RoRUs');
INSERT INTO public."user" VALUES ('U06a4bdf76bf7', '2023-12-22 15:53:52.524589+00', '2024-07-09 12:54:29.214478+00', '', '', false, 'q2WyBG3GRwtlIsBHmYrKLSgOX9uxI62pykjDTPV9w6U');
INSERT INTO public."user" VALUES ('U611323f9392c', '2023-12-22 15:53:56.300066+00', '2024-07-09 12:54:29.214478+00', '', '', false, 'O4XqGf4NVp2cLLll_1jPyXWCp_nCLn9KXIitZfbCH3s');
INSERT INTO public."user" VALUES ('Uc5d62a177997', '2023-12-22 17:05:37.497868+00', '2024-07-09 12:54:29.214478+00', '', '', false, 'DQQJJaFCPeVNrkUPrs8GYg3p8NvdZErEyttTsmMpetA');
INSERT INTO public."user" VALUES ('Ue6cc7bfa0efd', '2023-12-22 18:59:30.657785+00', '2024-07-09 12:54:29.214478+00', 'vad 3', '', false, 'BmoXvigTeMmN36mdr1ZWxpSa7Zf9q9CllV7DBFqChcM');
INSERT INTO public."user" VALUES ('Uebe87839ab3e', '2023-12-23 01:05:38.486075+00', '2024-07-09 12:54:29.214478+00', '', '', false, 'zHTJ9RJTZvb5z7BYiX-ep_158cxzepos5bbWwN2kAMM');
INSERT INTO public."user" VALUES ('U8f0839032839', '2023-12-23 02:16:33.13365+00', '2024-07-09 12:54:29.214478+00', '', '', false, 'UTNGHwpv2u1gdFZTpLNl6JxqAmp1JBZqLqyPFGqcv50');
INSERT INTO public."user" VALUES ('U867a75db12ae', '2023-12-23 12:21:29.771889+00', '2024-07-09 12:54:29.214478+00', '', '', false, 'XEd57PSUXg3Hu_OBwq2kkYlTZkE51mrPcY4Cu-PXUUM');
INSERT INTO public."user" VALUES ('Ud982a6dee46f', '2023-12-23 12:21:34.431101+00', '2024-07-09 12:54:29.214478+00', '', '', false, 'kzts5jjfxWrLJSCiE5jjJL5_pmjWgVsBWvw87Ab9tZY');
INSERT INTO public."user" VALUES ('Uc3db248a6e7f', '2023-12-23 21:44:18.666403+00', '2024-07-09 12:54:29.214478+00', '', '', false, 'EnB6dnZR7-_86DD2fETDhdS1Tf-CeesS5sl7ENsDTW8');
INSERT INTO public."user" VALUES ('U03eaee0e3052', '2023-12-23 21:44:20.234761+00', '2024-07-09 12:54:29.214478+00', '', '', false, 'L6OD6SJ7gWg4o_ApXJ8D4fmt4OZqlfUsEKC8NopEJtE');
INSERT INTO public."user" VALUES ('Ue2570414501b', '2023-12-23 21:44:22.604865+00', '2024-07-09 12:54:29.214478+00', '', '', false, 'aFACc-u0X9BT0VTVtI9PseX2S4sLg9_06Ze38eF0Jgw');
INSERT INTO public."user" VALUES ('U9c1051c9bb99', '2023-12-23 21:44:22.972331+00', '2024-07-09 12:54:29.214478+00', '', '', false, 'oGH--OXKIlK7RjbjQPS4bag7hmJj99Gi3Ep-6cR9B9s');
INSERT INTO public."user" VALUES ('Ucb37b247402a', '2023-12-23 21:44:23.237134+00', '2024-07-09 12:54:29.214478+00', '', '', false, '9tJrdHYipsZQUreSiJ2cXFOIZ8EQgKTogxcHHMv8-I4');
INSERT INTO public."user" VALUES ('Ufec0de2f341d', '2023-12-23 21:44:25.631633+00', '2024-07-09 12:54:29.214478+00', '', '', false, 'THNaWXQP0XEbxLOlwqO4ywNXzAZwBQWjkbEl1HFW3DI');
INSERT INTO public."user" VALUES ('Uefe16d246c36', '2023-12-23 21:44:26.175421+00', '2024-07-09 12:54:29.214478+00', '', '', false, 'Rxts-C90lV3cC2HsDc1B3aZtqTa7_ttNGJ4tCGNzZpg');
INSERT INTO public."user" VALUES ('U037b51a34f3c', '2023-12-23 21:44:30.03492+00', '2024-07-09 12:54:29.214478+00', '', '', false, 'gWbAobu5BgG-Y-n5QgEQ3-udM53GHlA23hrr04wFs0M');
INSERT INTO public."user" VALUES ('U2a62e985bcd5', '2023-12-23 21:44:36.936259+00', '2024-07-09 12:54:29.214478+00', '', '', false, 'M2yG2FocGOyWIRm0pI_InqZNxreYvqCVd3EUaa3Smzs');
INSERT INTO public."user" VALUES ('U53eb1f0bdcd2', '2023-12-23 21:44:41.315475+00', '2024-07-09 12:54:29.214478+00', '', '', false, '1-LFySp3zdYG9i-cCvwjjfhzzMvTC97M8Ua8_ZVhhqc');
INSERT INTO public."user" VALUES ('Ue94281e36fe8', '2023-12-23 21:45:00.096935+00', '2024-07-09 12:54:29.214478+00', '', '', false, 'xoo91BPIPJ8tZTbNtCa2ekHGqe2F7jsehwVFbApXaxg');
INSERT INTO public."user" VALUES ('Uc2bfe7e7308d', '2023-12-23 21:45:38.478114+00', '2024-07-09 12:54:29.214478+00', '', '', false, '2KuZ2M783-C1nh3VmPIrFsGGO2XAaDOyh6qb4FeaCaI');
INSERT INTO public."user" VALUES ('U4e7d43caba8f', '2023-12-23 21:47:52.599428+00', '2024-07-09 12:54:29.214478+00', '', '', false, 'qOgIXruji7kvzlrMbrzBfSd3a_obmw70Lvit-a-41zQ');
INSERT INTO public."user" VALUES ('Uee0fbe261b7f', '2023-12-23 21:48:38.896867+00', '2024-07-09 12:54:29.214478+00', '', '', false, 'V7FJ8sEHNbD2-lh_QWUAdT8ttXythacR9_zes2WxUwM');
INSERT INTO public."user" VALUES ('U7f5fca21e1e5', '2023-12-23 21:49:08.767623+00', '2024-07-09 12:54:29.214478+00', '', '', false, 'ny5VYwjD4kK0pAq7ZbJtlwfD2BHIvydkU2LZ7KJkkEE');
INSERT INTO public."user" VALUES ('Udf6d8127c2c6', '2023-12-23 21:49:35.659008+00', '2024-07-09 12:54:29.214478+00', '', '', false, 'EC0lHKmv8mJOBCenrZzYtzEQVxbr9b4PXOUQUvpLG-w');
INSERT INTO public."user" VALUES ('U35108003593e', '2023-12-23 21:49:39.140676+00', '2024-07-09 12:54:29.214478+00', '', '', false, 'U2qMnj3NhBBOZffLKA1CDClp4P6gxmM1u4aLqMR3Tw4');
INSERT INTO public."user" VALUES ('U5f7ff9cb9304', '2023-12-23 21:51:24.753715+00', '2024-07-09 12:54:29.214478+00', '', '', false, 'q5kzQsHUc_u4oslSAMk6FiC7HWFgSFoGU_ML8yCtgvk');
INSERT INTO public."user" VALUES ('Uf5ee43a1b729', '2023-12-23 21:51:28.523908+00', '2024-07-09 12:54:29.214478+00', '', '', false, 'nfUwWr7wQj_v6upmEgTbLirsxUaIajXQZR69dx18P-A');
INSERT INTO public."user" VALUES ('Ub1a7f706910f', '2023-12-23 21:51:33.59887+00', '2024-07-09 12:54:29.214478+00', '', '', false, '40OuVG2jktKj4QAwE56KPvfueB_AQUmxAxsw-6VE5Nw');
INSERT INTO public."user" VALUES ('Uab16119974a0', '2023-12-23 21:51:37.317858+00', '2024-07-09 12:54:29.214478+00', '', '', false, 'LbGvrF-b3lYVwx7jXDc-CNaPx6Ho0_NdeLVghyPvYFc');
INSERT INTO public."user" VALUES ('Ua6dfa92ad74d', '2023-12-23 21:51:44.722244+00', '2024-07-09 12:54:29.214478+00', '', '', false, 'yua9h0JJDC-ecE8nIqpbBBZpf0Q1dgC4YE39eb_8MaQ');
INSERT INTO public."user" VALUES ('U57b6f30fc663', '2023-12-23 21:51:50.619915+00', '2024-07-09 12:54:29.214478+00', '', '', false, '_BR_6PBWN6fpPqaOnzRB3GgyYmS6V5dBkO5lNiZuE5Y');
INSERT INTO public."user" VALUES ('U4a82930ca419', '2024-01-09 19:50:20.921281+00', '2024-07-09 12:54:29.214478+00', '', '', false, 'rq_B3ndNMo6uizl_RntfZNh8ZDD3bPJG5pqyH3vxO8w');
INSERT INTO public."user" VALUES ('Uef7fbf45ef11', '2023-09-26 10:54:45.133958+00', '2024-07-09 12:54:29.214478+00', 'Tommie Kreiger', 'Etiam erat velit scelerisque in.
Vitae proin sagittis nisl rhoncus mattis.
Viverra justo nec ultrices dui sapien eget mi.', false, 'Generated4FrR928rs2rou1njfFs');
INSERT INTO public."user" VALUES ('U9a89e0679dec', '2023-09-26 10:54:45.133958+00', '2024-07-09 12:54:29.214478+00', 'Ms. Mabelle Weimann', '', false, 'Generatedy8IIAAW3AaUEUosqCOb');
INSERT INTO public."user" VALUES ('Udb60bbb285ca', '2023-10-09 04:59:04.831099+00', '2024-07-09 12:54:29.214478+00', 'sergeyN3', '', false, '_8dSFhB5NapmxRWyp6Zw6tRIeMHTKobDuZDWJ1k0U0w');
INSERT INTO public."user" VALUES ('Ue7a29d5409f2', '2023-09-26 10:54:45.133958+00', '2024-07-09 12:54:29.214478+00', 'Jabari Carroll', 'Feugiat nisl pretium fusce id velit ut.
Amet purus gravida quis blandit turpis cursus in hac habitasse.
Sit amet mattis vulputate enim.
Lectus quam id leo in.', false, 'Generatedur1u1anOMs4zQoln9Ax');
INSERT INTO public."user" VALUES ('U9e42f6dab85a', '2023-09-26 10:54:45.133958+00', '2024-07-09 12:54:29.214478+00', 'Thad Baumbach', '', false, 'GenerateduV4GVBOirf3mMyT5bRc');
INSERT INTO public."user" VALUES ('U389f9f24b31c', '2023-09-26 10:54:45.133958+00', '2024-07-09 12:54:29.214478+00', 'Alize Metz', '', false, 'GeneratediALZTbulhcfDpdH4brw');
INSERT INTO public."user" VALUES ('U9a2c85753a6d', '2023-09-26 10:54:45.133958+00', '2024-07-09 12:54:29.214478+00', 'Ewald Turner DDS', 'Metus vulputate eu scelerisque felis imperdiet.
Nunc mattis enim ut tellus.', false, 'Generated09t5OEpdSJ6QoIDMBHV');
INSERT INTO public."user" VALUES ('Uc3c31b8a022f', '2023-09-26 10:56:05.86312+00', '2024-07-09 12:54:29.214478+00', 'Candice McDermott', 'Tincidunt dui ut ornare lectus.
Et magnis dis parturient montes.', false, 'GenerateddNck8AYvKjiuKPIgixu');
INSERT INTO public."user" VALUES ('Udece0afd9a8b', '2023-09-26 10:56:05.86312+00', '2024-07-09 12:54:29.214478+00', 'Ryleigh Schmitt', '', false, 'GeneratedL0dkMXEklwPFmghD5UH');
INSERT INTO public."user" VALUES ('U26aca0e369c7', '2023-09-26 10:56:05.86312+00', '2024-07-09 12:54:29.214478+00', 'Mrs. Aditya Collier', 'Morbi non arcu risus quis varius quam quisque id.
Id velit ut tortor pretium.
Nulla aliquet enim tortor at auctor.', false, 'GeneratedYmbHbzxjJmIK4NpH6FQ');
INSERT INTO public."user" VALUES ('Uf5096f6ab14e', '2023-09-26 10:56:05.86312+00', '2024-07-09 12:54:29.214478+00', 'Jeanie Hansen', '', false, 'GeneratedvqvPXzQIYd6XIQo5ymY');
INSERT INTO public."user" VALUES ('Ubebfe0c8fc29', '2023-11-25 23:53:38.629389+00', '2024-07-09 12:54:29.214478+00', '', '', false, '_WbDdfes-nNME2_JxKHQ9zWDPci3D42MeG_LoSS22U4');
INSERT INTO public."user" VALUES ('U798f0a5b78f0', '2023-11-26 00:21:16.604861+00', '2024-07-09 12:54:29.214478+00', '', '', false, 'grxQsONLmJoPU_zD8EGWFOAVvf7qEMZd6oaE7EsJ9FA');
INSERT INTO public."user" VALUES ('Uf2b0a6b1d423', '2023-09-26 10:56:05.86312+00', '2024-07-09 12:54:29.214478+00', 'Noemi Reichert', 'Eget duis at tellus at urna condimentum mattis.
Ridiculus mus mauris vitae ultricies leo integer malesuada.
Nec dui nunc mattis enim ut.
Malesuada fames ac turpis egestas.', false, 'GeneratedLe1hQdneMTcuHNJ2ONM');
INSERT INTO public."user" VALUES ('Uaa4e2be7a87a', '2023-09-26 10:56:05.86312+00', '2024-07-09 12:54:29.214478+00', 'Nicholas Schuppe', 'Nibh venenatis cras sed felis eget.
Odio tempor orci dapibus ultrices.
At in tellus integer feugiat scelerisque varius morbi.
Faucibus ornare suspendisse sed nisi.', false, 'GeneratedHWZn6yzgN50Y9741iy2');
INSERT INTO public."user" VALUES ('U0c17798eaab4', '2023-09-26 10:56:05.86312+00', '2024-07-09 12:54:29.214478+00', 'Norene Gutkowski', 'Volutpat consequat mauris nunc congue nisi.
Amet commodo nulla facilisi nullam vehicula.
Proin fermentum leo vel orci porta.', false, 'GeneratedE2VaSXb1HihZ6qUtg6N');
INSERT INTO public."user" VALUES ('U1c285703fc63', '2023-09-26 10:56:05.86312+00', '2024-07-09 12:54:29.214478+00', 'Patricia Dibbert', '', false, 'GeneratedcO7weLOHQs6sQMIOjKA');
INSERT INTO public."user" VALUES ('Uc1158424318a', '2023-09-26 10:56:05.86312+00', '2024-07-09 12:54:29.214478+00', 'Zula Sauer', '', false, 'Generated1T93RAyM9baoVVTo1ck');
INSERT INTO public."user" VALUES ('U80e22da6d8c4', '2023-09-26 10:56:05.86312+00', '2024-07-09 12:54:29.214478+00', 'Rossie Schmeler', 'Molestie ac feugiat sed lectus.', false, 'GeneratedrpOU62g5kX02S52WDI1');
INSERT INTO public."user" VALUES ('U0d47e4861ef0', '2023-10-03 12:35:11.999169+00', '2024-07-09 12:54:29.214478+00', 'Donald Duck', 'Watching you!', false, 'U2q1YNCwpkvyUWucu64JdVMUGAwODc9vfBLCtlvNzec');
INSERT INTO public."user" VALUES ('U6d2f25cc4264', '2023-10-03 12:51:28.212214+00', '2024-07-09 12:54:29.214478+00', 'Nemo the Captain (old)', '', false, 'GcfxAgRDZui6CFe4CHjs5nSRm1VRJYa9QYmEnD8bFAs');
INSERT INTO public."user" VALUES ('Uf31403bd4e20', '2023-11-16 13:18:28.086868+00', '2024-07-09 12:54:29.214478+00', '', '', false, 'gRCxH7Q71mSbkVCR610SVvYOjH6Yy9LUj4sSPN-8cFw');
INSERT INTO public."user" VALUES ('U09cf1f359454', '2023-11-07 04:28:18.13322+00', '2024-07-09 12:54:29.214478+00', 'Nemo the Captain', 'Усипуси', false, 'BNdFwFVJw4cQEvlpndXHz86FcSzC8eQpYpvAxV9IkbY');
INSERT INTO public."user" VALUES ('Uc44834086c03', '2023-11-17 11:21:30.404027+00', '2024-07-09 12:54:29.214478+00', '', '', false, 'd385BVJwRiqxJ9cNha-Pu8dCSz5gqUoDKIhm7JEgQU0');
INSERT INTO public."user" VALUES ('U01814d1ec9ff', '2023-10-04 13:04:08.922876+00', '2024-07-09 12:54:29.214478+00', 'Vadim', 'some random Dutch junkie, lol', false, 'JDJ1X_aZb7mcBgkTJWZqWUXXXuxgxjZg391OBiYqwKY');
INSERT INTO public."user" VALUES ('U99a0f1f7e6ee', '2023-10-06 15:16:59.415273+00', '2024-07-09 12:54:29.214478+00', 'СеР', 'дескрипл ', false, '6NIHN2umftKBwLPNZSs9RnySHKpzgECqmIXCXEpIpVM');
INSERT INTO public."user" VALUES ('U8a78048d60f7', '2023-10-04 16:04:21.374824+00', '2024-07-09 12:54:29.214478+00', 'Немо', 'Моя телега не едет.
Мой Скайп умер для меня.', false, 'bmrEIA_mzIyrihQZBLi6xuJoBNq26JhmOljS0roB2fw');
INSERT INTO public."user" VALUES ('U1bcba4fd7175', '2023-11-08 10:00:04.149016+00', '2024-07-09 12:54:29.214478+00', 'vad9 (185)', '', false, 'zHH_I3UgFYR6bbgEK2_TlDGxcrsR0Cifblf5sM0mFTE');
INSERT INTO public."user" VALUES ('U499f24158a40', '2023-10-05 13:16:09.723161+00', '2024-07-09 12:54:29.214478+00', 'Dmitrii', 'Lorem ipsum', false, 'J9yFvPuKS8BRfp1vXO-eIxY-4jsaS7poM2ZA5VBYw3o');
INSERT INTO public."user" VALUES ('U21769235b28d', '2023-10-05 13:40:27.404586+00', '2024-07-09 12:54:29.214478+00', 'Антон', '', false, 'paEr80FdYqrnAjYjUjhmH0VSD0Iid7CARPiTZWUVGCk');
INSERT INTO public."user" VALUES ('Uab766aeb8fd2', '2023-11-19 12:22:56.192016+00', '2024-07-09 12:54:29.214478+00', '', '', false, 'KwsMYK0vpGWPgXyt5atcLHXX2qBvzlED2XH3AZvpZYo');
INSERT INTO public."user" VALUES ('U02be55e5fdb2', '2023-11-19 12:23:00.076091+00', '2024-07-09 12:54:29.214478+00', '', '', false, 'xKd0MwPkVnjBzeq3bzY5JzMwe4TAMrr9LG_a_nwxanQ');
INSERT INTO public."user" VALUES ('U11722d2113bf', '2023-11-20 18:32:00.1413+00', '2024-07-09 12:54:29.214478+00', '', '', false, '590OhW-icyQdjcquNMGrUtyh5tIFPdUTjYsf_9bKkVc');
INSERT INTO public."user" VALUES ('Ufa76b4bb3c95', '2023-11-21 21:47:50.721639+00', '2024-07-09 12:54:29.214478+00', '', '', false, '1kk_LUCvooVrKMosl5dFSOxYdFJPlbEE5Twmv7DgYI0');
INSERT INTO public."user" VALUES ('U1df3e39ebe59', '2023-11-21 21:47:54.228104+00', '2024-07-09 12:54:29.214478+00', '', '', false, 'ZsypxfvXSEsAuYIixZbjFFx14IAvSTzWgjJjSOyXMnU');
INSERT INTO public."user" VALUES ('Uf59dcd0bc354', '2023-11-21 21:47:54.946865+00', '2024-07-09 12:54:29.214478+00', '', '', false, 'zS6M8JyiAGKV8Vg7vglLbK859kaCA48r3rZpt3SOjbs');
INSERT INTO public."user" VALUES ('Uc3a2aab8a776', '2023-11-21 21:47:58.630869+00', '2024-07-09 12:54:29.214478+00', '', '', false, 'cVD_G8SGo6cQqtEvJVk1jzTHl10VBn0vJIEQKGW9RRI');
INSERT INTO public."user" VALUES ('U606a687682ec', '2023-11-21 21:49:35.418814+00', '2024-07-09 12:54:29.214478+00', '', '', false, '7jhM7z4nX1kIB99mZmMyOc1yKruEcITW5AsUcnbHu3U');
INSERT INTO public."user" VALUES ('Udc7c82928598', '2023-11-21 21:49:39.080934+00', '2024-07-09 12:54:29.214478+00', '', '', false, 'wem_nGOj4Sn2eO6_irD3WqlhUMnhquei5FXLUu8TjEM');
INSERT INTO public."user" VALUES ('U1d5b8c2a3400', '2023-11-21 21:50:53.67823+00', '2024-07-09 12:54:29.214478+00', '', '', false, 'wV7uwad_N1N-EqVT0KwdaOSp5XMC8TpLwKRxr6BfU8o');
INSERT INTO public."user" VALUES ('U005d51b8771c', '2023-11-21 21:50:58.602992+00', '2024-07-09 12:54:29.214478+00', '', '', false, 'WYVVOLTlYUjCW5nyaOY47a58kzIsqS846EF2kVyAveA');
INSERT INTO public."user" VALUES ('Uccc3c7395af6', '2023-11-25 18:37:42.895856+00', '2024-07-09 12:54:29.214478+00', '', '', false, 'QTLHZRBYRJdmAbC9T7ZYdzACYQf1YMuTcBAzvyF1QsQ');
INSERT INTO public."user" VALUES ('U34252014c05b', '2023-10-07 10:50:24.116209+00', '2024-07-09 12:54:29.214478+00', 'sergei', 'дескрип
', false, 'vFad-oXk9UkdJDe1axVPhxTgpSbah1dyvhanKxdw18g');
INSERT INTO public."user" VALUES ('U495c3bb411e1', '2023-11-25 18:37:46.730291+00', '2024-07-09 12:54:29.214478+00', '', '', false, 'cb56MGceYzcDUow5RabBgmFKhhTHMUW_8JB6pH9YQ_g');
INSERT INTO public."user" VALUES ('U1e6a314ef612', '2023-11-25 18:38:35.594442+00', '2024-07-09 12:54:29.214478+00', '', '', false, 'g4EevPu6Uf7rVfqKByQJnI6iTjMsL1dp9SxiDs79TwY');
INSERT INTO public."user" VALUES ('U8842ed397bb7', '2023-11-25 18:38:41.28417+00', '2024-07-09 12:54:29.214478+00', '', '', false, '-liqbcvtG-Ra6D9bsICpWu7FgdqZ0WqfHXZKFgOfDFI');
INSERT INTO public."user" VALUES ('Ud7002ae5a86c', '2023-10-08 12:53:06.899275+00', '2024-07-09 12:54:29.214478+00', 'sergeyN1', '', false, 'BBH8qRe8Pu_IJotLH9m12gy4jpWXE_uX46_f55b-ygY');
INSERT INTO public."user" VALUES ('Ucfb9f0586d9e', '2023-11-25 18:39:24.919787+00', '2024-07-09 12:54:29.214478+00', '', '', false, 'dR76x1VHLxjjavz0NtKpn8ArYiPGyYirbaNn2Kdwdo0');
INSERT INTO public."user" VALUES ('Ubd93205079e9', '2023-11-25 18:39:29.664375+00', '2024-07-09 12:54:29.214478+00', '', '', false, 'pofUNN61SEFa9F7QwBRLpnewrw7EXOqAPxw1dAwiKPU');
INSERT INTO public."user" VALUES ('U1afee48387d4', '2023-11-25 18:43:31.150274+00', '2024-07-09 12:54:29.214478+00', '', '', false, '4VlRn_MSaiQ4An-uJXDqvz5FABPdAYGPHSkXef2YHAU');
INSERT INTO public."user" VALUES ('Uaaf5341090c6', '2023-11-25 18:43:34.835872+00', '2024-07-09 12:54:29.214478+00', '', '', false, 'iKKYHJuAo2pO8tKyUSDC_YlHrHFisz2lunbmakpE5LA');
INSERT INTO public."user" VALUES ('Uda5b03b660d7', '2023-11-25 21:41:28.975403+00', '2024-07-09 12:54:29.214478+00', '', '', false, '281-FRtfoj3Pci2TSldtM_Nsjg9qkI2dC6cbGlM7ekY');
INSERT INTO public."user" VALUES ('Ueb139752b907', '2023-11-25 21:41:27.32766+00', '2024-07-09 12:54:29.214478+00', 'Nemo', '', false, 'f7yacQ-GeEtsD-EI-XphrjYe8uh2t9_9IOpGzlORiBo');
INSERT INTO public."user" VALUES ('Ua9d9d5da3948', '2023-11-25 23:49:33.858574+00', '2024-07-09 12:54:29.214478+00', '', '', false, 'IlRtrbzThQk_ePvwL_2UzqkvmIshAbcFGk6cBC9xX34');
INSERT INTO public."user" VALUES ('U704bd6ecde75', '2023-11-25 23:50:19.752987+00', '2024-07-09 12:54:29.214478+00', '', '', false, 'Ny6koIIb2ChoJjObGnAgD-3K3tG0moKjlJ7Ny5EphIA');
INSERT INTO public."user" VALUES ('U675d1026fe95', '2023-11-25 23:50:35.175233+00', '2024-07-09 12:54:29.214478+00', '', '', false, 'oXKROr1fKldjFHqifiP7bSQ7wNm0lNNFk36FwG2AACI');
INSERT INTO public."user" VALUES ('U362d375c067c', '2023-11-25 23:50:38.855541+00', '2024-07-09 12:54:29.214478+00', '', '', false, 'KulcW6Tk0WI7S9j3_Qg4z71UNP4Bndag0ilBB-xFg0A');
INSERT INTO public."user" VALUES ('U65bb6831c537', '2023-11-25 23:50:55.989666+00', '2024-07-09 12:54:29.214478+00', '', '', false, 'TrgXbaw2xiRU2rDd3r6TkAmHwr5hQTkH9ywpcjwwra4');
INSERT INTO public."user" VALUES ('U6661263fb410', '2023-10-08 16:28:08.673513+00', '2024-07-09 12:54:29.214478+00', 'sergeyN2', '', false, 'LMhCYpW3Pq3KbdRwq2Yrc-EpxN0VfIaamfIsIO39Abw');
INSERT INTO public."user" VALUES ('U02fbd7c8df4c', '2023-10-08 16:47:47.37975+00', '2024-07-09 12:54:29.214478+00', 'vadim2', '', false, 'Y2QTf-k3bI8emOu-MYDpPJXwUYNVYEPjcJKTB4haUpY');
INSERT INTO public."user" VALUES ('U5f8c0e9c8cc4', '2023-11-15 10:35:56.334391+00', '2024-07-09 12:54:29.214478+00', '', '', false, 'Y-zYpdEaVfxvb4bBHD9im77KZfOW5VB42qTzf4w9tHs');
INSERT INTO public."user" VALUES ('Ubd9c1e76bb53', '2023-11-15 10:39:04.339003+00', '2024-07-09 12:54:29.214478+00', '', '', false, '-1p9h3ItK0kBiriyclSjsztgD4CigL_qt4WSwoyJdLI');
INSERT INTO public."user" VALUES ('Ud5b22ebf52f2', '2023-10-08 19:42:06.369526+00', '2024-07-09 12:54:29.214478+00', 'G50', '', false, 'O20sPB6xwX-amqEPJurQOOL3I84Sr49ZLRpPvqsYYTg');
INSERT INTO public."user" VALUES ('Ucbb6d026b66f', '2023-11-16 16:18:11.702241+00', '2024-07-09 12:54:29.214478+00', '', '', false, 'WGqBJ4KmB3UWjYpWunE9xO8IRrixB5eL3XdewNuA9io');
INSERT INTO public."user" VALUES ('U20d01ad4d96b', '2023-11-16 16:18:12.517053+00', '2024-07-09 12:54:29.214478+00', '', '', false, '2WmE2B2E1h-8IMZr3Rs52wTB-sAsVu9bpynyWFtB1FA');
INSERT INTO public."user" VALUES ('U3bf4a5894df1', '2023-11-17 13:53:30.418579+00', '2024-07-09 12:54:29.214478+00', '', '', false, 'Q1cTXK4xNx6addfYqLUQjaxbrSMQ0AQ1LS8BEDeD8DA');
INSERT INTO public."user" VALUES ('Ucdffb8ab5145', '2023-11-17 13:53:34.516056+00', '2024-07-09 12:54:29.214478+00', '', '', false, 'SM5H32b8lt-69PuRwbtvT_RrjDHied0hAupSudFpxms');
INSERT INTO public."user" VALUES ('U7bd2e29031a4', '2023-11-17 13:56:35.021507+00', '2024-07-09 12:54:29.214478+00', '', '', false, '4xAGxggOQzpfW4GoKRbZgYJJh0-prlRldmNflSY56lI');
INSERT INTO public."user" VALUES ('U41784ed376c3', '2023-10-09 06:15:17.311601+00', '2024-07-09 12:54:29.214478+00', 'sergeyN5', '', false, 'tzCvwmZ8XGQiG8_m96BBRvFM5YminzU2DC-K5rErC0I');
INSERT INTO public."user" VALUES ('U3de789cac826', '2023-11-17 13:56:39.082051+00', '2024-07-09 12:54:29.214478+00', '', '', false, 'ZfmEM8_pv7C5On7bCkPsXYuVNOo5wbVpGeJCed4yCHM');
INSERT INTO public."user" VALUES ('Uddd01c7863e9', '2023-11-19 12:27:35.208508+00', '2024-07-09 12:54:29.214478+00', '', '', false, '4CWeQhBPKG4tcGFZBZcMLLwHms7f-IkTwT59eGpamMw');
INSERT INTO public."user" VALUES ('U8aa2e2623fa5', '2023-11-19 12:27:36.83881+00', '2024-07-09 12:54:29.214478+00', '', '', false, 'mne9nSbtn9a7dJhAySzqu5wuWogPhPPvreOD-v-skIg');
INSERT INTO public."user" VALUES ('U7382ac807a4f', '2023-11-21 18:22:21.371334+00', '2024-07-09 12:54:29.214478+00', '', '', false, 'Fn3hHo1i0QCxVFTLUUaCapWRJfCTnhG-PfpoXO5UNmE');
INSERT INTO public."user" VALUES ('U895fd30e1e2a', '2023-11-22 13:05:38.061146+00', '2024-07-09 12:54:29.214478+00', '', '', false, 'OrtPT6dLl6YuTTkq-JfUtfCm9PWDGduY6y4yNK1WpP8');
INSERT INTO public."user" VALUES ('U3b78f50182c7', '2023-11-25 21:51:13.377412+00', '2024-07-09 12:54:29.214478+00', '', '', false, 'rNb-YhJy6r8BrKpYRXjVcKATqvmipHbrPGfls-qX03o');
INSERT INTO public."user" VALUES ('U5cfee124371b', '2023-11-25 23:51:45.547785+00', '2024-07-09 12:54:29.214478+00', '', '', false, 'vA-g-EXs0M8F-dwUcEPmn9D99WGZ8YeGZsEZG0nhkb4');
INSERT INTO public."user" VALUES ('U05e4396e2382', '2023-11-25 23:51:49.197945+00', '2024-07-09 12:54:29.214478+00', '', '', false, 'lr5RvLLxCCshgKQ4xGaO9lUBQnc-Q3E3VFsvO3_3JL4');
INSERT INTO public."user" VALUES ('Ua29a81d30ef9', '2023-11-25 23:52:03.42075+00', '2024-07-09 12:54:29.214478+00', '', '', false, '6UO4VTMcETD_LIvKlADyocVxeru3k2Mt_EN0vwRNfQk');
INSERT INTO public."user" VALUES ('Ue202d5b01f8d', '2023-11-25 23:52:09.117417+00', '2024-07-09 12:54:29.214478+00', '', '', false, '1DRF5-9GHcBFtnKYTwEwFCFEhR-P1KxOqbmLobAJfTU');
INSERT INTO public."user" VALUES ('Ufb826ea158e5', '2023-11-25 23:53:34.896883+00', '2024-07-09 12:54:29.214478+00', '', '', false, 'OVLCsn5TTv4bPPwy4vM2L9kwmxyUy3Nbi3ubgUqT4fk');
INSERT INTO public."user" VALUES ('U585dfead09c6', '2023-11-26 00:21:56.565529+00', '2024-07-09 12:54:29.214478+00', '', '', false, 'GlJiBRHlvC8TV3V8TdyjRHwV0O9ydc6iBnlo1Yrz8uI');
INSERT INTO public."user" VALUES ('U0ff6902d8945', '2023-12-03 03:44:44.414712+00', '2024-07-09 12:54:29.214478+00', '', '', false, 'LGuzuxn0e-j97353EZ6jipFwASqqUqwcpdP_gFGxrfM');
INSERT INTO public."user" VALUES ('Udf0362755172', '2023-12-03 03:44:47.483207+00', '2024-07-09 12:54:29.214478+00', '', '', false, 'ncGAx4IacHAbXM6EiAq_2uzwcU8XJID1TS03SQsbXxc');
INSERT INTO public."user" VALUES ('Ua1ca6a97ea28', '2023-12-07 09:20:46.098314+00', '2024-07-09 12:54:29.214478+00', '', '', false, 'P58mm0syEa2yDy10VVLcVuFr1FI7ZHHxB0e4k7cTcWk');
INSERT INTO public."user" VALUES ('U9605bd4d1218', '2023-10-09 19:13:07.827868+00', '2024-07-09 12:54:29.214478+00', 'vadim 5', '', false, 'Dad4saWxEjjePp8Qu_ymMlDAH4RbuTBh5ziazuvwyWg');
INSERT INTO public."user" VALUES ('Ub93799d9400e', '2023-10-09 09:04:35.432046+00', '2024-07-09 12:54:29.214478+00', 'vadim3', '', false, 'zaQRbTHe_vitar8bTlu5jXAc-9zV8w4UMP70zX9_a0E');
INSERT INTO public."user" VALUES ('U682c3380036f', '2023-10-10 10:55:29.900923+00', '2024-07-09 12:54:29.214478+00', 'vadim 5', '', false, 'P7I9rqv9tVrj3HyUU3ZE4-NgWsUd5sOLIMnUWTAzrqs');
INSERT INTO public."user" VALUES ('U6240251593cd', '2023-10-10 10:56:56.758492+00', '2024-07-09 12:54:29.214478+00', 'Vadim asus', '', false, 'rFenjKGGwotGp0558FISgS1dACN1EPoSjeQhIabriRk');
INSERT INTO public."user" VALUES ('U83e829a2e822', '2023-12-12 17:35:38.650638+00', '2024-07-09 12:54:29.214478+00', '', '', false, 'a3Wcg--QOqTUsaL379aI99PAH40MUhYtvj79ctNQufU');
INSERT INTO public."user" VALUES ('U8fc7861a79b9', '2023-12-13 21:50:42.414604+00', '2024-07-09 12:54:29.214478+00', '', '', false, 'FMkR31lzzVqg7RiKkN6xkMLpQbSka0W5Q1xkEkS0QBU');
INSERT INTO public."user" VALUES ('Ua12e78308f49', '2023-10-10 16:22:04.617498+00', '2024-07-09 12:54:29.214478+00', 'Vadim 6', '', false, 'sWbLip4vqZvnYPeyJHomNuwTiC9ZdRJsEcUcf9ugaYE');
INSERT INTO public."user" VALUES ('U9e972ae23870', '2023-12-13 21:50:40.715163+00', '2024-07-09 12:54:29.214478+00', 'Mark Green', '', false, 'Myn9JaLLR-S-YYK5slYfyL87Fm9eodZOFL_TMBKIR_A');
INSERT INTO public."user" VALUES ('U5ee57577b2bd', '2023-12-15 14:13:18.20907+00', '2024-07-09 12:54:29.214478+00', '', '', false, '9Q3cqZnnm-mqaep2SI6578Ggo4bD3pRI7p_FIbOnBdI');
INSERT INTO public."user" VALUES ('Ue328d7da3b59', '2023-12-15 14:13:18.307709+00', '2024-07-09 12:54:29.214478+00', '', '', false, 'RJ0Bhf56-Af1Gr39Kg_LFfpNgKP1wUoQR6FtXTdpa2c');
INSERT INTO public."user" VALUES ('U052641f28245', '2023-12-15 14:13:19.490111+00', '2024-07-09 12:54:29.214478+00', '', '', false, 'GFYvLCnsONdhq5f6UDA9JsGCNHUao5e4GVr-0WyCTYQ');
INSERT INTO public."user" VALUES ('Ueb1e69384e4e', '2023-12-15 14:13:19.66827+00', '2024-07-09 12:54:29.214478+00', '', '', false, '44gwfBnpEAyDhP-ZdYfRngSZL8xNed1c1U9E3WJcrT8');
INSERT INTO public."user" VALUES ('Ud9df8116deba', '2023-10-18 03:11:26.787901+00', '2024-07-09 12:54:29.214478+00', 'Fadeev', '', false, '5H7h6NEA9E_apkurfhIz-ydp4MemMlYCohrGN1GSl54');
INSERT INTO public."user" VALUES ('U26451935eec8', '2023-12-15 14:13:19.911076+00', '2024-07-09 12:54:29.214478+00', '', '', false, 'mwy9jdrlqg2Kdrx5ezTv_LluAiESmW3D26kPORsl6Nk');
INSERT INTO public."user" VALUES ('Ub786ef7c9e9f', '2023-12-15 14:13:21.987113+00', '2024-07-09 12:54:29.214478+00', '', '', false, 'w3Z02peEqoiITZgKKBq742GDXoGw0EuKc5Yv8Kn1wPM');
INSERT INTO public."user" VALUES ('U84f274f30e33', '2023-12-15 14:13:22.629906+00', '2024-07-09 12:54:29.214478+00', '', '', false, '6scLmVhT7HgrAvJj5hhbgKxHvlYXfJNim0J16z7n2tY');
INSERT INTO public."user" VALUES ('Ud18285ef1202', '2023-12-15 14:14:10.616619+00', '2024-07-09 12:54:29.214478+00', '', '', false, '0HkZOY9lajUUKUITFvSUyKc-78bAJs5zx3qrCxjj63s');
INSERT INTO public."user" VALUES ('Ub93c197b25c5', '2023-12-15 14:14:11.214711+00', '2024-07-09 12:54:29.214478+00', '', '', false, 'guWoydi4VO6KXKlJVtYRZGdCJgAzzVRKulc5mhXY7DU');
INSERT INTO public."user" VALUES ('U5d0cd6daa146', '2023-12-15 14:16:08.246641+00', '2024-07-09 12:54:29.214478+00', '', '', false, 'ohYL6I2bLHNNb3DyNOrcIYuqmZ9cDRxC4yUQsqBxTOE');
INSERT INTO public."user" VALUES ('U0b4010c6af8e', '2023-12-15 14:16:08.366073+00', '2024-07-09 12:54:29.214478+00', '', '', false, 'zJiwyGBUjg-SEtmzJlCeWE7rjM5TXdoAyUCceyvjaE8');
INSERT INTO public."user" VALUES ('U2371cf61799b', '2023-12-15 14:16:08.533498+00', '2024-07-09 12:54:29.214478+00', '', '', false, 'AuwJOvUKvPBY-36BfQZRGgArgiuEHZBTB8OPOQAtXGw');
INSERT INTO public."user" VALUES ('U5d9b4e4a7baf', '2023-12-15 14:16:08.714912+00', '2024-07-09 12:54:29.214478+00', '', '', false, 'zuIUIFEDH0g5g44aCm2jjK6CCJXr54rCYukIxHz3_pk');
INSERT INTO public."user" VALUES ('U25982b736535', '2023-12-15 14:16:08.901994+00', '2024-07-09 12:54:29.214478+00', '', '', false, '_YJcncHJX8KmaIALhQ9cTFZ_WrU0w0pio6FejcGjmqc');
INSERT INTO public."user" VALUES ('U89a6e30efb07', '2023-12-15 14:16:09.104731+00', '2024-07-09 12:54:29.214478+00', '', '', false, 'qnLcnIJqH6UKxy2md8jrD8olH4MK30h5TJF7Ml4P7rs');
INSERT INTO public."user" VALUES ('U802de6b3675a', '2023-12-15 14:16:09.266845+00', '2024-07-09 12:54:29.214478+00', '', '', false, 'NKXmPAXlgAOPuQCt9tl0s9BrSwBllTV3SsRQvOOTNDU');
INSERT INTO public."user" VALUES ('U8c33fbcc06d7', '2023-12-15 14:16:45.555168+00', '2024-07-09 12:54:29.214478+00', '', '', false, 'mH3JPB3xWNgfVBkp_0JDBRnCU7_nC6uOwjdsHTlI9Q8');
INSERT INTO public."user" VALUES ('Ucfe743b8deb1', '2023-12-15 14:16:46.120879+00', '2024-07-09 12:54:29.214478+00', '', '', false, 'UG9eHIB-hLLa3b_HprKPKR603A-9TQgi4g8MossPyWY');
INSERT INTO public."user" VALUES ('U1e41b5f3adff', '2023-10-19 22:19:03.57401+00', '2024-07-09 12:54:29.214478+00', 'vad7', '', false, 'a2-33WA-8nbiNJIoEHcyBwgLaY3jI_UCGoNBIyXZ2jA');
INSERT INTO public."user" VALUES ('U4dac6797a9cc', '2023-12-15 14:16:46.58295+00', '2024-07-09 12:54:29.214478+00', '', '', false, 'ysqXtw6PY-PRX9gX5s52mLVzl8EperRwKyyhqVqFQiM');
INSERT INTO public."user" VALUES ('Ud04c89aaf453', '2023-10-20 18:52:01.450226+00', '2024-07-09 12:54:29.214478+00', 'vad8', '', false, 'TyFvgsuPdbjgVHwpehvHcHnSI1wuPBf4DPz_MxJEmJI');
INSERT INTO public."user" VALUES ('U96a8bbfce56f', '2023-11-15 10:39:04.378683+00', '2024-07-09 12:54:29.214478+00', '', '', false, 'rRNeF6Cn_zwpTbX8cqofrFUmRkGGgInPAGtDFvWDffY');
INSERT INTO public."user" VALUES ('U049bf307d470', '2023-11-16 16:24:38.643802+00', '2024-07-09 12:54:29.214478+00', '', '', false, 'JhMdxOmvtEdKdsKLIo134XmlCoqPeREQKVQDrsRttcE');
INSERT INTO public."user" VALUES ('U0e214fef4f03', '2023-11-17 14:04:55.857826+00', '2024-07-09 12:54:29.214478+00', '', '', false, 'HLDsspWFEkrADSZrsrQe_jq9_CX8_L_LD2c6z6LKulQ');
INSERT INTO public."user" VALUES ('Uf8eb8562f949', '2023-11-17 14:05:00.443871+00', '2024-07-09 12:54:29.214478+00', '', '', false, 'Cn2UULfQaK384vpHpoHZiGIk6sVY17VRDys5u0z2yeE');
INSERT INTO public."user" VALUES ('U5502925dfe14', '2023-11-20 17:48:34.662876+00', '2024-07-09 12:54:29.214478+00', '', '', false, '0J1h4H1GSDHRz0a9NRFSCbyuaHeMNeeQ_-6bWuZFPXE');
INSERT INTO public."user" VALUES ('Uf9ecad50b7e1', '2023-11-20 17:48:38.352123+00', '2024-07-09 12:54:29.214478+00', '', '', false, 'sLuBDkwiJ4xUynzSnh_ofWoWIU3zw320UZRWPzeaCYE');
INSERT INTO public."user" VALUES ('U17789c126682', '2023-11-20 17:49:03.325483+00', '2024-07-09 12:54:29.214478+00', '', '', false, 'D_zn4wbwv4Daia6_ORsJc916KS5-h9i955L1ICdJaoY');
INSERT INTO public."user" VALUES ('U77f496546efa', '2023-11-20 17:49:08.366265+00', '2024-07-09 12:54:29.214478+00', '', '', false, 'Y5e0NbSaLBoZf4cTn5zaZpS2GOgM9HMsnkEfUjgRk0I');
INSERT INTO public."user" VALUES ('Ua9f1d3f8ee78', '2023-11-20 17:52:20.651948+00', '2024-07-09 12:54:29.214478+00', '', '', false, 'v2D-LZEJKPXvm8CS-LqHGPCJ6EUv4rsmGSONLZ8Uabs');
INSERT INTO public."user" VALUES ('U6249d53929c4', '2023-11-20 17:52:22.057514+00', '2024-07-09 12:54:29.214478+00', '', '', false, 'I8iTHUBE0mnlksqVzPtIkCpQ3C3Jax3ikzNgqIOWjpE');
INSERT INTO public."user" VALUES ('Ua01529fb0d57', '2023-11-20 17:52:26.259706+00', '2024-07-09 12:54:29.214478+00', '', '', false, 'u5gwE91t4oeDfc-54HzPblbuPOSqVUuA7A-iRerhzag');
INSERT INTO public."user" VALUES ('U4f530cfe771e', '2023-11-20 17:52:27.4937+00', '2024-07-09 12:54:29.214478+00', '', '', false, 'EWu9BfFz1Rp8JELnomtzu6C5D9s5BxQYzajsfdnfNqU');
INSERT INTO public."user" VALUES ('U79466f73dc0c', '2023-11-24 19:56:19.154891+00', '2024-07-09 12:54:29.214478+00', 'Anna', 'Devoted to volunteering  for  meaningful  impact 
', false, '2CMlTuiroQxtb9K4eTOBtJjZDgWJ6x4ZhFypI2CuhlI');
INSERT INTO public."user" VALUES ('U5b09928b977a', '2023-11-25 23:45:42.204856+00', '2024-07-09 12:54:29.214478+00', '', '', false, '66omdAdhP0HtTo-lzFzbpS0hV17sHfXeUNHSYSgIskQ');
INSERT INTO public."user" VALUES ('Ud826f91f9025', '2023-11-25 23:45:43.021017+00', '2024-07-09 12:54:29.214478+00', '', '', false, 'CCd07THSqnjJxgi5vn92ZzUERhB-ovvZm-PIKNxH-G4');
INSERT INTO public."user" VALUES ('Uc35c445325f5', '2023-10-24 16:19:19.852582+00', '2024-07-09 12:54:29.214478+00', 'vad9', '', false, 'QyIaoPVWHHaOMy7bUvMra_LKngatZM_Fga2S2VyGT8Q');
INSERT INTO public."user" VALUES ('U0453a921d0e7', '2023-11-25 23:45:45.163472+00', '2024-07-09 12:54:29.214478+00', '', '', false, '7b8j6vgBn-gOi5x5SNHhIiiZXJyDi5spUXH7yXV_fUk');
INSERT INTO public."user" VALUES ('U6622a635b181', '2023-11-25 23:45:47.321237+00', '2024-07-09 12:54:29.214478+00', '', '', false, 'ge4_5k7pKMAfHBaUylBxZ4_gOWsSbYFl5BQRVH1G_JI');
INSERT INTO public."user" VALUES ('U6a774cf456f7', '2023-11-25 23:45:50.884197+00', '2024-07-09 12:54:29.214478+00', '', '', false, '24q8XaGyJ5Kv16f0ekWGe2Ow69D4SgYU7n6JTyqsU2k');
INSERT INTO public."user" VALUES ('U1188b2dfb294', '2023-11-25 23:45:52.383685+00', '2024-07-09 12:54:29.214478+00', '', '', false, 'le956l40xKKr7VhNiFfHkbHKuR7JS-MuWzUcKWTzJl8');
INSERT INTO public."user" VALUES ('Uac897fe92894', '2023-11-25 23:45:58.688175+00', '2024-07-09 12:54:29.214478+00', '', '', false, 'R0Z2k3CpAsEwk2G4CRttigqsw26UYpkEEscHoiQ0lAU');
INSERT INTO public."user" VALUES ('Ue5c10787d0db', '2023-11-25 23:46:03.04317+00', '2024-07-09 12:54:29.214478+00', '', '', false, '6ui5NdlxNIRZq20gElug6a74-zhLPKSxPIBEtw-_KZU');
INSERT INTO public."user" VALUES ('Ubd3c556b8a25', '2023-11-25 23:46:03.598632+00', '2024-07-09 12:54:29.214478+00', '', '', false, '9wBPFwgu7bTAhXOllCs1j-fO9888KWAzoLF9GzxcKwM');
INSERT INTO public."user" VALUES ('Ucb9952d31a9e', '2023-11-25 23:46:26.517122+00', '2024-07-09 12:54:29.214478+00', '', '', false, 'K7JtAxP2KOpFMfvEHLvSoEyfoEFOGLSaxMflapUYLXI');
INSERT INTO public."user" VALUES ('U3c63a9b6115a', '2023-10-27 17:59:56.464718+00', '2024-07-09 12:54:29.214478+00', 'kato', 'kahhftjjvddti njk jjj
', false, 'OFG9FJhviDGIAxBB-MALDCSnWEwb0kAmQds87KJ6CD0');
INSERT INTO public."user" VALUES ('U7462db3b65c4', '2023-11-25 23:46:36.273546+00', '2024-07-09 12:54:29.214478+00', '', '', false, 'SmKoBuIEZ4YWWl8lyCRcdm23aTLCG6RcuvXUh0nBU-Y');
INSERT INTO public."user" VALUES ('U3b6ea55b4098', '2023-11-25 23:46:56.490797+00', '2024-07-09 12:54:29.214478+00', '', '', false, '92UvL8Avco_y6GIUCY2h6kzMv4ZjyYMo5MLm_6W89rA');
INSERT INTO public."user" VALUES ('Udfbfcd087e6b', '2023-11-25 23:47:11.049376+00', '2024-07-09 12:54:29.214478+00', '', '', false, 'o1OaewSS9Vqe1KMkylEd1oeqQFnSrs6-vyohFD3UDNc');
INSERT INTO public."user" VALUES ('Ubeded808a9c0', '2023-11-26 00:14:10.982345+00', '2024-07-09 12:54:29.214478+00', '', '', false, '1xqF2O0JfXTCLorA804D3OOI7pTZohVL9EzJ3rqrWhY');
INSERT INTO public."user" VALUES ('U0cd6bd2dde4f', '2023-10-30 17:17:53.278344+00', '2024-07-09 12:54:29.214478+00', 'Marsel', '', false, 'UIBW70asbHKMCmacWPY8ztR7YWDeeiSCH1ix39XZjRI');
INSERT INTO public."user" VALUES ('U7eaa146a4793', '2023-11-26 12:15:29.902841+00', '2024-07-09 12:54:29.214478+00', '', '', false, 'EhzbKzdNKalAJLA2Hw2MhDQzE0VYx8V8XAdHwSpaItQ');
INSERT INTO public."user" VALUES ('Ucb84c094edba', '2023-11-26 12:15:34.054021+00', '2024-07-09 12:54:29.214478+00', '', '', false, 'JqIIgLlx1CfufGBBLY46LwgimYdM-gxqLfMaoZxa3VY');
INSERT INTO public."user" VALUES ('U6942e4590e93', '2023-12-07 09:17:39.217711+00', '2024-07-09 12:54:29.214478+00', '', '', false, 'oCro9g9quJ8EI__ELHoHpPRlRahCMGRBFeFvJOz2Ae8');
INSERT INTO public."user" VALUES ('U7a54f2f24cf6', '2023-12-07 09:17:40.218779+00', '2024-07-09 12:54:29.214478+00', '', '', false, 'wK53IBrCFoucdLfkxfmlW4A4zD3hML5BuqtAYZwJcvk');
INSERT INTO public."user" VALUES ('U27847df66cb4', '2023-12-07 09:17:40.762409+00', '2024-07-09 12:54:29.214478+00', '', '', false, 'bHQIJe6pZ6rNw797OaRt0ExPgdT5wQapDQge29j97Xo');
INSERT INTO public."user" VALUES ('U5e1dd853cab5', '2023-12-07 09:17:41.006059+00', '2024-07-09 12:54:29.214478+00', '', '', false, 'UVk7SInbpQN7GDI4qgwzh7w5HWX13Du0TBwZs5ps5qs');
INSERT INTO public."user" VALUES ('U7553cc7bb536', '2023-12-07 09:17:41.233541+00', '2024-07-09 12:54:29.214478+00', '', '', false, 'QQMirWm89Vf0OScsfWXrZfthkPRab2tKRwqIRvAqDrE');
INSERT INTO public."user" VALUES ('U7a975ca7e0b0', '2023-12-07 09:17:41.472351+00', '2024-07-09 12:54:29.214478+00', '', '', false, 'Jh1j8RnMHYq6nPC28WyjXBMifaI1pNduPZoWt6md8so');
INSERT INTO public."user" VALUES ('U5ef3d593e46e', '2023-12-07 09:17:41.718828+00', '2024-07-09 12:54:29.214478+00', '', '', false, 'kv5c1lptDWcAwfXRjX5sZcLVOl4yl6xo9zag7VMJbGw');
INSERT INTO public."user" VALUES ('Ue20d37fe1d62', '2023-12-07 09:17:41.936402+00', '2024-07-09 12:54:29.214478+00', '', '', false, 'WYRsmQT0QFRqOesK-rYGWMrnQJH68PSrHPbfzrqGKGk');
INSERT INTO public."user" VALUES ('U1c634fdd7c82', '2023-12-07 09:17:42.161774+00', '2024-07-09 12:54:29.214478+00', '', '', false, 'Bf554BuY7hC3pBcihc8_YvQE3EwNg3CWmT1CTQ2xLhQ');
INSERT INTO public."user" VALUES ('U4c619411e5de', '2023-12-07 09:17:42.387559+00', '2024-07-09 12:54:29.214478+00', '', '', false, '1V8sda2usdfJy88zC5IgfrI4MeAT4KcvNYhJj1dknzQ');
INSERT INTO public."user" VALUES ('Ue3b747447a90', '2023-12-07 09:17:42.606658+00', '2024-07-09 12:54:29.214478+00', '', '', false, 'hH9eScr9ZPH4I-6OwEOxeHf2tveGm8K_06Mce0gEkks');
INSERT INTO public."user" VALUES ('U660f0dfe3117', '2023-12-07 09:17:42.833033+00', '2024-07-09 12:54:29.214478+00', '', '', false, 'TUR00N0GxsXr1rGMLzVOEnHMwm0_pyymMVPoEOBmrJg');
INSERT INTO public."user" VALUES ('Ub152bb6d4a86', '2023-12-07 09:17:43.073274+00', '2024-07-09 12:54:29.214478+00', '', '', false, 's9c0fia47bbVktW3G29NynPLMLf9imdn9Zw5i7zqCTY');
INSERT INTO public."user" VALUES ('Uab20c65d180d', '2023-12-07 09:17:43.28672+00', '2024-07-09 12:54:29.214478+00', '', '', false, 'XOoaJ_0NZpFBH72UQ36jxPBUtoVQbVqzm-_8zoSEF-U');
INSERT INTO public."user" VALUES ('U7c9ce0ac22b7', '2023-12-07 09:17:43.484506+00', '2024-07-09 12:54:29.214478+00', '', '', false, 'hSoN0O3K6gLb9GTo5vQP-qdKFIiBn--YJXpt9aJISno');
INSERT INTO public."user" VALUES ('U14a3c81256ab', '2023-12-07 09:21:48.0235+00', '2024-07-09 12:54:29.214478+00', '', '', false, 'FvSphzHUrxjfGuQZynrVZod9ZjTiCzhfkbUZwfQXg2k');
INSERT INTO public."user" VALUES ('U2cd96f1b2ea6', '2023-12-13 21:40:36.562214+00', '2024-07-09 12:54:29.214478+00', 'Anna', '', false, '5G1HMAppxaVNwuQcDmJi1qM-2lHMsbekTP8BIY6bnnM');
INSERT INTO public."user" VALUES ('Ubcf610883f95', '2023-12-15 12:46:14.814377+00', '2024-07-09 12:54:29.214478+00', '', '', false, 'WnOoJLJR5fWm9feIIz60Q5WFyl5qtwGF8P0d-SV3WIw');
INSERT INTO public."user" VALUES ('Ub10b78df4f63', '2023-12-15 14:16:46.635275+00', '2024-07-09 12:54:29.214478+00', '', '', false, 'RsW2cQYOka7I7C_m8ZZ9wRpNjNoUTn1ig5O_NbxhDIY');
INSERT INTO public."user" VALUES ('U622a649ddf56', '2023-12-15 14:16:46.846933+00', '2024-07-09 12:54:29.214478+00', '', '', false, 'umEhGkXoq4ZrZCGn79yby-ZekGObCQqzPZAGYzkhmZQ');
INSERT INTO public."user" VALUES ('U5f2702cc8ade', '2023-12-15 14:16:46.880414+00', '2024-07-09 12:54:29.214478+00', '', '', false, 'HSV1Qnf1Oqk-KISf-9MUhbkvjP6hyHVVJwCGdoYYn_g');
INSERT INTO public."user" VALUES ('U996b5f6b8bec', '2023-12-15 14:16:46.983334+00', '2024-07-09 12:54:29.214478+00', '', '', false, '6wf3let0Ay1aBrXJRy7KUdUrv-kpv6bhWCdTCDYGetg');
INSERT INTO public."user" VALUES ('U8676859527f3', '2023-12-15 14:16:47.044214+00', '2024-07-09 12:54:29.214478+00', '', '', false, 'B-2q81VcR0kpuCVkVb3QXza4TXOdx3W9TAgNfbRm9sI');
INSERT INTO public."user" VALUES ('U0a227036e790', '2023-12-15 14:16:47.153009+00', '2024-07-09 12:54:29.214478+00', '', '', false, 'SeELxuS4iyrFKRNxIHDds0gzGNaDEkBU3L7Rx7q2J4U');
INSERT INTO public."user" VALUES ('U40096feaa029', '2023-12-15 14:16:47.361376+00', '2024-07-09 12:54:29.214478+00', '', '', false, 'GUwX-Esz0uvOv49VojDWqJ2404-wwEj1Ycka3s4hQH0');
INSERT INTO public."user" VALUES ('Ua7759a06a90a', '2023-12-15 14:16:47.606753+00', '2024-07-09 12:54:29.214478+00', '', '', false, '2YwrsCe2GbAgZst9TJ-jyznP7hr9ZT2pYvIhG2CR1cg');
INSERT INTO public."user" VALUES ('Ub7f9dfb6a7a5', '2023-12-15 14:47:18.733198+00', '2024-07-09 12:54:29.214478+00', '', '', false, '1P3oCcUavkfemxzf6YWe9kE1isd97-6xAajZTjG59y0');
INSERT INTO public."user" VALUES ('U6106ae1092fa', '2023-12-15 14:47:20.046478+00', '2024-07-09 12:54:29.214478+00', '', '', false, 'YmD6nE7detKXWFS9sTyvPNpfUsja2J3GS7UIfRvYo8s');
INSERT INTO public."user" VALUES ('U57a6591c7ee1', '2023-12-15 14:47:21.248839+00', '2024-07-09 12:54:29.214478+00', '', '', false, 'IcNqWk_v23mYIDNL4rD3Wf4HwWboAxUnVV9qCDkK2SA');
INSERT INTO public."user" VALUES ('U638f5c19326f', '2023-12-15 17:03:45.641383+00', '2024-07-09 12:54:29.214478+00', 'Guntur', 'I like tentura', false, 'bSPlo-W2gjE4kTFZsaT0PvEqrNo7DVYlXfDyXOZSNsw');
INSERT INTO public."user" VALUES ('Ub192fb5e4fee', '2023-12-19 13:49:17.683124+00', '2024-07-09 12:54:29.214478+00', '', '', false, 'FuZ66Y56FWoEJsmJZ5mfJDkbYXwYYp9f7QFPRqowEEE');
INSERT INTO public."user" VALUES ('U4d6816b2416e', '2023-12-19 21:16:52.700869+00', '2024-07-09 12:54:29.214478+00', '', '', false, 'Kbvy3Oskqx2tp_q3edvLpNY-16mfC3pyfEZcRlrU-XQ');
INSERT INTO public."user" VALUES ('U393de9ce9ec4', '2023-12-19 21:19:19.88339+00', '2024-07-09 12:54:29.214478+00', '', '', false, 'Eq9HJFrjQ0FGCxqzHDxHJnPokFTGQ9HZWqZlb06fV8I');
INSERT INTO public."user" VALUES ('Uc78a29f47b21', '2023-12-19 21:26:27.450265+00', '2024-07-09 12:54:29.214478+00', '', '', false, 'sAE0_hVm79CIDb7724zWgd7RKapAn7VqSj94fdGnIC4');
INSERT INTO public."user" VALUES ('U11456af7d414', '2023-12-23 22:06:00.470553+00', '2024-07-09 12:54:29.214478+00', 'v nexus 5', '', false, 'ucBSZcwQx8apif9HQaVjlmTZU6Xqcypi_j1RjvCBU4A');
INSERT INTO public."user" VALUES ('U663cd1f1e343', '2023-12-24 19:13:13.569312+00', '2024-07-09 12:54:29.214478+00', '', '', false, 'Xd13PbdtzDfbBNABISVHutVMnOlwu2NFlGsF4DoG81c');
INSERT INTO public."user" VALUES ('U83282a51b600', '2023-12-24 19:13:17.832332+00', '2024-07-09 12:54:29.214478+00', '', '', false, 'gEYESb5Hk9ZlHj2Um9yh2p4V55t0VTDaof_qEXnzUhs');
INSERT INTO public."user" VALUES ('U38fdca6685ca', '2023-12-24 19:13:19.324544+00', '2024-07-09 12:54:29.214478+00', '', '', false, 'PCjm8mlOIJ1sYmr3Z9ZxWMf4l59cf04JdIK_JsEdy4o');
INSERT INTO public."user" VALUES ('U3116d27854ab', '2023-12-24 19:13:24.234075+00', '2024-07-09 12:54:29.214478+00', '', '', false, 'Fsu_bKjImDOG1kgbGdt5oWKNoZ-hJtaHc5KL9N6Hsgk');
INSERT INTO public."user" VALUES ('Uc67c60f504ce', '2023-12-24 19:13:27.255797+00', '2024-07-09 12:54:29.214478+00', '', '', false, 'LH2vc4D8GfiVs8ICy8gF-cg6e3WJHjor0d45YWVwkB0');
INSERT INTO public."user" VALUES ('U22ad914a7065', '2023-12-24 19:13:28.297878+00', '2024-07-09 12:54:29.214478+00', '', '', false, 'AqNsNZJJpa5y0AEAyCLJd9FD2EJXOdAElC2tYAQlgbo');
INSERT INTO public."user" VALUES ('U35eb26fc07b4', '2023-12-24 19:14:03.452891+00', '2024-07-09 12:54:29.214478+00', '', '', false, 'TbtJRBr_vsiMwuaW11rl6H27BrNX3dBWtrA6ySl5Iqw');
INSERT INTO public."user" VALUES ('U3bbfefd5319e', '2023-12-24 19:14:08.616048+00', '2024-07-09 12:54:29.214478+00', '', '', false, 'GjSf_I9eUJgxVZuhAOxrnmNWP_j5Vso3iQ8grGqyh7E');
INSERT INTO public."user" VALUES ('Uf91b831f1eb7', '2023-12-24 19:14:33.661378+00', '2024-07-09 12:54:29.214478+00', '', '', false, 'n7XPjyuLpBok2IPgfuR2uuC2j6WFqTJsbBjbVFYr_XM');
INSERT INTO public."user" VALUES ('U7ac570b5840f', '2023-12-24 19:15:32.849692+00', '2024-07-09 12:54:29.214478+00', '', '', false, 'm7OqSwxEtJP_-PvLBm1wnSm9XXR7lEBUgTF_NcRpzQg');
INSERT INTO public."user" VALUES ('U526f361717a8', '2023-12-24 19:16:39.579572+00', '2024-07-09 12:54:29.214478+00', '', '', false, '8_k6oyUxqdjQkZ7374-eCJlLj8gniQjo3TFMqqBmVbY');
INSERT INTO public."user" VALUES ('U73057a8e8ebf', '2023-12-24 19:17:05.298639+00', '2024-07-09 12:54:29.214478+00', '', '', false, '_Z0sIy9gpceR9u1D6AveO2xl5S3S9GWAgFFp9ZHg1Ew');
INSERT INTO public."user" VALUES ('Ucd424ac24c15', '2023-12-24 19:17:50.42851+00', '2024-07-09 12:54:29.214478+00', '', '', false, 'ZqUmFcXvdcxWkxJyCdlEDn33s215STzlMaYTZM7epeE');
INSERT INTO public."user" VALUES ('Uda0a7acaeb90', '2023-12-24 19:21:05.541333+00', '2024-07-09 12:54:29.214478+00', '', '', false, 'ZS70TAeIyjBN-BDUI5mMpX-0WIzC3YTQ_Vomk5iPX3k');
INSERT INTO public."user" VALUES ('Ud5f1a29622d1', '2023-12-24 19:21:09.047042+00', '2024-07-09 12:54:29.214478+00', '', '', false, 'pCOZzAKETML3xzsjgNKNXJiHeUBA7J_KaMCHRJN1vbw');
INSERT INTO public."user" VALUES ('U6629a0a8ef04', '2023-12-24 19:22:55.07353+00', '2024-07-09 12:54:29.214478+00', '', '', false, '-AKTLa-3J1gt12MYTDUooHAVJgUNoRK0soMZjFYkoNA');
INSERT INTO public."user" VALUES ('U4ba2e4e81c0e', '2023-12-24 19:23:00.258495+00', '2024-07-09 12:54:29.214478+00', '', '', false, 'Jripy_gwhFmh3bWEjVz4gEy8j55DOwefunKHzQdDpmk');
INSERT INTO public."user" VALUES ('Uf75d4cbe5430', '2023-12-24 19:29:20.310821+00', '2024-07-09 12:54:29.214478+00', '', '', false, 'd23RJZ6XWqp7HfdxlQsPQh2uGEpvG2j3RjmkQtPX0AU');
INSERT INTO public."user" VALUES ('U2f08dff8dbdb', '2023-12-24 19:29:24.134911+00', '2024-07-09 12:54:29.214478+00', '', '', false, 'pXdWuOCExaslHbfOH-w4gc9Or4VzwQCh5bHw0SMsfBo');
INSERT INTO public."user" VALUES ('Ubbe66e390603', '2023-12-25 12:16:04.174887+00', '2024-07-09 12:54:29.214478+00', '', '', false, 'udAKX1Btw7Unv9uqCZ7Pd1gEILjAyRdzLuXsefDTLYc');
INSERT INTO public."user" VALUES ('U59abf06369c3', '2023-12-25 12:16:08.370733+00', '2024-07-09 12:54:29.214478+00', '', '', false, 'ud1lFsbKOuPvgHFsbrI6_ex_klp4FY-W8bR2ls6W-MQ');
INSERT INTO public."user" VALUES ('U47b466d57da1', '2023-12-25 17:09:45.310187+00', '2024-07-09 12:54:29.214478+00', '', '', false, 'DC_NFIjiMdC2puVC9wxNiA2SHGzaXy4I7MXZvz29K9c');
INSERT INTO public."user" VALUES ('U18a178de1dfb', '2023-12-26 15:53:42.233414+00', '2024-07-09 12:54:29.214478+00', 'Nemo N50', '', false, 'bkCNqSJw_g8hOaYkKrl0WBngn59K2M0EFMoSEbT3dr8');
INSERT INTO public."user" VALUES ('U4dd243415525', '2023-12-27 12:49:12.487354+00', '2024-07-09 12:54:29.214478+00', '', '', false, 'wSlHzhfwPVRjJB7blW37pFtpxt4BzOSt4KEc5ZBlw6E');
INSERT INTO public."user" VALUES ('U0f63ee3db59b', '2023-12-27 12:49:16.52244+00', '2024-07-09 12:54:29.214478+00', '', '', false, '57NEmsDIsLyOXZTgnDuy6BNzfpbFM0rPva-IQpf19nY');
INSERT INTO public."user" VALUES ('U4a6d6f193ae0', '2023-12-27 13:09:33.699807+00', '2024-07-09 12:54:29.214478+00', '', '', false, '4YYoNQBvCMKuW2id2_2b3By9AB3jw6R0y1mvLJIdv5c');
INSERT INTO public."user" VALUES ('Ua4041a93bdf4', '2023-12-27 13:09:41.856478+00', '2024-07-09 12:54:29.214478+00', '', '', false, 'R26jufJ5_BtMGJTiPVKXItl7EhyNlcVlhkrf5jRqHzc');
INSERT INTO public."user" VALUES ('U044c5bf57a97', '2023-12-27 13:09:42.64263+00', '2024-07-09 12:54:29.214478+00', '', '', false, '81drqBS17pKFXzTNe9OhbIDU6rBs3qSP9adOlGONYS4');
INSERT INTO public."user" VALUES ('Ua5a9eab9732d', '2023-12-27 13:09:43.617252+00', '2024-07-09 12:54:29.214478+00', '', '', false, 'm4UWifc48waNJ6Hz56xkGDJH6ARcgm21oULj2S5htcw');
INSERT INTO public."user" VALUES ('U8b70c7c00136', '2023-12-27 13:09:47.189727+00', '2024-07-09 12:54:29.214478+00', '', '', false, 'ymjAYV_s5JlUeuIOTfWRXeH0oxIh3Tt9XABPJqeAbSs');
INSERT INTO public."user" VALUES ('U36055bb45e5c', '2023-12-27 13:09:48.963861+00', '2024-07-09 12:54:29.214478+00', '', '', false, 'D00d1LblV2wNGeReuk6k0NsWGGHTaxkvea49bf2pCE4');
INSERT INTO public."user" VALUES ('U0e6659929c53', '2023-12-27 13:09:49.992972+00', '2024-07-09 12:54:29.214478+00', '', '', false, 'GcLcia_HuHZYFFa8GvnvGFsmzxP0tCX4Xkrk7ngADZw');
INSERT INTO public."user" VALUES ('U4d82230c274a', '2023-12-27 13:09:54.248985+00', '2024-07-09 12:54:29.214478+00', '', '', false, 'pJMUcIacisb0A_Vi6C1lZ1LjkmNEdxBMcPKJlK6i_wQ');
INSERT INTO public."user" VALUES ('U2cb58c48703b', '2023-12-27 13:14:58.117772+00', '2024-07-09 12:54:29.214478+00', '', '', false, 't13QWDjsWUYg8UZGUwt6YMMCaKK1PG4PVKwKXuv9HwE');
INSERT INTO public."user" VALUES ('U831a82104a9e', '2023-12-27 13:15:02.102489+00', '2024-07-09 12:54:29.214478+00', '', '', false, 'kkIzXbDBtopjRjO4w9BhSoCk1FXiFdtBk_IJ_QTNa_M');
INSERT INTO public."user" VALUES ('U7dd2b82154e0', '2023-12-27 13:17:50.030131+00', '2024-07-09 12:54:29.214478+00', '', '', false, '7ffKn1BIKBZ5JFOwhVEi_3lXXyf-leGbt6jWlwsJb6Q');
INSERT INTO public."user" VALUES ('U43dcf522b4dd', '2023-12-27 13:17:54.112293+00', '2024-07-09 12:54:29.214478+00', '', '', false, '8OY6OFAKzAZpmvtKJj9ap_FTzmp2bRnqj1vw7gFl5II');
INSERT INTO public."user" VALUES ('U1f348902b446', '2023-12-27 13:18:52.844594+00', '2024-07-09 12:54:29.214478+00', '', '', false, 'BE50XWcz0hwXRhdPydu0KzjmdQd0QxTTAR27IsqXVy0');
INSERT INTO public."user" VALUES ('Ue70d59cc8e3f', '2023-12-27 13:18:56.812407+00', '2024-07-09 12:54:29.214478+00', '', '', false, 'cbw7QV20jTKH7VCG1iCqtcqFCmC08YK2BeoPiPkAy7w');
INSERT INTO public."user" VALUES ('U8456b2b56820', '2023-12-27 13:20:40.07705+00', '2024-07-09 12:54:29.214478+00', '', '', false, 'HAz7H0vw9uwV3EurtfRzcg4WrH_Mi6GPHwVbmGDHJcQ');
INSERT INTO public."user" VALUES ('U1eedef3e4d10', '2023-12-27 13:21:34.004467+00', '2024-07-09 12:54:29.214478+00', '', '', false, 'rAHagK7CKAcSpvLggK8M0rLTnEDJHGuvdP7iWUeEECQ');
INSERT INTO public."user" VALUES ('Uf3b5141d73f3', '2023-12-27 13:21:38.698078+00', '2024-07-09 12:54:29.214478+00', '', '', false, 'JyPnRAOz294lfmTwizkmkXHFyqrutix5cLerJG_v2W8');
INSERT INTO public."user" VALUES ('U37f5b0f1e914', '2023-12-27 15:56:17.610608+00', '2024-07-09 12:54:29.214478+00', '', '', false, 'qK4V_6sHx2Mw8kGbwg4oqSkLj7EGVzoVWAZImOho2Ys');
INSERT INTO public."user" VALUES ('Ue73fabd3d39a', '2024-01-03 10:26:42.084198+00', '2024-07-09 12:54:29.214478+00', '', '', false, 'UouNCaOxQyK9YMasz6t4PTUBOrBYJOGIWejlzwycyHw');
INSERT INTO public."user" VALUES ('Uf8bf10852d43', '2024-01-26 12:49:23.721382+00', '2024-07-09 12:54:29.214478+00', '', '', false, 'o3EpWyvKn07VAWW6ml9oxhmG3cwU52c8Kq6IVmlmtSI');
INSERT INTO public."user" VALUES ('U0da9e22a248b', '2024-01-26 13:43:14.560156+00', '2024-07-09 12:54:29.214478+00', '', '', false, 'Syl0UeFwBLvP5DwrLRIHUggt6vQw4UF-vfGhNeQtsW8');
INSERT INTO public."user" VALUES ('U2d8ff859cca4', '2024-01-26 13:43:17.5155+00', '2024-07-09 12:54:29.214478+00', '', '', false, 'UfIHZLO6I2WuyzEBIH4ajQJzDEcW65hhgEb0sogbipk');
INSERT INTO public."user" VALUES ('U67bf00435429', '2024-01-26 13:43:31.374528+00', '2024-07-09 12:54:29.214478+00', 'lbj', 'l
', false, 'wI2zknsy7n6v41zjbG1ITvRLfLw1bXsDutH-mn_ryao');
INSERT INTO public."user" VALUES ('Uc676bd7563ec', '2024-01-26 14:25:38.377942+00', '2024-07-09 12:54:29.214478+00', '', '', false, 'Piz_LG9cu5-gWBs1UymSV6f52aAC1mH-kooFWQdfCI8');
INSERT INTO public."user" VALUES ('Ua85bc934db95', '2024-01-26 14:27:12.981997+00', '2024-07-09 12:54:29.214478+00', '', '', false, 'OX9GMmGYnbQR1XnY86fZXM-KYGVERcZY0TLYy8SAq6M');
INSERT INTO public."user" VALUES ('Uf6ce05bc4e5a', '2024-01-26 14:27:13.860557+00', '2024-07-09 12:54:29.214478+00', '', '', false, 'AvWTRacDYEWX1rg1Bv6zbt8LNPMo0j0fZVYeo98pfek');
INSERT INTO public."user" VALUES ('U72f88cf28226', '2024-01-26 14:46:52.811035+00', '2024-07-09 12:54:29.214478+00', '', '', false, 'PjAssQAYubZkps76g_5MdJ5pYGwzZNNFYtom4a8RgLk');
INSERT INTO public."user" VALUES ('Ue40b938f47a4', '2024-01-26 15:07:07.753786+00', '2024-07-09 12:54:29.214478+00', 'vbvvbh', 'bbhhhhh', false, 'RJ_9PTX-0wBM9gH7syF3PyiShjI1gVDSNi6Dx73r1pA');
INSERT INTO public."user" VALUES ('U96a7841bc98d', '2024-01-26 15:26:19.043101+00', '2024-07-09 12:54:29.214478+00', '', '', false, '-0SRZYi7RAhNLGgnVPY8J3KXPiXyT7NS7E2HtoU8Pxw');
INSERT INTO public."user" VALUES ('U9ce5721e93cf', '2024-02-16 15:12:12.268882+00', '2024-07-09 12:54:29.214478+00', '', '', false, '6oJbuRHLkPQs5n3KGmWhkSmDbunArp8ZRaMM4K6PH4Y');
INSERT INTO public."user" VALUES ('U36ddff1a63d8', '2024-02-16 15:57:56.782225+00', '2024-07-09 12:54:29.214478+00', '', '', false, 'gUajs0sgc60wZi2N1DF2Hfk2o4eipi6uoVRnUVYSJZI');
INSERT INTO public."user" VALUES ('U8889e390d38b', '2024-02-16 15:59:26.41538+00', '2024-07-09 12:54:29.214478+00', '', '', false, 'd-xJtyap-m9kOLk2M6-1WPNCK0GJSqyMB-erRMMjw8A');
INSERT INTO public."user" VALUES ('U9361426a2e51', '2024-02-16 16:00:19.319229+00', '2024-07-09 12:54:29.214478+00', '', '', false, 'ce1U7G10vXg0Kl65-s8RnAk9hom8WcWGQEbNXIf87Ds');
INSERT INTO public."user" VALUES ('Ucc8ea98c2b41', '2024-02-16 16:33:05.136944+00', '2024-07-09 12:54:29.214478+00', 'Vadim 216', '', false, '-x3gyCqR9sB1YSqGgzkpphSt3QQOPOqO5o2E5BOuMfc');
INSERT INTO public."user" VALUES ('U45578f837ab8', '2024-04-19 02:22:10.694978+00', '2024-07-09 12:54:29.214478+00', '', '', false, '85-HryxWae83s_isAvX-_3UN7T4z2kpjV-o5w8CWjaA');
INSERT INTO public."user" VALUES ('U88e719e6257d', '2024-04-19 02:22:12.885367+00', '2024-07-09 12:54:29.214478+00', '', '', false, 'WrYdnPzQYgnDuoyNkMDXPWGMF7VC7jR2Rq5GrQ-I6dU');
INSERT INTO public."user" VALUES ('U3614888a1bdc', '2024-04-19 02:22:26.407399+00', '2024-07-09 12:54:29.214478+00', '', '', false, 'I3IJ-4FApx6Foy8ZtvYBB7EcPHDb9zuy1sXsFkaih8c');
INSERT INTO public."user" VALUES ('U946ae258c4b5', '2024-04-19 02:22:28.762991+00', '2024-07-09 12:54:29.214478+00', '', '', false, 'k6iqKNuutNA-Ne9D5SnyFKE1imHfahjQKUGSiXaC-BM');
INSERT INTO public."user" VALUES ('U6eab54d64086', '2024-04-19 02:22:36.063283+00', '2024-07-09 12:54:29.214478+00', '', '', false, 'kcmKYnRWoMV-K7_qQf5wGcCfOyErOVdzXwaL1keQl98');
INSERT INTO public."user" VALUES ('U4ff50cbb890f', '2024-04-19 02:22:45.79485+00', '2024-07-09 12:54:29.214478+00', '', '', false, 'C2WwdFGsUTkDPo3DwOiRiosQb0-Aby011lolmUdzhsY');
INSERT INTO public."user" VALUES ('U1779c42930af', '2024-04-19 02:23:43.744527+00', '2024-07-09 12:54:29.214478+00', '', '', false, 'So1fLTn9UhJAcobqHHY9bvFpUAfUHLsxh1kgzAdkSnM');
INSERT INTO public."user" VALUES ('Ufca294ffe3a5', '2024-04-19 02:24:13.376236+00', '2024-07-09 12:54:29.214478+00', '', '', false, 'h5QEG_7e_1eWRRqRUBdY7Sm_qTL3Xsr4LQ-cl-c4KuQ');
INSERT INTO public."user" VALUES ('Uc244d6132650', '2024-04-19 02:24:15.555704+00', '2024-07-09 12:54:29.214478+00', '', '', false, 'x5-giD5v3d-PlyE-ppiIsxE135SfaYf0pKyKKmkeQ0I');
INSERT INTO public."user" VALUES ('U5f148383594f', '2024-04-19 02:24:27.049116+00', '2024-07-09 12:54:29.214478+00', '', '', false, 'ReyAgQQu6uN7Bh2qD4y2zUt0D63sdAwd0wldyp4iTFA');
INSERT INTO public."user" VALUES ('U4db49066d45a', '2024-04-19 02:24:29.229088+00', '2024-07-09 12:54:29.214478+00', '', '', false, 'dDsCf3iRhgUdRD3Ak9aknRl0nvylkvfexBLczCbrKGs');
INSERT INTO public."user" VALUES ('U118afa836f11', '2024-04-19 02:24:52.624083+00', '2024-07-09 12:54:29.214478+00', '', '', false, 'osFQDuGQ1znoMfl4pdVEradtmL0bsA15-YymTRFlPpk');
INSERT INTO public."user" VALUES ('U146915ad287e', '2024-04-23 15:47:33.855585+00', '2024-07-09 12:54:29.214478+00', '', '', false, 'GXNEdt4UmrGuUjounNIiMTgupim8JEtc8wVFG9dcP3o');
INSERT INTO public."user" VALUES ('U6727ddef0614', '2024-04-23 15:47:58.222129+00', '2024-07-09 12:54:29.214478+00', '', '', false, 'RmwR3ZKAMVzXDgsiqKyNV6bxdOEy2WZxJ13Un8o9y8A');
INSERT INTO public."user" VALUES ('U526c52711601', '2024-04-23 15:50:14.318007+00', '2024-07-09 12:54:29.214478+00', '', '', false, 'okP5B2QkZZfA_nLU2BxC1KnHO_j-5P2nOxh7JoDshl0');
INSERT INTO public."user" VALUES ('U28f934dc948e', '2024-04-23 16:17:14.745461+00', '2024-07-09 12:54:29.214478+00', '', '', false, 'yfptQ7IPgpBZ8lRa1fKiZJQ4Bl69-qiYdC7bB-VkP_g');
INSERT INTO public."user" VALUES ('U1e5391821528', '2024-04-29 06:02:23.157404+00', '2024-07-09 12:54:29.214478+00', '', '', false, 'TIlcQjxvCro5_k-OEfoTI564srAcQ1Pz7KtAn-oZ-ao');
INSERT INTO public."user" VALUES ('U00ace0c36154', '2024-04-29 06:02:26.464245+00', '2024-07-09 12:54:29.214478+00', '', '', false, 'nWQbW1efMTSc1BqIVI1Pqw2-jGT7whldRmkH-_O2FKU');
INSERT INTO public."user" VALUES ('U864ef33f7249', '2024-05-24 01:19:59.044067+00', '2024-07-09 12:54:29.214478+00', '', '', false, 'wjGAgpXAkV8GnyHekM_wRZZYJloaGm8NMQMfE2Gm_SY');
INSERT INTO public."user" VALUES ('U82a1a138c984', '2024-07-16 12:32:15.184173+00', '2024-07-16 12:32:15.184173+00', '', '', false, 'nXFi6SBmVc5NV9pjao5sYmmrizBys_xU9caQpmdbjzk');
INSERT INTO public."user" VALUES ('U95f3426b8e5d', '2024-07-05 14:48:31.14837+00', '2024-07-17 14:10:52.424343+00', 'Alter Ego', 'Some description', true, 'KVqolpoPKRfKBb9R2sMwzg4ySFJHBb_h9qo5EagjMV0');
INSERT INTO public."user" VALUES ('U07ba25a99574', '2024-08-06 13:43:12.656361+00', '2024-08-06 13:43:12.656361+00', '', '', false, 'jsy7sm-DYIL2yfwLCpu6gdALaRPQY7Rl4lcf9O01Zfg');
INSERT INTO public."user" VALUES ('U03f52ca325d0', '2024-08-09 01:07:07.186827+00', '2024-08-09 01:07:07.186827+00', '', '', false, 'g5cyMyXDuXVXsvHJQqf_dB9PClijSdCHVcD_ZZMu_5s');
INSERT INTO public."user" VALUES ('U1f8687088899', '2024-08-09 01:07:29.850142+00', '2024-08-09 01:07:29.850142+00', '', '', false, 'ggP8SCnORzarudGClgblXViOdCDTc1iv81LpnkG6H_U');
INSERT INTO public."user" VALUES ('Ue28a49e571f5', '2024-08-09 01:07:30.565608+00', '2024-08-09 01:07:30.565608+00', '', '', false, 'iIKK_qULbQ6x5IxCD_zgu2ZyHQ8aytHPLhFXAb2xsEc');
INSERT INTO public."user" VALUES ('U27b1b14972c6', '2024-08-12 23:06:51.640705+00', '2024-08-12 23:06:51.640705+00', '', '', false, 'Ce88F9qOaxUHR1vI-80TLKUJ3tDG-B8QeszNW2MXO98');
INSERT INTO public."user" VALUES ('Ud98c9735d1e0', '2024-08-12 23:07:01.989387+00', '2024-08-12 23:07:01.989387+00', '', '', false, 'Ez8fjBZ_UxL562O35bnGV2VFIWcEZKBSHb5Vo9co7IE');
INSERT INTO public."user" VALUES ('U05c63e1de554', '2024-08-12 23:11:48.133526+00', '2024-08-12 23:11:48.133526+00', '', '', false, 'IAqmIl04wPpVdTyhpCLSMRft5_qcNr_J-SXw0HioMPQ');
INSERT INTO public."user" VALUES ('U85af6afd0809', '2024-08-12 23:13:13.703868+00', '2024-08-12 23:13:13.703868+00', '', '', false, 'fTKSzSGmLD4z08ig_ooenp01BrqWgKdpyj21Kn0OfOw');
INSERT INTO public."user" VALUES ('U32f453dcedfc', '2024-08-20 22:32:19.140228+00', '2024-08-20 22:32:19.140228+00', '', '', false, 'NE7MN0ZyxTrAah5IMII8jTCUi7FpKaXrkPaY9gJuebc');
INSERT INTO public."user" VALUES ('U6eba124741ce', '2024-08-20 22:38:37.514343+00', '2024-08-20 22:38:37.514343+00', '', '', false, 'tdI8k3rbzeCR7YxiQFfPs289VMuQGb3XX_2_h3ON9cc');
INSERT INTO public."user" VALUES ('Uee84b59d1fe1', '2024-08-20 22:41:17.153928+00', '2024-08-20 22:41:17.153928+00', '', '', false, 'sVpdRnY4_o5zdQgJ_hN5Y1OYXFtOYJ4oMJrG_PpiXcU');
INSERT INTO public."user" VALUES ('Ua0ac51c2e156', '2024-08-21 22:24:32.720337+00', '2024-08-21 22:24:32.720337+00', '', '', false, '8mSmu6DgHndFn-WVVe8Yj1rACLF2tnb3nlND_E-Lucw');
INSERT INTO public."user" VALUES ('Ub2e0bee5b4d2', '2024-08-24 17:19:37.756827+00', '2024-08-24 17:19:37.756827+00', '', '', false, 'MJRlmU71Bv1QKVNg3f43a0jidVFId6xYjMl4Oz9LLLA');
INSERT INTO public."user" VALUES ('U4b8040b1efd9', '2024-08-30 12:31:52.215516+00', '2024-08-30 12:31:52.215516+00', '', '', false, 'mA1G4hWfi6w5J0iDG7vkhhsQCzX1MnBqddZ6CUrOufc');
INSERT INTO public."user" VALUES ('U13f833b527aa', '2024-09-07 22:01:20.362305+00', '2024-09-07 22:01:20.362305+00', '', '', false, 'p7PBDJedeXKFyvKZ6J29z6L9nTCUf0PRnVi6VmaUCOM');
INSERT INTO public."user" VALUES ('Ue9e793f3ad14', '2024-09-07 22:01:47.710057+00', '2024-09-07 22:02:05.689601+00', 'Wait4wasm', '', false, 'GV9HzXXEr0-h-kPi7L3XM3DH4DEdmY0dCxgFbv8-ATo');
INSERT INTO public."user" VALUES ('U33fc8f104565', '2024-09-08 15:10:12.496448+00', '2024-09-08 15:10:12.496448+00', '', '', false, 'y7ZWMtlYvmNRFetvwfihjyHdxyA6Xd69lmuwSGNc3MY');


--
-- Data for Name: user_context; Type: TABLE DATA; Schema: public; Owner: postgres
--

INSERT INTO public.user_context VALUES ('Ub01f4ad1b03f', 'Discourse');
INSERT INTO public.user_context VALUES ('Ub01f4ad1b03f', 'Fatum');
INSERT INTO public.user_context VALUES ('U0ae9f5d0bf02', 'tentura-test');
INSERT INTO public.user_context VALUES ('U77a03e9a08af', 'tentura-test');
INSERT INTO public.user_context VALUES ('U77a03e9a08af', 'bla');
INSERT INTO public.user_context VALUES ('U77a03e9a08af', 'Fatum');
INSERT INTO public.user_context VALUES ('U77a03e9a08af', 'Glamour');
INSERT INTO public.user_context VALUES ('Uf82dbb4708ba', 'happiness');
INSERT INTO public.user_context VALUES ('U0ae9f5d0bf02', 'Fatum');
INSERT INTO public.user_context VALUES ('Ub47d8c364c9e', 'Fatum');
INSERT INTO public.user_context VALUES ('Uf82dbb4708ba', 'Volunteer');
INSERT INTO public.user_context VALUES ('U9de057150efc', 'tetset');
INSERT INTO public.user_context VALUES ('U9de057150efc', 'test2222');
INSERT INTO public.user_context VALUES ('Ub4b46ee7a5e4', 'Magic');
INSERT INTO public.user_context VALUES ('U3ea0a229ad85', 'Photo');
INSERT INTO public.user_context VALUES ('U163b54808a6b', 'Cats');
INSERT INTO public.user_context VALUES ('U55272fd6c264', 'cat');
INSERT INTO public.user_context VALUES ('U55272fd6c264', 'bengal');
INSERT INTO public.user_context VALUES ('U55272fd6c264', 'game');
INSERT INTO public.user_context VALUES ('U5cd67e57a766', 'Fatum');
INSERT INTO public.user_context VALUES ('Ufe8cdd16cc19', 'Fatum');
INSERT INTO public.user_context VALUES ('Ub01f4ad1b03f', 'Glamour');
INSERT INTO public.user_context VALUES ('Ub01f4ad1b03f', 'Ampir');


--
-- Data for Name: user_updates; Type: TABLE DATA; Schema: public; Owner: postgres
--

INSERT INTO public.user_updates VALUES ('Ub01f4ad1b03f', '\x69696969696969690a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a6565656565656565020202020202020234343434343434348989898989898989292929292929292908080808080808082121212121212121b0b0b0b0b0b0b0b011111111111111117272727272727272535353535353535300000000000000000202020202020202');


--
-- Data for Name: vote_beacon; Type: TABLE DATA; Schema: public; Owner: postgres
--

INSERT INTO public.vote_beacon VALUES ('U389f9f24b31c', 'B25c85fe0df2d', 5, '2023-09-26 10:56:27.21524+00', '2023-09-26 10:56:27.21524+00');
INSERT INTO public.vote_beacon VALUES ('Ue55b928fa8dd', 'Bed5126bc655d', 3, '2023-12-21 22:02:07.215582+00', '2023-12-21 22:02:07.506937+00');
INSERT INTO public.vote_beacon VALUES ('U57b6f30fc663', 'Bed5126bc655d', -1, '2023-12-23 21:53:30.243529+00', '2023-12-23 21:54:11.89482+00');
INSERT INTO public.vote_beacon VALUES ('U0c17798eaab4', 'B3c467fb437b2', 2, '2023-09-26 10:56:27.21524+00', '2023-09-26 10:56:27.21524+00');
INSERT INTO public.vote_beacon VALUES ('U9a2c85753a6d', 'B3b3f2ecde430', 6, '2023-09-26 10:56:27.21524+00', '2023-09-26 10:56:27.21524+00');
INSERT INTO public.vote_beacon VALUES ('Uf5096f6ab14e', 'B60d725feca77', 8, '2023-09-26 10:56:27.21524+00', '2023-09-26 10:56:27.21524+00');
INSERT INTO public.vote_beacon VALUES ('U9e42f6dab85a', 'Bad1c69de7837', 3, '2023-09-26 10:56:27.21524+00', '2023-09-26 10:56:27.21524+00');
INSERT INTO public.vote_beacon VALUES ('Ud7002ae5a86c', 'B75a44a52fa29', -2, '2023-10-08 12:53:38.646917+00', '2023-10-08 16:27:27.113924+00');
INSERT INTO public.vote_beacon VALUES ('U57b6f30fc663', 'B30bf91bf5845', 1, '2023-12-23 21:54:38.729724+00', '2024-02-02 19:31:50.337266+00');
INSERT INTO public.vote_beacon VALUES ('Uaa4e2be7a87a', 'B7f628ad203b5', 9, '2023-09-26 10:56:27.21524+00', '2023-09-26 10:56:27.21524+00');
INSERT INTO public.vote_beacon VALUES ('Uef7fbf45ef11', 'B7f628ad203b5', 7, '2023-09-26 10:56:27.21524+00', '2023-09-26 10:56:27.21524+00');
INSERT INTO public.vote_beacon VALUES ('Uf2b0a6b1d423', 'B5eb4c6be535a', 5, '2023-09-26 10:56:27.21524+00', '2023-09-26 10:56:27.21524+00');
INSERT INTO public.vote_beacon VALUES ('Uf2b0a6b1d423', 'Bb78026d99388', 9, '2023-09-26 10:56:27.21524+00', '2023-09-26 10:56:27.21524+00');
INSERT INTO public.vote_beacon VALUES ('U1c285703fc63', 'Bad1c69de7837', 7, '2023-09-26 10:56:27.21524+00', '2023-09-26 10:56:27.21524+00');
INSERT INTO public.vote_beacon VALUES ('Ue6cc7bfa0efd', 'Bed5126bc655d', 7, '2024-02-08 15:57:58.493054+00', '2024-02-08 15:57:59.492231+00');
INSERT INTO public.vote_beacon VALUES ('U9605bd4d1218', 'B75a44a52fa29', 4, '2023-10-09 19:34:27.188377+00', '2023-10-09 19:34:27.6472+00');
INSERT INTO public.vote_beacon VALUES ('U80e22da6d8c4', 'B45d72e29f004', 3, '2023-09-26 10:56:27.21524+00', '2023-09-26 10:56:27.21524+00');
INSERT INTO public.vote_beacon VALUES ('Ub93799d9400e', 'B73a44e2bbd44', 5, '2023-10-09 09:08:04.088507+00', '2023-10-09 09:08:04.65115+00');
INSERT INTO public.vote_beacon VALUES ('Ub93799d9400e', 'B491d307dfe01', 2, '2023-10-09 11:01:48.313324+00', '2023-10-09 11:01:48.44936+00');
INSERT INTO public.vote_beacon VALUES ('U09cf1f359454', 'B73a44e2bbd44', 1, '2023-11-08 06:45:51.876394+00', '2023-11-08 06:45:51.876394+00');
INSERT INTO public.vote_beacon VALUES ('Ue6cc7bfa0efd', 'B5e7178dd70bb', -7, '2024-02-08 15:58:05.622728+00', '2024-02-08 15:58:10.174935+00');
INSERT INTO public.vote_beacon VALUES ('U01814d1ec9ff', 'B9c01ce5718d1', 10, '2023-10-05 14:02:02.674397+00', '2023-10-05 14:02:05.204124+00');
INSERT INTO public.vote_beacon VALUES ('U09cf1f359454', 'B310b66ab31fb', 1, '2023-11-08 06:46:32.74184+00', '2023-11-08 06:46:32.74184+00');
INSERT INTO public.vote_beacon VALUES ('U09cf1f359454', 'Be2b46c17f1da', -1, '2023-11-08 06:46:45.696688+00', '2023-11-08 06:46:45.696688+00');
INSERT INTO public.vote_beacon VALUES ('U01814d1ec9ff', 'B63fbe1427d09', -3, '2023-10-06 10:11:46.602687+00', '2023-10-06 10:11:46.898825+00');
INSERT INTO public.vote_beacon VALUES ('U01814d1ec9ff', 'B491d307dfe01', -1, '2023-10-06 10:12:03.295462+00', '2023-10-06 10:12:04.304093+00');
INSERT INTO public.vote_beacon VALUES ('U02fbd7c8df4c', 'B75a44a52fa29', 7, '2023-10-08 16:49:47.013437+00', '2023-10-08 16:49:50.874021+00');
INSERT INTO public.vote_beacon VALUES ('U8a78048d60f7', 'B63fbe1427d09', -1, '2023-10-06 21:30:12.279774+00', '2023-10-20 06:47:44.273297+00');
INSERT INTO public.vote_beacon VALUES ('U9605bd4d1218', 'B9c01ce5718d1', 2, '2023-10-09 19:34:41.215124+00', '2023-10-09 19:34:41.367126+00');
INSERT INTO public.vote_beacon VALUES ('U02fbd7c8df4c', 'Bad1c69de7837', -5, '2023-10-08 16:54:31.324886+00', '2023-10-08 16:54:31.91544+00');
INSERT INTO public.vote_beacon VALUES ('Uc3c31b8a022f', 'Bb78026d99388', 1, '2023-10-01 09:32:57.248097+00', '2023-10-01 09:32:57.248097+00');
INSERT INTO public.vote_beacon VALUES ('U7a8d8324441d', 'B3b3f2ecde430', 9, '2023-09-26 10:56:27.21524+00', '2023-10-01 09:32:57.248097+00');
INSERT INTO public.vote_beacon VALUES ('Uaa4e2be7a87a', 'B0e230e9108dd', 2, '2023-10-01 09:32:57.248097+00', '2023-10-01 09:32:57.248097+00');
INSERT INTO public.vote_beacon VALUES ('U389f9f24b31c', 'Bad1c69de7837', 2, '2023-10-01 09:32:57.248097+00', '2023-10-01 09:32:57.248097+00');
INSERT INTO public.vote_beacon VALUES ('Uadeb43da4abb', 'B0e230e9108dd', 4, '2023-10-01 09:32:57.248097+00', '2023-10-01 09:32:57.248097+00');
INSERT INTO public.vote_beacon VALUES ('Uc1158424318a', 'B7f628ad203b5', 8, '2023-10-01 09:34:20.264693+00', '2023-10-01 09:34:20.264693+00');
INSERT INTO public.vote_beacon VALUES ('U26aca0e369c7', 'Be2b46c17f1da', 7, '2023-10-01 09:34:20.264693+00', '2023-10-01 09:34:20.264693+00');
INSERT INTO public.vote_beacon VALUES ('U0c17798eaab4', 'B0e230e9108dd', 3, '2023-10-01 09:34:20.264693+00', '2023-10-01 09:34:20.264693+00');
INSERT INTO public.vote_beacon VALUES ('Udece0afd9a8b', 'Bad1c69de7837', 9, '2023-10-01 09:34:20.264693+00', '2023-10-01 09:34:20.264693+00');
INSERT INTO public.vote_beacon VALUES ('Uef7fbf45ef11', 'B0e230e9108dd', -1, '2023-10-01 09:39:07.95166+00', '2023-10-01 09:39:07.95166+00');
INSERT INTO public.vote_beacon VALUES ('U7a8d8324441d', 'B5eb4c6be535a', 1, '2023-10-01 09:39:07.95166+00', '2023-10-01 09:39:07.95166+00');
INSERT INTO public.vote_beacon VALUES ('Uc3c31b8a022f', 'B3c467fb437b2', -1, '2023-10-01 09:44:31.96176+00', '2023-10-01 09:44:31.96176+00');
INSERT INTO public.vote_beacon VALUES ('U016217c34c6e', 'B3c467fb437b2', 2, '2023-10-01 09:47:53.067521+00', '2023-10-01 09:47:53.067521+00');
INSERT INTO public.vote_beacon VALUES ('Uf5096f6ab14e', 'B3b3f2ecde430', 3, '2023-10-01 09:49:09.834378+00', '2023-10-01 09:49:09.834378+00');
INSERT INTO public.vote_beacon VALUES ('Uc3c31b8a022f', 'B45d72e29f004', 3, '2023-10-01 09:53:34.906577+00', '2023-10-01 09:53:34.906577+00');
INSERT INTO public.vote_beacon VALUES ('U7a8d8324441d', 'Be2b46c17f1da', 5, '2023-10-01 09:57:31.153037+00', '2023-10-01 09:57:31.153037+00');
INSERT INTO public.vote_beacon VALUES ('U9a2c85753a6d', 'B3c467fb437b2', 9, '2023-10-01 09:57:37.138627+00', '2023-10-01 09:57:37.138627+00');
INSERT INTO public.vote_beacon VALUES ('U09cf1f359454', 'Bad1c69de7837', -1, '2023-11-08 06:46:49.783005+00', '2023-11-08 06:46:49.783005+00');
INSERT INTO public.vote_beacon VALUES ('U09cf1f359454', 'B8a531802473b', -1, '2023-11-08 06:46:55.277375+00', '2023-11-08 06:46:55.277375+00');
INSERT INTO public.vote_beacon VALUES ('U09cf1f359454', 'B45d72e29f004', -1, '2023-11-08 06:46:58.025942+00', '2023-11-08 06:46:58.025942+00');
INSERT INTO public.vote_beacon VALUES ('U9605bd4d1218', 'B8a531802473b', 2, '2023-10-09 19:34:42.593584+00', '2023-10-09 19:34:42.739428+00');
INSERT INTO public.vote_beacon VALUES ('U09cf1f359454', 'B60d725feca77', -1, '2023-11-08 06:47:00.536206+00', '2023-11-08 06:47:00.536206+00');
INSERT INTO public.vote_beacon VALUES ('U09cf1f359454', 'B3c467fb437b2', -1, '2023-11-08 06:47:04.647778+00', '2023-11-08 06:47:04.647778+00');
INSERT INTO public.vote_beacon VALUES ('U01814d1ec9ff', 'B8a531802473b', 8, '2023-10-04 13:13:40.070494+00', '2023-10-04 13:13:41.080585+00');
INSERT INTO public.vote_beacon VALUES ('U09cf1f359454', 'B5a1c1d3d0140', -1, '2023-11-08 06:47:05.514372+00', '2023-11-08 06:47:05.514372+00');
INSERT INTO public.vote_beacon VALUES ('U6661263fb410', 'B75a44a52fa29', 3, '2023-10-08 16:28:35.560094+00', '2023-10-08 16:59:22.617239+00');
INSERT INTO public.vote_beacon VALUES ('U9605bd4d1218', 'B5a1c1d3d0140', 2, '2023-10-09 19:34:44.408809+00', '2023-10-09 19:34:44.570107+00');
INSERT INTO public.vote_beacon VALUES ('U01814d1ec9ff', 'Bd7a8bfcf3337', 3, '2023-10-08 17:00:05.650026+00', '2023-10-08 17:00:06.052436+00');
INSERT INTO public.vote_beacon VALUES ('U09cf1f359454', 'B3b3f2ecde430', -1, '2023-11-08 06:47:07.685868+00', '2023-11-08 06:47:07.685868+00');
INSERT INTO public.vote_beacon VALUES ('Ud5b22ebf52f2', 'B310b66ab31fb', 1, '2023-10-08 19:46:47.746201+00', '2023-10-08 19:46:47.746201+00');
INSERT INTO public.vote_beacon VALUES ('U01814d1ec9ff', 'B3b3f2ecde430', -3, '2023-10-04 13:13:29.989553+00', '2023-10-04 13:13:31.20901+00');
INSERT INTO public.vote_beacon VALUES ('U09cf1f359454', 'B0e230e9108dd', -1, '2023-11-08 06:47:09.346095+00', '2023-11-08 06:47:09.346095+00');
INSERT INTO public.vote_beacon VALUES ('U09cf1f359454', 'Bb78026d99388', -1, '2023-11-08 06:47:11.809317+00', '2023-11-08 06:47:11.809317+00');
INSERT INTO public.vote_beacon VALUES ('U01814d1ec9ff', 'B5a1c1d3d0140', 5, '2023-10-04 13:13:27.699206+00', '2023-10-04 13:13:37.248109+00');
INSERT INTO public.vote_beacon VALUES ('U9605bd4d1218', 'Bd7a8bfcf3337', 1, '2023-10-09 19:34:46.311634+00', '2023-10-09 19:34:46.311634+00');
INSERT INTO public.vote_beacon VALUES ('U09cf1f359454', 'B5eb4c6be535a', -1, '2023-11-08 06:47:13.850365+00', '2023-11-08 06:47:13.850365+00');
INSERT INTO public.vote_beacon VALUES ('U09cf1f359454', 'B25c85fe0df2d', -1, '2023-11-08 06:47:15.697056+00', '2023-11-08 06:47:15.697056+00');
INSERT INTO public.vote_beacon VALUES ('U09cf1f359454', 'B3f6f837bc345', 1, '2023-11-08 06:47:18.761143+00', '2023-11-08 06:47:18.761143+00');
INSERT INTO public.vote_beacon VALUES ('U09cf1f359454', 'B63fbe1427d09', -1, '2023-11-08 06:47:20.786321+00', '2023-11-08 06:47:20.786321+00');
INSERT INTO public.vote_beacon VALUES ('U6d2f25cc4264', 'Ba3c4a280657d', 2, '2023-10-10 01:29:51.39271+00', '2023-10-10 01:29:51.621231+00');
INSERT INTO public.vote_beacon VALUES ('U6d2f25cc4264', 'B491d307dfe01', 3, '2023-10-08 17:10:29.209903+00', '2023-10-10 01:29:26.257805+00');
INSERT INTO public.vote_beacon VALUES ('Ub93799d9400e', 'B75a44a52fa29', 5, '2023-10-09 09:06:39.681393+00', '2023-10-09 09:06:40.390326+00');
INSERT INTO public.vote_beacon VALUES ('U682c3380036f', 'B75a44a52fa29', 2, '2023-10-10 11:02:08.545119+00', '2023-10-10 11:02:08.689987+00');
INSERT INTO public.vote_beacon VALUES ('U6d2f25cc4264', 'B7f628ad203b5', -1, '2023-10-08 17:06:41.483879+00', '2023-10-10 01:29:31.64058+00');
INSERT INTO public.vote_beacon VALUES ('U01814d1ec9ff', 'Bb78026d99388', -11, '2023-10-04 17:12:59.866121+00', '2023-10-04 17:13:03.209842+00');
INSERT INTO public.vote_beacon VALUES ('U6d2f25cc4264', 'B79efabc4d8bf', 2, '2023-10-10 01:29:37.065414+00', '2023-10-10 01:29:37.624394+00');
INSERT INTO public.vote_beacon VALUES ('Ub93799d9400e', 'B9c01ce5718d1', 5, '2023-10-09 09:05:49.484445+00', '2023-10-10 10:53:17.599458+00');
INSERT INTO public.vote_beacon VALUES ('U6d2f25cc4264', 'Bad1c69de7837', -1, '2023-10-10 01:29:48.838975+00', '2023-10-10 01:29:48.838975+00');
INSERT INTO public.vote_beacon VALUES ('U6240251593cd', 'B9c01ce5718d1', -4, '2023-10-10 11:06:15.243949+00', '2023-10-10 11:06:15.653456+00');
INSERT INTO public.vote_beacon VALUES ('U682c3380036f', 'Bf34ee3bfc12b', 4, '2023-10-10 10:58:09.676778+00', '2023-10-10 10:58:10.124075+00');
INSERT INTO public.vote_beacon VALUES ('U6240251593cd', 'B75a44a52fa29', 4, '2023-10-10 10:59:10.35401+00', '2023-10-10 10:59:10.78901+00');
INSERT INTO public.vote_beacon VALUES ('Ua12e78308f49', 'B75a44a52fa29', 4, '2023-10-10 16:23:26.06142+00', '2023-10-10 16:23:27.218871+00');
INSERT INTO public.vote_beacon VALUES ('Ud9df8116deba', 'B310b66ab31fb', 1, '2023-10-18 19:47:47.404676+00', '2023-10-18 19:47:47.404676+00');
INSERT INTO public.vote_beacon VALUES ('U8a78048d60f7', 'B499bfc56e77b', -1, '2023-10-19 14:34:30.94709+00', '2023-10-19 14:34:30.94709+00');
INSERT INTO public.vote_beacon VALUES ('U8a78048d60f7', 'Be2b46c17f1da', -1, '2023-10-19 14:34:16.112185+00', '2023-10-20 06:47:43.300174+00');
INSERT INTO public.vote_beacon VALUES ('U6d2f25cc4264', 'Bfefe4e25c870', 4, '2023-10-10 01:29:42.624157+00', '2023-10-19 20:43:18.825897+00');
INSERT INTO public.vote_beacon VALUES ('U1e41b5f3adff', 'B310b66ab31fb', 5, '2023-10-19 22:20:10.842356+00', '2023-10-19 22:47:48.043065+00');
INSERT INTO public.vote_beacon VALUES ('U6d2f25cc4264', 'B9c01ce5718d1', 4, '2023-10-10 01:29:44.890125+00', '2023-10-19 22:59:53.310265+00');
INSERT INTO public.vote_beacon VALUES ('U8a78048d60f7', 'B9c01ce5718d1', 3, '2023-10-20 06:46:36.277807+00', '2023-10-20 06:46:39.966631+00');
INSERT INTO public.vote_beacon VALUES ('U8a78048d60f7', 'Bfefe4e25c870', 3, '2023-10-20 06:46:53.310175+00', '2023-10-20 06:46:54.831922+00');
INSERT INTO public.vote_beacon VALUES ('U8a78048d60f7', 'B3c467fb437b2', -1, '2023-10-19 14:34:15.244883+00', '2023-10-20 06:47:46.876004+00');
INSERT INTO public.vote_beacon VALUES ('U8a78048d60f7', 'B491d307dfe01', 3, '2023-10-20 06:46:57.62004+00', '2023-10-20 06:46:58.704984+00');
INSERT INTO public.vote_beacon VALUES ('U8a78048d60f7', 'Bd49e3dac97b0', -1, '2023-10-20 06:47:13.563019+00', '2023-10-20 06:47:13.563019+00');
INSERT INTO public.vote_beacon VALUES ('U8a78048d60f7', 'Bf3a0a1165271', -1, '2023-10-20 06:47:15.228123+00', '2023-10-20 06:47:15.228123+00');
INSERT INTO public.vote_beacon VALUES ('U8a78048d60f7', 'B8a531802473b', -1, '2023-10-20 06:47:17.536566+00', '2023-10-20 06:47:17.536566+00');
INSERT INTO public.vote_beacon VALUES ('U8a78048d60f7', 'Bdf39d0e1daf5', -1, '2023-10-20 06:47:20.109309+00', '2023-10-20 06:47:20.109309+00');
INSERT INTO public.vote_beacon VALUES ('U8a78048d60f7', 'B7f628ad203b5', -1, '2023-10-19 14:34:13.472993+00', '2023-10-20 06:47:45.943078+00');
INSERT INTO public.vote_beacon VALUES ('U8a78048d60f7', 'B45d72e29f004', -1, '2023-10-20 06:47:48.983673+00', '2023-10-20 06:47:48.983673+00');
INSERT INTO public.vote_beacon VALUES ('U6d2f25cc4264', 'Bdf39d0e1daf5', -1, '2023-10-08 17:08:05.645202+00', '2023-11-03 02:33:30.160137+00');
INSERT INTO public.vote_beacon VALUES ('U6d2f25cc4264', 'B63fbe1427d09', -1, '2023-10-05 11:17:52.855079+00', '2023-11-03 02:27:59.26423+00');
INSERT INTO public.vote_beacon VALUES ('U8a78048d60f7', 'B60d725feca77', -1, '2023-10-20 06:47:52.161745+00', '2023-10-20 06:47:52.161745+00');
INSERT INTO public.vote_beacon VALUES ('U8a78048d60f7', 'Bb78026d99388', -1, '2023-10-20 06:47:55.234508+00', '2023-10-20 06:47:55.234508+00');
INSERT INTO public.vote_beacon VALUES ('U8a78048d60f7', 'B5eb4c6be535a', -1, '2023-10-20 06:47:57.401033+00', '2023-10-20 06:47:57.401033+00');
INSERT INTO public.vote_beacon VALUES ('U8a78048d60f7', 'B3b3f2ecde430', -1, '2023-10-20 06:48:01.863457+00', '2023-10-20 06:48:01.863457+00');
INSERT INTO public.vote_beacon VALUES ('U8a78048d60f7', 'B0e230e9108dd', -1, '2023-10-20 06:48:04.570045+00', '2023-10-20 06:48:04.570045+00');
INSERT INTO public.vote_beacon VALUES ('U8a78048d60f7', 'B25c85fe0df2d', -1, '2023-10-20 06:48:07.340391+00', '2023-10-20 06:48:07.340391+00');
INSERT INTO public.vote_beacon VALUES ('U8a78048d60f7', 'Ba3c4a280657d', 3, '2023-10-20 06:49:00.050399+00', '2023-10-20 06:49:00.688657+00');
INSERT INTO public.vote_beacon VALUES ('U0cd6bd2dde4f', 'B7f628ad203b5', 1, '2023-10-30 17:21:11.777492+00', '2023-10-30 17:21:11.777492+00');
INSERT INTO public.vote_beacon VALUES ('U8a78048d60f7', 'B75a44a52fa29', 3, '2023-10-20 06:49:10.154623+00', '2023-10-20 06:49:11.40249+00');
INSERT INTO public.vote_beacon VALUES ('U09cf1f359454', 'Bdf39d0e1daf5', -1, '2023-11-08 06:47:23.031848+00', '2023-11-08 06:47:23.031848+00');
INSERT INTO public.vote_beacon VALUES ('U09cf1f359454', 'Ba5d64165e5d5', -1, '2023-11-08 06:47:25.073996+00', '2023-11-08 06:47:25.073996+00');
INSERT INTO public.vote_beacon VALUES ('U09cf1f359454', 'Bf3a0a1165271', -1, '2023-11-08 06:47:27.377193+00', '2023-11-08 06:47:27.377193+00');
INSERT INTO public.vote_beacon VALUES ('U09cf1f359454', 'B4f14b223b56d', -1, '2023-11-08 06:47:31.358332+00', '2023-11-08 06:47:31.358332+00');
INSERT INTO public.vote_beacon VALUES ('U09cf1f359454', 'Bd49e3dac97b0', -1, '2023-11-08 06:47:32.457278+00', '2023-11-08 06:47:32.457278+00');
INSERT INTO public.vote_beacon VALUES ('U09cf1f359454', 'Be29b4af3f7a5', -1, '2023-11-08 06:47:34.543354+00', '2023-11-08 06:47:34.543354+00');
INSERT INTO public.vote_beacon VALUES ('U09cf1f359454', 'Be5bb2f3d56cb', -1, '2023-11-08 06:47:36.43539+00', '2023-11-08 06:47:36.43539+00');
INSERT INTO public.vote_beacon VALUES ('U09cf1f359454', 'B499bfc56e77b', -1, '2023-11-08 06:47:40.8891+00', '2023-11-08 06:47:40.8891+00');
INSERT INTO public.vote_beacon VALUES ('U8aa2e2623fa5', 'B9c01ce5718d1', -2, '2023-11-19 12:29:18.633269+00', '2023-11-19 12:31:14.730115+00');
INSERT INTO public.vote_beacon VALUES ('U09cf1f359454', 'B75a44a52fa29', 1, '2023-11-19 12:39:49.925937+00', '2023-11-19 12:39:49.925937+00');
INSERT INTO public.vote_beacon VALUES ('U1bcba4fd7175', 'B4f00e7813add', 3, '2023-11-08 10:02:33.671577+00', '2023-11-08 10:02:37.631023+00');
INSERT INTO public.vote_beacon VALUES ('U0cd6bd2dde4f', 'B92e4a185c654', 1, '2023-10-30 17:21:16.002482+00', '2023-10-30 17:21:16.002482+00');
INSERT INTO public.vote_beacon VALUES ('U8a78048d60f7', 'B92e4a185c654', 3, '2023-10-20 06:49:51.402367+00', '2023-10-20 06:49:52.684039+00');
INSERT INTO public.vote_beacon VALUES ('U3c63a9b6115a', 'B9c01ce5718d1', 3, '2023-10-27 18:04:02.690651+00', '2023-10-27 18:04:08.923087+00');
INSERT INTO public.vote_beacon VALUES ('U8a78048d60f7', 'B310b66ab31fb', 4, '2023-10-20 06:49:55.259792+00', '2023-10-20 06:49:56.944991+00');
INSERT INTO public.vote_beacon VALUES ('U8a78048d60f7', 'B10d3f548efc4', 3, '2023-10-20 06:50:30.650978+00', '2023-10-20 06:50:31.57806+00');
INSERT INTO public.vote_beacon VALUES ('U1bcba4fd7175', 'B70df5dbab8c3', 2, '2023-11-08 10:04:13.893565+00', '2023-11-08 10:04:14.047995+00');
INSERT INTO public.vote_beacon VALUES ('U3c63a9b6115a', 'Bad1c69de7837', 2, '2023-10-27 18:04:11.578875+00', '2023-10-27 18:04:11.712118+00');
INSERT INTO public.vote_beacon VALUES ('U8a78048d60f7', 'Bd90a1cf73384', 3, '2023-10-20 06:50:36.570412+00', '2023-10-20 06:50:37.505698+00');
INSERT INTO public.vote_beacon VALUES ('U8a78048d60f7', 'B0a87a669fc28', 3, '2023-10-20 06:50:41.660152+00', '2023-10-20 06:50:42.243536+00');
INSERT INTO public.vote_beacon VALUES ('U8a78048d60f7', 'B19ea554faf29', 3, '2023-10-20 06:50:47.741319+00', '2023-10-20 06:50:50.164166+00');
INSERT INTO public.vote_beacon VALUES ('U6d2f25cc4264', 'Bb78026d99388', -1, '2023-10-25 02:45:09.977099+00', '2023-11-03 02:33:35.765097+00');
INSERT INTO public.vote_beacon VALUES ('U8a78048d60f7', 'Bb1e3630d2f4a', 3, '2023-10-20 06:50:54.506389+00', '2023-10-20 06:50:55.511292+00');
INSERT INTO public.vote_beacon VALUES ('U77f496546efa', 'B9c01ce5718d1', -1, '2023-11-20 17:50:46.044271+00', '2023-11-20 17:50:46.044271+00');
INSERT INTO public.vote_beacon VALUES ('U8a78048d60f7', 'Bf34ee3bfc12b', 3, '2023-10-20 06:51:04.594471+00', '2023-10-20 06:51:05.592478+00');
INSERT INTO public.vote_beacon VALUES ('Uc35c445325f5', 'B8a531802473b', -5, '2023-10-30 18:41:58.32829+00', '2023-10-30 19:26:13.106489+00');
INSERT INTO public.vote_beacon VALUES ('U1bcba4fd7175', 'Bfefe4e25c870', 5, '2023-11-11 13:55:50.930328+00', '2023-11-11 13:55:51.538305+00');
INSERT INTO public.vote_beacon VALUES ('U3c63a9b6115a', 'B75a44a52fa29', 5, '2023-10-27 18:04:15.583972+00', '2023-10-27 18:04:16.792091+00');
INSERT INTO public.vote_beacon VALUES ('Ud04c89aaf453', 'B73a44e2bbd44', 4, '2023-10-20 18:53:44.690864+00', '2023-10-20 18:53:45.30063+00');
INSERT INTO public.vote_beacon VALUES ('U6d2f25cc4264', 'B5eb4c6be535a', -1, '2023-10-20 20:27:07.671355+00', '2023-10-20 20:27:07.671355+00');
INSERT INTO public.vote_beacon VALUES ('U6d2f25cc4264', 'B8a531802473b', -1, '2023-10-20 20:29:30.459181+00', '2023-10-20 20:29:30.459181+00');
INSERT INTO public.vote_beacon VALUES ('U4f530cfe771e', 'B9c01ce5718d1', 0, '2023-11-20 17:52:53.147117+00', '2023-11-20 17:53:19.800328+00');
INSERT INTO public.vote_beacon VALUES ('U4f530cfe771e', 'B7f628ad203b5', 0, '2023-11-20 17:52:56.208777+00', '2023-11-20 17:53:28.872829+00');
INSERT INTO public.vote_beacon VALUES ('U09cf1f359454', 'B9c01ce5718d1', 2, '2023-11-20 17:29:48.148633+00', '2023-11-20 19:58:00.786605+00');
INSERT INTO public.vote_beacon VALUES ('U09cf1f359454', 'B491d307dfe01', 2, '2023-11-20 17:29:59.94723+00', '2023-11-20 19:58:02.436514+00');
INSERT INTO public.vote_beacon VALUES ('U1bcba4fd7175', 'Bc4addf09b79f', 3, '2023-11-08 10:02:06.224365+00', '2023-11-08 10:02:06.530581+00');
INSERT INTO public.vote_beacon VALUES ('U1bcba4fd7175', 'B0e230e9108dd', -1, '2023-11-21 01:00:06.252346+00', '2023-11-21 01:00:06.252346+00');
INSERT INTO public.vote_beacon VALUES ('U585dfead09c6', 'B9c01ce5718d1', 2, '2023-11-26 00:22:52.428407+00', '2023-11-26 00:23:16.30857+00');
INSERT INTO public.vote_beacon VALUES ('U05e4396e2382', 'Bad1c69de7837', -1, '2023-11-25 23:53:48.861519+00', '2023-11-25 23:53:48.861519+00');
INSERT INTO public.vote_beacon VALUES ('U79466f73dc0c', 'B9c01ce5718d1', -6, '2023-11-24 22:01:24.171716+00', '2023-11-24 22:01:56.490878+00');
INSERT INTO public.vote_beacon VALUES ('U8a78048d60f7', 'Ba5d64165e5d5', -1, '2023-10-20 21:38:29.050602+00', '2023-10-20 21:38:29.050602+00');
INSERT INTO public.vote_beacon VALUES ('Uc35c445325f5', 'B75a44a52fa29', 2, '2023-10-24 16:22:36.442454+00', '2023-10-24 16:22:36.78597+00');
INSERT INTO public.vote_beacon VALUES ('Ucb84c094edba', 'B491d307dfe01', 0, '2023-11-26 12:18:46.611218+00', '2023-11-26 12:18:53.578271+00');
INSERT INTO public.vote_beacon VALUES ('Uc35c445325f5', 'B9c01ce5718d1', 4, '2023-10-24 16:21:32.627435+00', '2023-10-27 17:58:42.748058+00');
INSERT INTO public.vote_beacon VALUES ('U1bcba4fd7175', 'B73a44e2bbd44', 3, '2023-11-11 21:36:04.618665+00', '2023-11-11 21:36:05.222669+00');
INSERT INTO public.vote_beacon VALUES ('U6d2f25cc4264', 'Be2b46c17f1da', -1, '2023-11-03 02:33:43.102247+00', '2023-11-03 02:33:43.102247+00');
INSERT INTO public.vote_beacon VALUES ('U8a78048d60f7', 'Be29b4af3f7a5', -1, '2023-10-30 14:57:57.064059+00', '2023-10-30 14:57:57.064059+00');
INSERT INTO public.vote_beacon VALUES ('U8a78048d60f7', 'B4f14b223b56d', -1, '2023-10-30 14:57:59.13476+00', '2023-10-30 14:57:59.13476+00');
INSERT INTO public.vote_beacon VALUES ('U8a78048d60f7', 'Be5bb2f3d56cb', -1, '2023-10-30 14:58:10.302515+00', '2023-10-30 14:58:10.302515+00');
INSERT INTO public.vote_beacon VALUES ('U8a78048d60f7', 'Bd7a8bfcf3337', 1, '2023-10-30 14:58:52.464396+00', '2023-10-30 14:58:52.464396+00');
INSERT INTO public.vote_beacon VALUES ('U8a78048d60f7', 'B79efabc4d8bf', 1, '2023-10-30 14:59:03.968436+00', '2023-10-30 14:59:03.968436+00');
INSERT INTO public.vote_beacon VALUES ('U0cd6bd2dde4f', 'B9c01ce5718d1', 1, '2023-10-30 17:20:16.263374+00', '2023-10-30 17:20:16.263374+00');
INSERT INTO public.vote_beacon VALUES ('U0cd6bd2dde4f', 'B75a44a52fa29', 1, '2023-10-30 17:20:26.103171+00', '2023-10-30 17:20:26.103171+00');
INSERT INTO public.vote_beacon VALUES ('U6d2f25cc4264', 'B499bfc56e77b', -1, '2023-11-03 02:16:27.710419+00', '2023-11-03 02:28:05.530372+00');
INSERT INTO public.vote_beacon VALUES ('U6d2f25cc4264', 'B25c85fe0df2d', -1, '2023-11-03 02:33:23.795249+00', '2023-11-03 02:33:23.795249+00');
INSERT INTO public.vote_beacon VALUES ('U6d2f25cc4264', 'B3c467fb437b2', -1, '2023-11-03 02:33:46.132125+00', '2023-11-03 02:33:46.132125+00');
INSERT INTO public.vote_beacon VALUES ('U6d2f25cc4264', 'B3b3f2ecde430', -1, '2023-11-03 02:33:48.205024+00', '2023-11-03 02:33:48.205024+00');
INSERT INTO public.vote_beacon VALUES ('U09cf1f359454', 'Bc896788cd2ef', -1, '2023-11-14 00:27:37.248143+00', '2023-11-14 00:27:37.248143+00');
INSERT INTO public.vote_beacon VALUES ('U1bcba4fd7175', 'B45d72e29f004', -9, '2023-11-10 17:05:49.774368+00', '2023-11-10 17:05:50.922108+00');
INSERT INTO public.vote_beacon VALUES ('U1bcba4fd7175', 'Be2b46c17f1da', -1, '2023-11-10 17:05:53.513559+00', '2023-11-10 17:05:53.513559+00');
INSERT INTO public.vote_beacon VALUES ('U1bcba4fd7175', 'B9c01ce5718d1', 9, '2023-11-08 10:00:21.888473+00', '2023-11-11 13:55:15.574336+00');
INSERT INTO public.vote_beacon VALUES ('Ucdffb8ab5145', 'B9c01ce5718d1', 2, '2023-11-17 13:54:56.304102+00', '2023-11-17 13:55:29.343394+00');
INSERT INTO public.vote_beacon VALUES ('U3de789cac826', 'B9c01ce5718d1', 1, '2023-11-17 13:58:01.849984+00', '2023-11-17 14:00:03.667747+00');
INSERT INTO public.vote_beacon VALUES ('U362d375c067c', 'Bad1c69de7837', 0, '2023-11-25 23:53:24.95896+00', '2023-11-25 23:54:11.922961+00');
INSERT INTO public.vote_beacon VALUES ('U79466f73dc0c', 'B45d72e29f004', 5, '2023-11-24 22:02:30.69792+00', '2023-11-24 22:02:31.955886+00');
INSERT INTO public.vote_beacon VALUES ('Uac897fe92894', 'B9c01ce5718d1', -2, '2023-11-25 23:47:22.36996+00', '2023-11-25 23:47:28.547798+00');
INSERT INTO public.vote_beacon VALUES ('U79466f73dc0c', 'B7f628ad203b5', 6, '2023-11-24 22:01:28.672405+00', '2023-11-24 22:01:29.64747+00');
INSERT INTO public.vote_beacon VALUES ('Uac897fe92894', 'B7f628ad203b5', 1, '2023-11-25 23:47:49.014027+00', '2023-11-25 23:47:49.014027+00');
INSERT INTO public.vote_beacon VALUES ('U79466f73dc0c', 'Be2b46c17f1da', 4, '2023-11-24 22:01:33.228451+00', '2023-11-24 22:01:33.749123+00');
INSERT INTO public.vote_beacon VALUES ('U79466f73dc0c', 'Bad1c69de7837', 2, '2023-11-24 22:01:35.833865+00', '2023-11-24 22:01:36.013209+00');
INSERT INTO public.vote_beacon VALUES ('Uac897fe92894', 'Be2b46c17f1da', 2, '2023-11-25 23:48:36.978902+00', '2023-11-25 23:48:42.521172+00');
INSERT INTO public.vote_beacon VALUES ('U704bd6ecde75', 'B9c01ce5718d1', -1, '2023-11-25 23:53:02.007974+00', '2023-11-25 23:53:36.630857+00');
INSERT INTO public.vote_beacon VALUES ('U14a3c81256ab', 'B9c01ce5718d1', 0, '2023-12-07 09:23:58.066808+00', '2023-12-07 09:24:05.25743+00');
INSERT INTO public.vote_beacon VALUES ('U05e4396e2382', 'B7f628ad203b5', 1, '2023-11-25 23:54:39.308489+00', '2023-11-25 23:54:50.229757+00');
INSERT INTO public.vote_beacon VALUES ('Ue202d5b01f8d', 'B9c01ce5718d1', 2, '2023-11-25 23:53:10.575978+00', '2023-11-25 23:55:01.549276+00');
INSERT INTO public.vote_beacon VALUES ('Ubebfe0c8fc29', 'Bfefe4e25c870', 3, '2023-11-25 23:56:48.816753+00', '2023-11-25 23:57:10.051276+00');
INSERT INTO public.vote_beacon VALUES ('U83e829a2e822', 'Be2b46c17f1da', -8, '2023-12-22 19:05:25.027866+00', '2023-12-22 19:05:26.102619+00');
INSERT INTO public.vote_beacon VALUES ('U83e829a2e822', 'B7f628ad203b5', 14, '2023-12-14 11:31:25.54302+00', '2023-12-14 11:31:27.316436+00');
INSERT INTO public.vote_beacon VALUES ('Ubeded808a9c0', 'B9c01ce5718d1', 6, '2023-12-12 15:24:40.276668+00', '2023-12-12 15:24:41.255462+00');
INSERT INTO public.vote_beacon VALUES ('U638f5c19326f', 'B9c01ce5718d1', 2, '2023-12-15 17:06:58.294484+00', '2023-12-15 17:15:47.448077+00');
INSERT INTO public.vote_beacon VALUES ('Ubeded808a9c0', 'B7f628ad203b5', -9, '2023-12-12 15:24:43.806683+00', '2023-12-12 15:24:49.317837+00');
INSERT INTO public.vote_beacon VALUES ('U83282a51b600', 'B9c01ce5718d1', -1, '2023-12-24 19:13:50.446096+00', '2023-12-24 19:13:50.446096+00');
INSERT INTO public.vote_beacon VALUES ('U83282a51b600', 'Be2b46c17f1da', 0, '2023-12-24 19:14:47.353014+00', '2023-12-24 19:14:57.410344+00');
INSERT INTO public.vote_beacon VALUES ('U35eb26fc07b4', 'B7f628ad203b5', -2, '2023-12-24 19:14:32.354897+00', '2023-12-24 19:15:01.896254+00');
INSERT INTO public.vote_beacon VALUES ('U83282a51b600', 'B7f628ad203b5', 1, '2023-12-24 19:15:29.336564+00', '2023-12-24 19:15:29.336564+00');
INSERT INTO public.vote_beacon VALUES ('U38fdca6685ca', 'B9c01ce5718d1', 0, '2023-12-24 19:14:29.030571+00', '2023-12-24 19:15:35.789782+00');
INSERT INTO public.vote_beacon VALUES ('U35eb26fc07b4', 'Be2b46c17f1da', 0, '2023-12-24 19:15:38.450639+00', '2023-12-24 19:16:19.083951+00');
INSERT INTO public.vote_beacon VALUES ('U35eb26fc07b4', 'B60d725feca77', 1, '2023-12-24 19:16:44.261833+00', '2023-12-24 19:16:44.261833+00');
INSERT INTO public.vote_beacon VALUES ('U83282a51b600', 'B45d72e29f004', -1, '2023-12-24 19:15:55.086863+00', '2023-12-24 19:18:03.570577+00');
INSERT INTO public.vote_beacon VALUES ('Ucd424ac24c15', 'B9c01ce5718d1', 2, '2023-12-24 19:19:54.869453+00', '2023-12-24 19:20:45.020405+00');
INSERT INTO public.vote_beacon VALUES ('Ud5f1a29622d1', 'B7f628ad203b5', 1, '2023-12-24 19:22:56.414067+00', '2023-12-24 19:22:56.414067+00');
INSERT INTO public.vote_beacon VALUES ('U526f361717a8', 'B9c01ce5718d1', 0, '2023-12-24 19:18:35.106922+00', '2023-12-24 19:20:13.735845+00');
INSERT INTO public.vote_beacon VALUES ('U4ba2e4e81c0e', 'B7f628ad203b5', -2, '2023-12-24 19:25:58.649375+00', '2023-12-24 19:26:23.603672+00');
INSERT INTO public.vote_beacon VALUES ('U59abf06369c3', 'Be2b46c17f1da', -1, '2023-12-25 12:18:01.044293+00', '2023-12-25 12:18:01.044293+00');
INSERT INTO public.vote_beacon VALUES ('U72f88cf28226', 'B3f6f837bc345', 1, '2024-01-26 14:47:57.804937+00', '2024-01-26 14:48:11.075086+00');
INSERT INTO public.vote_beacon VALUES ('U59abf06369c3', 'B7f628ad203b5', 3, '2023-12-25 12:17:40.779039+00', '2023-12-25 12:19:11.965442+00');
INSERT INTO public.vote_beacon VALUES ('Ueb139752b907', 'B1533941e2773', 1, '2023-12-26 11:03:15.849199+00', '2023-12-26 11:03:15.849199+00');
INSERT INTO public.vote_beacon VALUES ('U72f88cf28226', 'B310b66ab31fb', 1, '2024-01-26 14:49:21.001972+00', '2024-01-26 14:49:21.001972+00');
INSERT INTO public.vote_beacon VALUES ('U47b466d57da1', 'Bad1c69de7837', -3, '2023-12-26 12:12:55.119698+00', '2023-12-26 12:12:55.389162+00');
INSERT INTO public.vote_beacon VALUES ('U11456af7d414', 'Bad1c69de7837', -2, '2023-12-26 12:19:43.923374+00', '2023-12-26 12:19:44.422003+00');
INSERT INTO public.vote_beacon VALUES ('U18a178de1dfb', 'B491d307dfe01', 1, '2023-12-26 15:56:18.958757+00', '2023-12-26 15:56:18.958757+00');
INSERT INTO public.vote_beacon VALUES ('U18a178de1dfb', 'B75a44a52fa29', 1, '2023-12-26 15:56:22.252032+00', '2023-12-26 15:56:22.252032+00');
INSERT INTO public.vote_beacon VALUES ('U18a178de1dfb', 'B310b66ab31fb', 1, '2023-12-26 15:56:29.415022+00', '2023-12-26 15:56:29.415022+00');
INSERT INTO public.vote_beacon VALUES ('U18a178de1dfb', 'B19ea554faf29', 1, '2023-12-26 15:56:34.182086+00', '2023-12-26 15:56:34.182086+00');
INSERT INTO public.vote_beacon VALUES ('U18a178de1dfb', 'B73a44e2bbd44', 1, '2023-12-26 15:56:39.709785+00', '2023-12-26 15:56:39.709785+00');
INSERT INTO public.vote_beacon VALUES ('U18a178de1dfb', 'Bf34ee3bfc12b', 1, '2023-12-26 15:56:57.0935+00', '2023-12-26 15:56:57.0935+00');
INSERT INTO public.vote_beacon VALUES ('U18a178de1dfb', 'B3f6f837bc345', 1, '2023-12-26 15:56:59.081081+00', '2023-12-26 15:56:59.081081+00');
INSERT INTO public.vote_beacon VALUES ('U18a178de1dfb', 'B4f00e7813add', 1, '2023-12-26 15:57:03.340493+00', '2023-12-26 15:57:03.340493+00');
INSERT INTO public.vote_beacon VALUES ('U18a178de1dfb', 'B1533941e2773', 1, '2023-12-26 15:57:09.132478+00', '2023-12-26 15:57:09.132478+00');
INSERT INTO public.vote_beacon VALUES ('U18a178de1dfb', 'Bc4addf09b79f', 1, '2023-12-26 15:57:14.534688+00', '2023-12-26 15:57:14.534688+00');
INSERT INTO public.vote_beacon VALUES ('U18a178de1dfb', 'B70df5dbab8c3', 1, '2023-12-26 15:57:19.010182+00', '2023-12-26 15:57:19.010182+00');
INSERT INTO public.vote_beacon VALUES ('U0f63ee3db59b', 'B9c01ce5718d1', -4, '2023-12-27 12:51:46.444738+00', '2023-12-27 12:52:27.947078+00');
INSERT INTO public.vote_beacon VALUES ('Ue40b938f47a4', 'B9c01ce5718d1', 0, '2024-01-26 15:10:39.480693+00', '2024-01-26 15:10:41.191871+00');
INSERT INTO public.vote_beacon VALUES ('U7cdd7999301e', 'B7f628ad203b5', 1, '2023-12-27 13:12:20.037178+00', '2023-12-27 13:12:20.037178+00');
INSERT INTO public.vote_beacon VALUES ('U0e6659929c53', 'B9c01ce5718d1', 1, '2023-12-27 13:11:34.422001+00', '2023-12-27 13:12:23.228812+00');
INSERT INTO public.vote_beacon VALUES ('U99deecf5a281', 'B9c01ce5718d1', 1, '2023-12-27 13:13:08.732333+00', '2023-12-27 13:13:08.732333+00');
INSERT INTO public.vote_beacon VALUES ('Ua4041a93bdf4', 'B9c01ce5718d1', -1, '2023-12-27 13:10:22.913622+00', '2023-12-27 13:14:00.606424+00');
INSERT INTO public.vote_beacon VALUES ('Ue70d59cc8e3f', 'B9c01ce5718d1', 1, '2023-12-27 13:19:31.283109+00', '2023-12-27 13:19:31.283109+00');
INSERT INTO public.vote_beacon VALUES ('U43dcf522b4dd', 'B9c01ce5718d1', 2, '2023-12-27 13:19:37.579483+00', '2023-12-27 13:19:40.346008+00');
INSERT INTO public.vote_beacon VALUES ('U43dcf522b4dd', 'B3b3f2ecde430', -1, '2023-12-27 13:20:10.778873+00', '2023-12-27 13:20:10.778873+00');
INSERT INTO public.vote_beacon VALUES ('Uf3b5141d73f3', 'B9c01ce5718d1', -3, '2023-12-27 13:24:02.983349+00', '2023-12-27 13:25:02.050149+00');
INSERT INTO public.vote_beacon VALUES ('U83e829a2e822', 'B5eb4c6be535a', 3, '2023-12-27 15:15:19.146107+00', '2023-12-27 15:15:19.554884+00');
INSERT INTO public.vote_beacon VALUES ('U83e829a2e822', 'B0e230e9108dd', -4, '2023-12-27 15:15:20.924696+00', '2023-12-27 15:15:21.48502+00');
INSERT INTO public.vote_beacon VALUES ('U83e829a2e822', 'Bad1c69de7837', -4, '2023-12-27 15:17:58.296817+00', '2023-12-27 15:17:58.843237+00');
INSERT INTO public.vote_beacon VALUES ('Ub01f4ad1b03f', 'B491d307dfe01', 1, '2023-12-28 08:09:41.014745+00', '2023-12-28 08:09:41.014745+00');
INSERT INTO public.vote_beacon VALUES ('Ub01f4ad1b03f', 'B75a44a52fa29', 1, '2023-12-28 08:11:20.097205+00', '2023-12-28 08:11:20.097205+00');
INSERT INTO public.vote_beacon VALUES ('Ub01f4ad1b03f', 'B1533941e2773', 3, '2023-12-28 08:11:08.586449+00', '2023-12-28 08:12:53.729421+00');
INSERT INTO public.vote_beacon VALUES ('Ub01f4ad1b03f', 'Bd7a8bfcf3337', 1, '2023-12-28 08:13:03.992413+00', '2023-12-28 08:13:03.992413+00');
INSERT INTO public.vote_beacon VALUES ('Ub01f4ad1b03f', 'Bd90a1cf73384', 1, '2023-12-28 08:13:12.178212+00', '2023-12-28 08:13:12.178212+00');
INSERT INTO public.vote_beacon VALUES ('Ub01f4ad1b03f', 'B10d3f548efc4', 1, '2023-12-28 08:13:14.016361+00', '2023-12-28 08:13:14.016361+00');
INSERT INTO public.vote_beacon VALUES ('Ub01f4ad1b03f', 'B73a44e2bbd44', 1, '2023-12-28 08:13:17.206628+00', '2023-12-28 08:13:17.206628+00');
INSERT INTO public.vote_beacon VALUES ('Ub01f4ad1b03f', 'B19ea554faf29', 1, '2023-12-28 08:13:27.451918+00', '2023-12-28 08:13:27.451918+00');
INSERT INTO public.vote_beacon VALUES ('Ub01f4ad1b03f', 'B0a87a669fc28', 1, '2023-12-28 08:13:30.808948+00', '2023-12-28 08:13:30.808948+00');
INSERT INTO public.vote_beacon VALUES ('Ub01f4ad1b03f', 'Bb1e3630d2f4a', 1, '2023-12-28 08:13:33.721741+00', '2023-12-28 08:13:33.721741+00');
INSERT INTO public.vote_beacon VALUES ('Ub01f4ad1b03f', 'B92e4a185c654', 1, '2023-12-28 08:13:37.260084+00', '2023-12-28 08:13:37.260084+00');
INSERT INTO public.vote_beacon VALUES ('Ub01f4ad1b03f', 'Bf34ee3bfc12b', 1, '2023-12-28 08:13:39.293345+00', '2023-12-28 08:13:39.293345+00');
INSERT INTO public.vote_beacon VALUES ('Ub01f4ad1b03f', 'Bc4addf09b79f', 1, '2023-12-28 08:13:43.017802+00', '2023-12-28 08:13:43.017802+00');
INSERT INTO public.vote_beacon VALUES ('Ub01f4ad1b03f', 'B4f00e7813add', 1, '2023-12-28 08:13:56.297798+00', '2023-12-28 08:13:56.297798+00');
INSERT INTO public.vote_beacon VALUES ('Ub01f4ad1b03f', 'B70df5dbab8c3', 1, '2023-12-28 08:14:01.93369+00', '2023-12-28 08:14:08.200205+00');
INSERT INTO public.vote_beacon VALUES ('Ub01f4ad1b03f', 'Be2b46c17f1da', -1, '2024-01-13 17:55:42.740788+00', '2024-01-13 17:55:42.740788+00');
INSERT INTO public.vote_beacon VALUES ('Ub01f4ad1b03f', 'B45d72e29f004', -1, '2024-01-13 17:56:22.938065+00', '2024-01-13 17:56:22.938065+00');
INSERT INTO public.vote_beacon VALUES ('Ub01f4ad1b03f', 'B8a531802473b', -1, '2024-01-13 17:58:15.555133+00', '2024-01-13 17:58:15.555133+00');
INSERT INTO public.vote_beacon VALUES ('Ub01f4ad1b03f', 'B5a1c1d3d0140', -1, '2024-01-13 17:58:17.7258+00', '2024-01-13 17:58:17.7258+00');
INSERT INTO public.vote_beacon VALUES ('Ub01f4ad1b03f', 'B60d725feca77', -1, '2024-01-13 17:58:19.925516+00', '2024-01-13 17:58:19.925516+00');
INSERT INTO public.vote_beacon VALUES ('Ub01f4ad1b03f', 'B3c467fb437b2', -1, '2024-01-13 17:58:22.486422+00', '2024-01-13 17:58:22.486422+00');
INSERT INTO public.vote_beacon VALUES ('Ub01f4ad1b03f', 'B3b3f2ecde430', -1, '2024-01-13 17:58:24.122797+00', '2024-01-13 17:58:24.122797+00');
INSERT INTO public.vote_beacon VALUES ('Ub01f4ad1b03f', 'B5eb4c6be535a', -1, '2024-01-13 17:58:25.779698+00', '2024-01-13 17:58:25.779698+00');
INSERT INTO public.vote_beacon VALUES ('Ub01f4ad1b03f', 'Bb78026d99388', -1, '2024-01-13 17:58:27.282866+00', '2024-01-13 17:58:27.282866+00');
INSERT INTO public.vote_beacon VALUES ('Ub01f4ad1b03f', 'B0e230e9108dd', -1, '2024-01-13 17:58:29.183163+00', '2024-01-13 17:58:29.183163+00');
INSERT INTO public.vote_beacon VALUES ('Ub01f4ad1b03f', 'B25c85fe0df2d', -1, '2024-01-13 17:58:33.165329+00', '2024-01-13 17:58:33.165329+00');
INSERT INTO public.vote_beacon VALUES ('Uf6ce05bc4e5a', 'B9c01ce5718d1', 1, '2024-01-26 14:30:20.296572+00', '2024-01-26 14:30:22.10776+00');
INSERT INTO public.vote_beacon VALUES ('U85af6afd0809', 'Bad1c69de7837', -3, '2024-08-12 23:14:50.99767+00', '2024-08-12 23:16:36.354092+00');
INSERT INTO public.vote_beacon VALUES ('U006251a762f0', 'B491d307dfe01', -1, '2024-08-08 17:16:24.771694+00', '2024-08-08 17:18:11.77764+00');
INSERT INTO public.vote_beacon VALUES ('Ud3f25372d084', 'B45d72e29f004', 2, '2024-08-12 23:09:10.662765+00', '2024-08-12 23:09:57.766167+00');
INSERT INTO public.vote_beacon VALUES ('U95f3426b8e5d', 'B79efabc4d8bf', 3, '2024-07-11 16:14:53.930271+00', '2024-07-11 16:14:53.930271+00');
INSERT INTO public.vote_beacon VALUES ('U95f3426b8e5d', 'B9c01ce5718d1', 2, '2024-07-08 12:44:01.550908+00', '2024-07-11 17:24:23.386027+00');
INSERT INTO public.vote_beacon VALUES ('Ucc76e1b73be0', 'B7f628ad203b5', 4, '2024-08-01 11:18:31.719445+00', '2024-08-01 11:18:32.470675+00');
INSERT INTO public.vote_beacon VALUES ('U57c0388e5cb5', 'B9c01ce5718d1', 2, '2024-07-24 14:09:44.580834+00', '2024-07-24 14:09:44.899648+00');
INSERT INTO public.vote_beacon VALUES ('Ub01f4ad1b03f', 'Be64122664ec6', 3, '2024-08-09 00:45:44.236056+00', '2024-08-09 00:45:47.429316+00');
INSERT INTO public.vote_beacon VALUES ('U57c0388e5cb5', 'Be2b46c17f1da', -4, '2024-07-28 10:25:53.635335+00', '2024-07-28 10:25:54.323222+00');
INSERT INTO public.vote_beacon VALUES ('U57c0388e5cb5', 'B73a44e2bbd44', 0, '2024-07-28 10:26:06.17612+00', '2024-07-28 10:26:08.215187+00');
INSERT INTO public.vote_beacon VALUES ('Uad7e22db9014', 'B9c01ce5718d1', 1, '2024-08-01 11:07:05.415815+00', '2024-08-01 11:07:05.415815+00');
INSERT INTO public.vote_beacon VALUES ('Uad7e22db9014', 'Be2b46c17f1da', -1, '2024-08-01 11:06:46.183978+00', '2024-08-01 11:08:05.575793+00');
INSERT INTO public.vote_beacon VALUES ('Uad7e22db9014', 'B7f628ad203b5', 1, '2024-08-01 11:08:10.565046+00', '2024-08-01 11:08:10.565046+00');
INSERT INTO public.vote_beacon VALUES ('Ua0ece646c249', 'B9c01ce5718d1', 1, '2024-08-01 11:08:27.317609+00', '2024-08-01 11:08:27.317609+00');
INSERT INTO public.vote_beacon VALUES ('Uc2fdcf17c2fe', 'B7f628ad203b5', -1, '2024-08-01 11:08:58.693628+00', '2024-08-01 11:08:58.693628+00');
INSERT INTO public.vote_beacon VALUES ('Uc2fdcf17c2fe', 'B3b3f2ecde430', 1, '2024-08-01 11:09:05.486581+00', '2024-08-01 11:09:40.711934+00');
INSERT INTO public.vote_beacon VALUES ('Uebf1ab7a1e6b', 'B9c01ce5718d1', 0, '2024-08-01 11:09:30.724518+00', '2024-08-01 11:09:48.340016+00');
INSERT INTO public.vote_beacon VALUES ('Uccbf9cc1fa1b', 'Ba3c4a280657d', 1, '2024-08-09 01:16:51.104322+00', '2024-08-09 01:19:20.732824+00');
INSERT INTO public.vote_beacon VALUES ('Ua0ece646c249', 'B73a44e2bbd44', 2, '2024-08-01 11:08:57.421542+00', '2024-08-01 11:10:45.648893+00');
INSERT INTO public.vote_beacon VALUES ('Ua0ece646c249', 'B7f628ad203b5', 1, '2024-08-01 11:11:14.182424+00', '2024-08-01 11:11:14.182424+00');
INSERT INTO public.vote_beacon VALUES ('Ua0ece646c249', 'Bad1c69de7837', -1, '2024-08-01 11:11:34.83782+00', '2024-08-01 11:11:34.83782+00');
INSERT INTO public.vote_beacon VALUES ('U6fa666cd4b28', 'B491d307dfe01', 0, '2024-08-01 11:13:09.473707+00', '2024-08-01 11:13:27.386965+00');
INSERT INTO public.vote_beacon VALUES ('U09ce851f811d', 'Bad1c69de7837', 3, '2024-08-04 11:53:32.640533+00', '2024-08-04 11:55:15.972515+00');
INSERT INTO public.vote_beacon VALUES ('Ua5c4a6b171b2', 'B7f628ad203b5', 0, '2024-08-01 11:12:18.364342+00', '2024-08-01 11:14:38.508528+00');
INSERT INTO public.vote_beacon VALUES ('U14debbf04eba', 'B3b3f2ecde430', -1, '2024-08-10 11:19:23.10814+00', '2024-08-10 11:19:23.10814+00');
INSERT INTO public.vote_beacon VALUES ('U6fa666cd4b28', 'B7f628ad203b5', 1, '2024-08-01 11:12:10.938796+00', '2024-08-01 11:14:54.487278+00');
INSERT INTO public.vote_beacon VALUES ('U14debbf04eba', 'B491d307dfe01', 0, '2024-08-10 11:19:21.447298+00', '2024-08-10 11:22:14.796683+00');
INSERT INTO public.vote_beacon VALUES ('U09ce851f811d', 'B7f628ad203b5', -2, '2024-08-04 11:52:03.611552+00', '2024-08-04 11:55:35.935106+00');
INSERT INTO public.vote_beacon VALUES ('U808cdf86e24f', 'B79efabc4d8bf', -1, '2024-08-12 23:07:00.170747+00', '2024-08-12 23:07:00.170747+00');
INSERT INTO public.vote_beacon VALUES ('U27b1b14972c6', 'B7f628ad203b5', -1, '2024-08-12 23:07:46.567038+00', '2024-08-12 23:10:42.437186+00');
INSERT INTO public.vote_beacon VALUES ('U62360fd0833f', 'Ba3c4a280657d', 2, '2024-08-12 23:07:48.297735+00', '2024-08-12 23:11:30.512724+00');
INSERT INTO public.vote_beacon VALUES ('U62360fd0833f', 'B491d307dfe01', 0, '2024-08-12 23:08:05.158508+00', '2024-08-12 23:08:50.965987+00');
INSERT INTO public.vote_beacon VALUES ('Ud3f25372d084', 'B7f628ad203b5', 2, '2024-08-12 23:07:19.701777+00', '2024-08-12 23:08:53.959193+00');
INSERT INTO public.vote_beacon VALUES ('U77a03e9a08af', 'B4b8fafa86526', 0, '2024-08-13 18:28:26.792318+00', '2024-08-17 12:58:44.141559+00');
INSERT INTO public.vote_beacon VALUES ('U77a03e9a08af', 'Bf9c21e90c364', -1, '2024-08-13 18:28:35.59751+00', '2024-08-13 18:28:35.59751+00');
INSERT INTO public.vote_beacon VALUES ('Uf82dbb4708ba', 'B60d725feca77', 11, '2024-08-16 14:30:04.044834+00', '2024-08-16 14:30:08.31087+00');
INSERT INTO public.vote_beacon VALUES ('U85af6afd0809', 'Be2b46c17f1da', 3, '2024-08-12 23:13:29.93814+00', '2024-08-12 23:13:37.216993+00');
INSERT INTO public.vote_beacon VALUES ('Ue1c6ed610073', 'B7f628ad203b5', 0, '2024-08-13 23:02:03.937951+00', '2024-08-13 23:03:31.285514+00');
INSERT INTO public.vote_beacon VALUES ('U05c63e1de554', 'Bad1c69de7837', -2, '2024-08-12 23:12:51.834362+00', '2024-08-12 23:15:31.204133+00');
INSERT INTO public.vote_beacon VALUES ('U77a03e9a08af', 'B7f628ad203b5', -3, '2024-08-16 13:22:32.821599+00', '2024-08-16 13:22:33.204213+00');
INSERT INTO public.vote_beacon VALUES ('U4bab0d326dee', 'B7f628ad203b5', -1, '2024-08-13 23:07:52.966805+00', '2024-08-13 23:07:52.966805+00');
INSERT INTO public.vote_beacon VALUES ('Ue1c6ed610073', 'B3b3f2ecde430', 1, '2024-08-13 23:02:08.90392+00', '2024-08-13 23:03:05.063558+00');
INSERT INTO public.vote_beacon VALUES ('Ue70081ae1455', 'B79efabc4d8bf', -2, '2024-08-13 23:08:20.892889+00', '2024-08-13 23:08:23.778912+00');
INSERT INTO public.vote_beacon VALUES ('Ue70081ae1455', 'B60d725feca77', 1, '2024-08-13 23:08:36.111615+00', '2024-08-13 23:08:36.111615+00');
INSERT INTO public.vote_beacon VALUES ('Uf82dbb4708ba', 'Bad1c69de7837', 8, '2024-08-16 14:27:57.885858+00', '2024-08-16 14:28:00.291023+00');
INSERT INTO public.vote_beacon VALUES ('Uf82dbb4708ba', 'Be64122664ec6', 3, '2024-08-16 14:57:26.79535+00', '2024-08-16 14:57:27.794792+00');
INSERT INTO public.vote_beacon VALUES ('U32f453dcedfc', 'B9cade9992fb9', 2, '2024-08-20 22:33:54.880067+00', '2024-08-20 22:36:24.769216+00');
INSERT INTO public.vote_beacon VALUES ('Uee84b59d1fe1', 'B491d307dfe01', 2, '2024-08-20 22:41:39.355063+00', '2024-08-20 22:41:41.968266+00');
INSERT INTO public.vote_beacon VALUES ('Uee84b59d1fe1', 'Bad1c69de7837', 1, '2024-08-20 22:41:51.668541+00', '2024-08-20 22:41:51.668541+00');
INSERT INTO public.vote_beacon VALUES ('Uee84b59d1fe1', 'B60d725feca77', 1, '2024-08-20 22:44:12.946787+00', '2024-08-20 22:44:12.946787+00');
INSERT INTO public.vote_beacon VALUES ('Uc02f96c370bd', 'B7f628ad203b5', 1, '2024-08-21 11:39:13.24525+00', '2024-08-21 11:39:13.24525+00');
INSERT INTO public.vote_beacon VALUES ('Uc02f96c370bd', 'Be2b46c17f1da', 1, '2024-08-21 11:39:59.449199+00', '2024-08-21 11:39:59.449199+00');
INSERT INTO public.vote_beacon VALUES ('Uc02f96c370bd', 'B60d725feca77', 0, '2024-08-21 11:40:20.181764+00', '2024-08-21 11:42:32.970678+00');
INSERT INTO public.vote_beacon VALUES ('Ub01f4ad1b03f', 'B3f6f837bc345', 2, '2023-12-28 08:10:22.244354+00', '2024-08-06 22:42:46.646652+00');
INSERT INTO public.vote_beacon VALUES ('U0be96c3b9883', 'B25c85fe0df2d', -4, '2024-08-21 15:11:13.488179+00', '2024-08-21 15:11:14.391403+00');
INSERT INTO public.vote_beacon VALUES ('Ub01f4ad1b03f', 'B310b66ab31fb', 4, '2023-12-28 08:10:23.973813+00', '2024-09-08 19:25:33.750178+00');
INSERT INTO public.vote_beacon VALUES ('U0be96c3b9883', 'Be2b46c17f1da', -3, '2024-08-21 15:11:22.4668+00', '2024-08-21 15:11:22.903271+00');
INSERT INTO public.vote_beacon VALUES ('U7debdb69f42f', 'B60d725feca77', 2, '2024-08-13 23:17:04.551581+00', '2024-08-13 23:18:48.564349+00');
INSERT INTO public.vote_beacon VALUES ('U77a03e9a08af', 'B9c01ce5718d1', 1, '2024-08-16 13:52:01.72918+00', '2024-08-16 13:52:01.72918+00');
INSERT INTO public.vote_beacon VALUES ('U1715ceca6772', 'B491d307dfe01', 1, '2024-08-24 17:04:44.97183+00', '2024-08-24 17:04:59.408411+00');
INSERT INTO public.vote_beacon VALUES ('Ub01f4ad1b03f', 'Bb5f87c1621d5', 1, '2024-08-28 03:52:16.307163+00', '2024-08-28 03:52:16.307163+00');
INSERT INTO public.vote_beacon VALUES ('U1f8687088899', 'Bad1c69de7837', -1, '2024-08-09 01:07:45.395189+00', '2024-08-09 01:07:45.395189+00');
INSERT INTO public.vote_beacon VALUES ('U163b54808a6b', 'B5f6a16260bac', 1, '2024-08-24 17:05:15.423379+00', '2024-08-24 17:05:15.423379+00');
INSERT INTO public.vote_beacon VALUES ('Ub01f4ad1b03f', 'B7f628ad203b5', 1, '2024-08-28 03:52:19.377802+00', '2024-08-28 03:52:19.377802+00');
INSERT INTO public.vote_beacon VALUES ('U17b825d673df', 'B7f628ad203b5', 1, '2024-08-21 15:12:40.60394+00', '2024-08-21 15:12:42.598573+00');
INSERT INTO public.vote_beacon VALUES ('U4389072867c2', 'Bad1c69de7837', 2, '2024-08-09 01:08:34.567168+00', '2024-08-09 01:08:49.245743+00');
INSERT INTO public.vote_beacon VALUES ('U163b54808a6b', 'B4f00e7813add', 1, '2024-08-24 17:05:26.920836+00', '2024-08-24 17:05:26.920836+00');
INSERT INTO public.vote_beacon VALUES ('U90b0d3d5d688', 'Bfefe4e25c870', 3, '2024-08-27 15:16:55.527839+00', '2024-08-27 15:16:56.138123+00');
INSERT INTO public.vote_beacon VALUES ('Uf82dbb4708ba', 'B0e230e9108dd', -7, '2024-08-16 14:30:17.505588+00', '2024-08-16 14:30:21.789168+00');
INSERT INTO public.vote_beacon VALUES ('Ue28a49e571f5', 'Bad1c69de7837', 0, '2024-08-09 01:08:14.553626+00', '2024-08-09 01:10:38.990955+00');
INSERT INTO public.vote_beacon VALUES ('U163b54808a6b', 'Be64122664ec6', 1, '2024-08-24 17:05:29.792363+00', '2024-08-24 17:05:29.792363+00');
INSERT INTO public.vote_beacon VALUES ('U1f8687088899', 'B3b3f2ecde430', -1, '2024-08-09 01:08:50.350309+00', '2024-08-09 01:11:28.57021+00');
INSERT INTO public.vote_beacon VALUES ('Ub01f4ad1b03f', 'B500ed1ecb236', 3, '2024-08-06 22:43:55.136265+00', '2024-08-06 22:43:58.589907+00');
INSERT INTO public.vote_beacon VALUES ('U2343287cf1f5', 'Bad1c69de7837', -1, '2024-08-08 15:24:58.875088+00', '2024-08-08 15:24:58.875088+00');
INSERT INTO public.vote_beacon VALUES ('Uaea5ee26a787', 'Bad1c69de7837', -1, '2024-08-08 15:25:15.612412+00', '2024-08-08 15:25:15.612412+00');
INSERT INTO public.vote_beacon VALUES ('U99266e588f08', 'Bad1c69de7837', 0, '2024-08-24 17:04:47.631421+00', '2024-08-24 17:05:35.04442+00');
INSERT INTO public.vote_beacon VALUES ('Uc2cb918a102c', 'Bad1c69de7837', 1, '2024-08-09 01:08:30.074725+00', '2024-08-09 01:11:36.013735+00');
INSERT INTO public.vote_beacon VALUES ('U2343287cf1f5', 'Be2b46c17f1da', 1, '2024-08-08 15:25:52.969459+00', '2024-08-08 15:26:13.829869+00');
INSERT INTO public.vote_beacon VALUES ('Uf82dbb4708ba', 'B75a44a52fa29', 7, '2024-08-16 14:30:43.274799+00', '2024-08-16 14:30:45.690455+00');
INSERT INTO public.vote_beacon VALUES ('U03f52ca325d0', 'Be2b46c17f1da', 1, '2024-08-09 01:07:36.611698+00', '2024-08-09 01:11:43.17137+00');
INSERT INTO public.vote_beacon VALUES ('Uaea5ee26a787', 'B7f628ad203b5', 0, '2024-08-08 15:25:36.588737+00', '2024-08-08 15:26:29.486298+00');
INSERT INTO public.vote_beacon VALUES ('U2a3519a5a091', 'B491d307dfe01', -3, '2024-08-08 15:26:09.214768+00', '2024-08-08 15:26:57.347681+00');
INSERT INTO public.vote_beacon VALUES ('Ub01f4ad1b03f', 'Bea6112348aa2', 2, '2024-08-28 03:52:26.928813+00', '2024-08-28 03:52:36.736384+00');
INSERT INTO public.vote_beacon VALUES ('U2a3519a5a091', 'Bad1c69de7837', -4, '2024-08-08 15:26:12.034027+00', '2024-08-08 15:27:38.640407+00');
INSERT INTO public.vote_beacon VALUES ('Uaea5ee26a787', 'B45d72e29f004', 0, '2024-08-08 15:27:54.483858+00', '2024-08-08 15:28:19.878546+00');
INSERT INTO public.vote_beacon VALUES ('U06f2343258bc', 'B3b3f2ecde430', 1, '2024-08-20 22:32:41.215245+00', '2024-08-20 22:32:54.843454+00');
INSERT INTO public.vote_beacon VALUES ('Uf28fa5b0a7d5', 'B79efabc4d8bf', 1, '2024-08-09 01:13:14.54706+00', '2024-08-09 01:15:30.167483+00');
INSERT INTO public.vote_beacon VALUES ('Uf28fa5b0a7d5', 'B0e230e9108dd', -1, '2024-08-09 01:15:49.646312+00', '2024-08-09 01:15:49.646312+00');
INSERT INTO public.vote_beacon VALUES ('U1ece3c01f2c1', 'Bad1c69de7837', -1, '2024-08-08 15:33:22.046864+00', '2024-08-08 15:34:52.498298+00');
INSERT INTO public.vote_beacon VALUES ('Uf28fa5b0a7d5', 'Ba3c4a280657d', 1, '2024-08-09 01:16:33.496673+00', '2024-08-09 01:16:33.496673+00');
INSERT INTO public.vote_beacon VALUES ('U5a89e961863e', 'Bad1c69de7837', 1, '2024-08-08 15:35:51.255949+00', '2024-08-08 15:35:51.255949+00');
INSERT INTO public.vote_beacon VALUES ('U1ece3c01f2c1', 'Ba3c4a280657d', -2, '2024-08-08 15:35:14.69858+00', '2024-08-08 15:36:12.417758+00');
INSERT INTO public.vote_beacon VALUES ('U5a89e961863e', 'B7f628ad203b5', 2, '2024-08-08 15:37:02.470017+00', '2024-08-08 15:37:37.568534+00');
INSERT INTO public.vote_beacon VALUES ('U01d7dc9f375f', 'B7f628ad203b5', 0, '2024-08-20 22:32:45.624038+00', '2024-08-20 22:33:00.376194+00');
INSERT INTO public.vote_beacon VALUES ('U06f2343258bc', 'Bad1c69de7837', -1, '2024-08-20 22:33:06.25377+00', '2024-08-20 22:33:06.25377+00');
INSERT INTO public.vote_beacon VALUES ('U17b825d673df', 'B491d307dfe01', 6, '2024-08-21 15:12:45.658787+00', '2024-08-21 15:12:47.037738+00');
INSERT INTO public.vote_beacon VALUES ('U77a03e9a08af', 'Bad1c69de7837', -4, '2024-08-09 22:07:03.789944+00', '2024-08-09 22:07:04.775775+00');
INSERT INTO public.vote_beacon VALUES ('U77a03e9a08af', 'Bb78026d99388', 3, '2024-08-09 22:07:22.337575+00', '2024-08-09 22:07:26.048955+00');
INSERT INTO public.vote_beacon VALUES ('U77a03e9a08af', 'Be64122664ec6', 2, '2024-08-10 17:25:30.754745+00', '2024-08-10 17:25:31.053107+00');
INSERT INTO public.vote_beacon VALUES ('U32f453dcedfc', 'Bfefe4e25c870', -1, '2024-08-20 22:32:59.545839+00', '2024-08-20 22:33:28.969834+00');
INSERT INTO public.vote_beacon VALUES ('U77a03e9a08af', 'B500ed1ecb236', 7, '2024-08-08 18:38:39.481041+00', '2024-08-13 18:26:14.246073+00');
INSERT INTO public.vote_beacon VALUES ('U163b54808a6b', 'B500ed1ecb236', 1, '2024-08-24 17:05:36.664227+00', '2024-08-24 17:05:36.664227+00');
INSERT INTO public.vote_beacon VALUES ('U77a03e9a08af', 'B45d72e29f004', -2, '2024-08-13 18:27:27.288294+00', '2024-08-13 18:27:27.594844+00');
INSERT INTO public.vote_beacon VALUES ('U7d4884eabf34', 'Be2b46c17f1da', -1, '2024-08-13 23:01:40.02549+00', '2024-08-13 23:01:40.02549+00');
INSERT INTO public.vote_beacon VALUES ('U0fc148d003b7', 'Bfefe4e25c870', -1, '2024-08-13 23:02:40.546346+00', '2024-08-13 23:02:40.546346+00');
INSERT INTO public.vote_beacon VALUES ('U1ccc3338ee60', 'B5eb4c6be535a', 1, '2024-08-13 23:03:01.137179+00', '2024-08-13 23:03:07.217539+00');
INSERT INTO public.vote_beacon VALUES ('U163b54808a6b', 'B4b8fafa86526', 1, '2024-08-24 17:05:41.569172+00', '2024-08-24 17:05:41.569172+00');
INSERT INTO public.vote_beacon VALUES ('U01d7dc9f375f', 'Bad1c69de7837', 2, '2024-08-20 22:33:15.379757+00', '2024-08-20 22:33:41.39679+00');
INSERT INTO public.vote_beacon VALUES ('U0fc148d003b7', 'B491d307dfe01', -2, '2024-08-13 23:02:56.647362+00', '2024-08-13 23:03:26.254861+00');
INSERT INTO public.vote_beacon VALUES ('U7d4884eabf34', 'B7f628ad203b5', 2, '2024-08-13 23:02:12.852361+00', '2024-08-13 23:04:55.869612+00');
INSERT INTO public.vote_beacon VALUES ('U1715ceca6772', 'Be2b46c17f1da', 1, '2024-08-24 17:05:47.583226+00', '2024-08-24 17:05:47.583226+00');
INSERT INTO public.vote_beacon VALUES ('Ucd6310f58337', 'Bad1c69de7837', 0, '2024-08-24 17:04:43.314857+00', '2024-08-24 17:07:31.408053+00');
INSERT INTO public.vote_beacon VALUES ('U4bab0d326dee', 'B79efabc4d8bf', 1, '2024-08-13 23:07:50.17902+00', '2024-08-13 23:07:50.17902+00');
INSERT INTO public.vote_beacon VALUES ('Ue70081ae1455', 'B3b3f2ecde430', -1, '2024-08-13 23:07:52.865091+00', '2024-08-13 23:07:52.865091+00');
INSERT INTO public.vote_beacon VALUES ('Uc9fc0531972e', 'B3b3f2ecde430', -1, '2024-08-24 17:07:18.472251+00', '2024-08-24 17:08:29.714624+00');
INSERT INTO public.vote_beacon VALUES ('U17b825d673df', 'B30bf91bf5845', 5, '2024-08-21 15:13:05.441958+00', '2024-08-21 15:13:06.498973+00');
INSERT INTO public.vote_beacon VALUES ('U4bab0d326dee', 'Bad1c69de7837', -3, '2024-08-13 23:05:44.18343+00', '2024-08-13 23:09:15.252136+00');
INSERT INTO public.vote_beacon VALUES ('U7debdb69f42f', 'B3b3f2ecde430', -1, '2024-08-13 23:16:46.737698+00', '2024-08-13 23:16:46.737698+00');
INSERT INTO public.vote_beacon VALUES ('U06f2343258bc', 'B7f628ad203b5', -1, '2024-08-20 22:32:43.844314+00', '2024-08-20 22:34:42.046092+00');
INSERT INTO public.vote_beacon VALUES ('Ub4b46ee7a5e4', 'B9c01ce5718d1', 1, '2024-08-22 20:37:21.686957+00', '2024-08-22 20:37:21.686957+00');
INSERT INTO public.vote_beacon VALUES ('Ub4b46ee7a5e4', 'B500ed1ecb236', 1, '2024-08-22 20:37:41.841371+00', '2024-08-22 20:37:41.841371+00');
INSERT INTO public.vote_beacon VALUES ('Ub4b46ee7a5e4', 'Be64122664ec6', 1, '2024-08-22 20:43:31.066684+00', '2024-08-22 20:43:31.066684+00');
INSERT INTO public.vote_beacon VALUES ('Uaebcaa080fa8', 'B5eb4c6be535a', -1, '2024-08-20 22:33:15.00479+00', '2024-08-20 22:34:46.728276+00');
INSERT INTO public.vote_beacon VALUES ('U9d5605fd67f3', 'Bad1c69de7837', 1, '2024-08-20 22:36:02.407865+00', '2024-08-20 22:36:02.407865+00');
INSERT INTO public.vote_beacon VALUES ('Uaebcaa080fa8', 'B25c85fe0df2d', 1, '2024-08-20 22:36:42.698834+00', '2024-08-20 22:36:42.698834+00');
INSERT INTO public.vote_beacon VALUES ('U3ea0a229ad85', 'B310b66ab31fb', 1, '2024-08-22 21:51:04.885951+00', '2024-08-22 21:51:04.885951+00');
INSERT INTO public.vote_beacon VALUES ('U6eba124741ce', 'Be2b46c17f1da', 3, '2024-08-20 22:38:56.210596+00', '2024-08-20 22:39:04.014898+00');
INSERT INTO public.vote_beacon VALUES ('U3ea0a229ad85', 'B500ed1ecb236', 1, '2024-08-22 21:51:20.810401+00', '2024-08-22 21:51:20.810401+00');
INSERT INTO public.vote_beacon VALUES ('U3ea0a229ad85', 'Be64122664ec6', 1, '2024-08-22 21:51:36.620602+00', '2024-08-22 21:51:36.620602+00');
INSERT INTO public.vote_beacon VALUES ('U3ea0a229ad85', 'Bb5f87c1621d5', 1, '2024-08-22 21:51:41.34436+00', '2024-08-22 21:51:41.34436+00');
INSERT INTO public.vote_beacon VALUES ('U6eba124741ce', 'Bfefe4e25c870', 0, '2024-08-20 22:39:09.574798+00', '2024-08-20 22:42:17.865564+00');
INSERT INTO public.vote_beacon VALUES ('U9de057150efc', 'B91796a98a225', 1, '2024-08-21 14:02:00.465166+00', '2024-08-21 14:02:00.465166+00');
INSERT INTO public.vote_beacon VALUES ('U1715ceca6772', 'Bad1c69de7837', 0, '2024-08-24 17:05:56.257508+00', '2024-08-24 17:08:35.591751+00');
INSERT INTO public.vote_beacon VALUES ('U3ea0a229ad85', 'B5f6a16260bac', 1, '2024-08-22 21:51:29.883584+00', '2024-08-22 21:52:24.656581+00');
INSERT INTO public.vote_beacon VALUES ('Ucd6310f58337', 'B7f628ad203b5', -1, '2024-08-24 17:04:17.291989+00', '2024-08-24 17:04:17.291989+00');
INSERT INTO public.vote_beacon VALUES ('Ub01f4ad1b03f', 'B8fabb952bc4b', 2, '2024-08-28 03:54:42.766279+00', '2024-08-28 03:54:43.486887+00');
INSERT INTO public.vote_beacon VALUES ('U99266e588f08', 'B7f628ad203b5', -1, '2024-08-24 17:04:50.341684+00', '2024-08-24 17:06:01.134467+00');
INSERT INTO public.vote_beacon VALUES ('U90b0d3d5d688', 'B491d307dfe01', -4, '2024-08-27 15:16:57.571215+00', '2024-08-27 15:16:58.255788+00');
INSERT INTO public.vote_beacon VALUES ('Ucfdea362a41c', 'Bad1c69de7837', 1, '2024-08-24 17:04:45.678344+00', '2024-08-24 17:06:10.962331+00');
INSERT INTO public.vote_beacon VALUES ('Uc9fc0531972e', 'Be2b46c17f1da', 0, '2024-08-24 17:05:27.516892+00', '2024-08-24 17:06:27.428215+00');
INSERT INTO public.vote_beacon VALUES ('Ue45a5234f456', 'B45d72e29f004', 0, '2024-08-24 17:12:22.675137+00', '2024-08-24 17:13:50.030667+00');
INSERT INTO public.vote_beacon VALUES ('U29a00cc1c9c2', 'B499bfc56e77b', 2, '2024-08-24 17:15:26.92333+00', '2024-08-24 17:15:27.265614+00');
INSERT INTO public.vote_beacon VALUES ('Ub01f4ad1b03f', 'Bc4603804bacf', 1, '2024-08-28 03:55:10.106418+00', '2024-08-28 03:55:10.106418+00');
INSERT INTO public.vote_beacon VALUES ('Ub01f4ad1b03f', 'Bf9c21e90c364', 1, '2024-08-28 03:51:20.601133+00', '2024-08-28 03:51:49.199975+00');
INSERT INTO public.vote_beacon VALUES ('Ub01f4ad1b03f', 'B5f6a16260bac', 2, '2024-08-28 03:51:54.876221+00', '2024-08-28 03:51:55.790326+00');
INSERT INTO public.vote_beacon VALUES ('Ub01f4ad1b03f', 'Bc8526e892c5d', 2, '2024-08-28 03:55:20.219319+00', '2024-08-30 12:40:53.97584+00');
INSERT INTO public.vote_beacon VALUES ('U89f659e858be', 'Bad1c69de7837', 1, '2024-09-05 23:45:52.830669+00', '2024-09-05 23:45:52.830669+00');
INSERT INTO public.vote_beacon VALUES ('U89f659e858be', 'B7f628ad203b5', 1, '2024-09-05 23:45:56.934105+00', '2024-09-05 23:45:56.934105+00');
INSERT INTO public.vote_beacon VALUES ('U89f659e858be', 'B3f6f837bc345', 1, '2024-09-05 23:47:12.462295+00', '2024-09-05 23:47:12.462295+00');
INSERT INTO public.vote_beacon VALUES ('U7d494d508e5e', 'B7f628ad203b5', 3, '2024-09-08 04:26:31.586095+00', '2024-09-08 04:28:04.376786+00');
INSERT INTO public.vote_beacon VALUES ('Ud23a6bb9874f', 'Bad1c69de7837', 1, '2024-09-08 06:48:59.372098+00', '2024-09-08 06:48:59.372098+00');
INSERT INTO public.vote_beacon VALUES ('Ub01f4ad1b03f', 'B9c01ce5718d1', 3, '2023-12-28 08:09:24.495161+00', '2024-09-08 19:24:07.241583+00');
INSERT INTO public.vote_beacon VALUES ('Ud21004c2382a', 'B7f628ad203b5', 6, '2024-09-08 09:31:49.867139+00', '2024-09-08 09:32:11.171097+00');


--
-- Data for Name: vote_comment; Type: TABLE DATA; Schema: public; Owner: postgres
--

INSERT INTO public.vote_comment VALUES ('U016217c34c6e', 'C4e0db8dec53e', 4, '2023-09-26 10:56:27.340119+00', '2023-09-26 10:56:27.340119+00');
INSERT INTO public.vote_comment VALUES ('Uf2b0a6b1d423', 'C4e0db8dec53e', 1, '2023-09-26 10:56:27.340119+00', '2023-09-26 10:56:27.340119+00');
INSERT INTO public.vote_comment VALUES ('Ue7a29d5409f2', 'C4893c40e481d', 4, '2023-09-26 10:56:27.340119+00', '2023-09-26 10:56:27.340119+00');
INSERT INTO public.vote_comment VALUES ('U1c285703fc63', 'Cd59e6cd7e104', 1, '2023-09-26 10:56:27.340119+00', '2023-09-26 10:56:27.340119+00');
INSERT INTO public.vote_comment VALUES ('U389f9f24b31c', 'C6aebafa4fe8e', 6, '2023-09-26 10:56:27.340119+00', '2023-09-26 10:56:27.340119+00');
INSERT INTO public.vote_comment VALUES ('U9a2c85753a6d', 'C357396896bd0', 8, '2023-09-26 10:56:27.340119+00', '2023-09-26 10:56:27.340119+00');
INSERT INTO public.vote_comment VALUES ('U26aca0e369c7', 'C4893c40e481d', 2, '2023-09-26 10:56:27.340119+00', '2023-09-26 10:56:27.340119+00');
INSERT INTO public.vote_comment VALUES ('U7a8d8324441d', 'C78ad459d3b81', 6, '2023-09-26 10:56:27.340119+00', '2023-09-26 10:56:27.340119+00');
INSERT INTO public.vote_comment VALUES ('Udece0afd9a8b', 'C599f6e6f6b64', 2, '2023-09-26 10:56:27.340119+00', '2023-09-26 10:56:27.340119+00');
INSERT INTO public.vote_comment VALUES ('U7a8d8324441d', 'Cd06fea6a395f', 9, '2023-09-26 10:56:27.340119+00', '2023-09-26 10:56:27.340119+00');
INSERT INTO public.vote_comment VALUES ('Udece0afd9a8b', 'C4f2dafca724f', 8, '2023-09-26 10:56:27.340119+00', '2023-09-26 10:56:27.340119+00');
INSERT INTO public.vote_comment VALUES ('Uadeb43da4abb', 'C2bbd63b00224', 7, '2023-09-26 10:56:27.340119+00', '2023-09-26 10:56:27.340119+00');
INSERT INTO public.vote_comment VALUES ('U80e22da6d8c4', 'Cb76829a425d9', -1, '2023-09-26 10:56:27.340119+00', '2023-09-26 10:56:27.340119+00');
INSERT INTO public.vote_comment VALUES ('U0c17798eaab4', 'C588ffef22463', 5, '2023-09-26 10:56:27.340119+00', '2023-09-26 10:56:27.340119+00');
INSERT INTO public.vote_comment VALUES ('Uaa4e2be7a87a', 'C78d6fac93d00', -1, '2023-09-26 10:56:27.340119+00', '2023-09-26 10:56:27.340119+00');
INSERT INTO public.vote_comment VALUES ('U9a2c85753a6d', 'C070e739180d6', 9, '2023-09-26 10:56:27.340119+00', '2023-09-26 10:56:27.340119+00');
INSERT INTO public.vote_comment VALUES ('U80e22da6d8c4', 'C35678a54ef5f', 5, '2023-09-26 10:56:27.340119+00', '2023-09-26 10:56:27.340119+00');
INSERT INTO public.vote_comment VALUES ('Uf5096f6ab14e', 'C4893c40e481d', -1, '2023-09-26 10:56:27.340119+00', '2023-09-26 10:56:27.340119+00');
INSERT INTO public.vote_comment VALUES ('Uadeb43da4abb', 'C9462ca240ceb', -1, '2023-09-26 10:56:27.340119+00', '2023-09-26 10:56:27.340119+00');
INSERT INTO public.vote_comment VALUES ('Uef7fbf45ef11', 'C2bbd63b00224', 8, '2023-09-26 10:56:27.340119+00', '2023-09-26 10:56:27.340119+00');
INSERT INTO public.vote_comment VALUES ('U9a2c85753a6d', 'C78ad459d3b81', 4, '2023-09-26 10:56:27.340119+00', '2023-09-26 10:56:27.340119+00');
INSERT INTO public.vote_comment VALUES ('Uad577360d968', 'Cbce32a9b256a', 3, '2023-09-26 10:56:27.340119+00', '2023-09-26 10:56:27.340119+00');
INSERT INTO public.vote_comment VALUES ('U9a89e0679dec', 'Cbce32a9b256a', 6, '2023-09-26 10:56:27.340119+00', '2023-09-26 10:56:27.340119+00');
INSERT INTO public.vote_comment VALUES ('U016217c34c6e', 'C15d8dfaceb75', 8, '2023-09-26 10:56:27.340119+00', '2023-09-26 10:56:27.340119+00');
INSERT INTO public.vote_comment VALUES ('U389f9f24b31c', 'Cd59e6cd7e104', 3, '2023-09-26 10:56:27.340119+00', '2023-09-26 10:56:27.340119+00');
INSERT INTO public.vote_comment VALUES ('Uc3c31b8a022f', 'C78d6fac93d00', 3, '2023-09-26 10:56:27.340119+00', '2023-09-26 10:56:27.340119+00');
INSERT INTO public.vote_comment VALUES ('Uf2b0a6b1d423', 'Cb76829a425d9', 8, '2023-09-26 10:56:27.340119+00', '2023-09-26 10:56:27.340119+00');
INSERT INTO public.vote_comment VALUES ('U9a2c85753a6d', 'Cfdde53c79a2d', 4, '2023-09-26 10:56:27.340119+00', '2023-09-26 10:56:27.340119+00');
INSERT INTO public.vote_comment VALUES ('U7a8d8324441d', 'C78d6fac93d00', 2, '2023-10-01 09:32:00.734168+00', '2023-10-01 09:32:00.734168+00');
INSERT INTO public.vote_comment VALUES ('Ue7a29d5409f2', 'Cfdde53c79a2d', 5, '2023-10-01 09:32:00.734168+00', '2023-10-01 09:32:00.734168+00');
INSERT INTO public.vote_comment VALUES ('U9e42f6dab85a', 'C0b19d314485e', -1, '2023-10-01 09:32:00.734168+00', '2023-10-01 09:32:00.734168+00');
INSERT INTO public.vote_comment VALUES ('U80e22da6d8c4', 'Cb14487d862b3', 6, '2023-10-01 09:32:00.734168+00', '2023-10-01 09:32:00.734168+00');
INSERT INTO public.vote_comment VALUES ('U389f9f24b31c', 'C4893c40e481d', 3, '2023-10-01 09:32:00.734168+00', '2023-10-01 09:32:00.734168+00');
INSERT INTO public.vote_comment VALUES ('U016217c34c6e', 'Cb76829a425d9', 2, '2023-10-01 09:32:00.734168+00', '2023-10-01 09:32:00.734168+00');
INSERT INTO public.vote_comment VALUES ('U7a8d8324441d', 'Cbbf2df46955b', 5, '2023-10-01 09:32:00.734168+00', '2023-10-01 09:32:00.734168+00');
INSERT INTO public.vote_comment VALUES ('U9a2c85753a6d', 'Cdcddfb230cb5', 4, '2023-10-01 09:32:00.734168+00', '2023-10-01 09:32:00.734168+00');
INSERT INTO public.vote_comment VALUES ('U9a2c85753a6d', 'C4893c40e481d', -1, '2023-10-01 09:32:00.734168+00', '2023-10-01 09:32:00.734168+00');
INSERT INTO public.vote_comment VALUES ('Uf2b0a6b1d423', 'Cdcddfb230cb5', 3, '2023-10-01 09:32:00.734168+00', '2023-10-01 09:32:00.734168+00');
INSERT INTO public.vote_comment VALUES ('U389f9f24b31c', 'Cbbf2df46955b', 4, '2023-10-01 09:32:00.734168+00', '2023-10-01 09:32:00.734168+00');
INSERT INTO public.vote_comment VALUES ('Uad577360d968', 'C2bbd63b00224', 9, '2023-10-01 09:32:00.734168+00', '2023-10-01 09:32:00.734168+00');
INSERT INTO public.vote_comment VALUES ('U80e22da6d8c4', 'Cbbf2df46955b', 5, '2023-10-01 09:32:00.734168+00', '2023-10-01 09:32:00.734168+00');
INSERT INTO public.vote_comment VALUES ('U9e42f6dab85a', 'C070e739180d6', 2, '2023-10-01 09:32:00.734168+00', '2023-10-01 09:32:00.734168+00');
INSERT INTO public.vote_comment VALUES ('Ue7a29d5409f2', 'C9028c7415403', 3, '2023-10-01 09:32:00.734168+00', '2023-10-01 09:32:00.734168+00');
INSERT INTO public.vote_comment VALUES ('U9a2c85753a6d', 'C3e84102071d1', 6, '2023-10-01 09:32:00.734168+00', '2023-10-01 09:32:00.734168+00');
INSERT INTO public.vote_comment VALUES ('U389f9f24b31c', 'Cdcddfb230cb5', 5, '2023-10-01 09:32:00.734168+00', '2023-10-01 09:32:00.734168+00');
INSERT INTO public.vote_comment VALUES ('Uaa4e2be7a87a', 'C588ffef22463', 1, '2023-10-01 09:32:00.734168+00', '2023-10-01 09:32:00.734168+00');
INSERT INTO public.vote_comment VALUES ('Ue7a29d5409f2', 'Ce1a7d8996eb0', 5, '2023-10-01 09:32:00.734168+00', '2023-10-01 09:32:00.734168+00');
INSERT INTO public.vote_comment VALUES ('U26aca0e369c7', 'Cb117f464e558', 6, '2023-10-01 09:32:00.734168+00', '2023-10-01 09:32:00.734168+00');
INSERT INTO public.vote_comment VALUES ('Uc1158424318a', 'C0b19d314485e', 4, '2023-10-01 09:32:00.734168+00', '2023-10-01 09:32:00.734168+00');
INSERT INTO public.vote_comment VALUES ('Uadeb43da4abb', 'C30e7409c2d5f', 2, '2023-10-01 09:32:00.734168+00', '2023-10-01 09:32:00.734168+00');
INSERT INTO public.vote_comment VALUES ('U80e22da6d8c4', 'C3e84102071d1', 4, '2023-10-01 09:32:00.734168+00', '2023-10-01 09:32:00.734168+00');
INSERT INTO public.vote_comment VALUES ('Uc1158424318a', 'Cfdde53c79a2d', 6, '2023-10-01 09:32:00.734168+00', '2023-10-01 09:32:00.734168+00');
INSERT INTO public.vote_comment VALUES ('U9a2c85753a6d', 'Ce1a7d8996eb0', 2, '2023-10-01 09:32:00.734168+00', '2023-10-01 09:32:00.734168+00');
INSERT INTO public.vote_comment VALUES ('U9a89e0679dec', 'Cd06fea6a395f', -1, '2023-10-01 09:32:00.734168+00', '2023-10-01 09:32:00.734168+00');
INSERT INTO public.vote_comment VALUES ('Uf5096f6ab14e', 'C6aebafa4fe8e', 8, '2023-10-01 09:32:00.734168+00', '2023-10-01 09:32:00.734168+00');
INSERT INTO public.vote_comment VALUES ('Uadeb43da4abb', 'Cc9f863ff681b', 2, '2023-10-01 09:32:00.734168+00', '2023-10-01 09:32:00.734168+00');
INSERT INTO public.vote_comment VALUES ('Ue7a29d5409f2', 'C399b6349ab02', 5, '2023-10-01 09:32:00.734168+00', '2023-10-01 09:32:00.734168+00');
INSERT INTO public.vote_comment VALUES ('Uc1158424318a', 'C4e0db8dec53e', 4, '2023-10-01 09:32:00.734168+00', '2023-10-01 09:32:00.734168+00');
INSERT INTO public.vote_comment VALUES ('U9a89e0679dec', 'C6aebafa4fe8e', 8, '2023-10-01 09:32:00.734168+00', '2023-10-01 09:32:00.734168+00');
INSERT INTO public.vote_comment VALUES ('U80e22da6d8c4', 'C6acd550a4ef3', -1, '2023-10-01 09:32:00.734168+00', '2023-10-01 09:32:00.734168+00');
INSERT INTO public.vote_comment VALUES ('Uf2b0a6b1d423', 'Ce1a7d8996eb0', -1, '2023-10-01 09:32:00.734168+00', '2023-10-01 09:32:00.734168+00');
INSERT INTO public.vote_comment VALUES ('U9a2c85753a6d', 'C30fef1977b4a', 8, '2023-10-01 09:32:00.734168+00', '2023-10-01 09:32:00.734168+00');
INSERT INTO public.vote_comment VALUES ('Uef7fbf45ef11', 'C588ffef22463', 4, '2023-10-01 09:32:00.734168+00', '2023-10-01 09:32:00.734168+00');
INSERT INTO public.vote_comment VALUES ('Uef7fbf45ef11', 'C94bb73c10a06', 3, '2023-10-01 09:32:00.734168+00', '2023-10-01 09:32:00.734168+00');
INSERT INTO public.vote_comment VALUES ('Uad577360d968', 'C588ffef22463', -1, '2023-10-01 09:32:00.734168+00', '2023-10-01 09:32:00.734168+00');
INSERT INTO public.vote_comment VALUES ('Uf2b0a6b1d423', 'C67e4476fda28', 6, '2023-10-01 09:32:00.734168+00', '2023-10-01 09:32:00.734168+00');
INSERT INTO public.vote_comment VALUES ('U0c17798eaab4', 'C4893c40e481d', 7, '2023-09-26 10:56:27.340119+00', '2023-10-01 09:32:00.734168+00');
INSERT INTO public.vote_comment VALUES ('Uf2b0a6b1d423', 'C6a2263dc469e', 3, '2023-10-01 09:32:00.734168+00', '2023-10-01 09:32:00.734168+00');
INSERT INTO public.vote_comment VALUES ('Uf2b0a6b1d423', 'C3fd1fdebe0e9', 7, '2023-10-01 09:32:00.734168+00', '2023-10-01 09:32:00.734168+00');
INSERT INTO public.vote_comment VALUES ('Uef7fbf45ef11', 'C3fd1fdebe0e9', 9, '2023-10-01 09:32:57.375819+00', '2023-10-01 09:32:57.375819+00');
INSERT INTO public.vote_comment VALUES ('Uc1158424318a', 'C9028c7415403', -1, '2023-10-01 09:32:57.375819+00', '2023-10-01 09:32:57.375819+00');
INSERT INTO public.vote_comment VALUES ('U9e42f6dab85a', 'C6a2263dc469e', 5, '2023-10-01 09:32:00.734168+00', '2023-10-01 09:32:57.375819+00');
INSERT INTO public.vote_comment VALUES ('Uad577360d968', 'C399b6349ab02', 6, '2023-10-01 09:32:57.375819+00', '2023-10-01 09:32:57.375819+00');
INSERT INTO public.vote_comment VALUES ('U26aca0e369c7', 'C9028c7415403', 8, '2023-10-01 09:32:57.375819+00', '2023-10-01 09:32:57.375819+00');
INSERT INTO public.vote_comment VALUES ('U1c285703fc63', 'C30e7409c2d5f', 4, '2023-10-01 09:32:00.734168+00', '2023-10-01 09:39:08.08905+00');
INSERT INTO public.vote_comment VALUES ('U9a89e0679dec', 'Cbbf2df46955b', -1, '2023-10-01 09:39:08.08905+00', '2023-10-01 09:39:08.08905+00');
INSERT INTO public.vote_comment VALUES ('Uf5096f6ab14e', 'C3e84102071d1', 1, '2023-10-01 09:39:08.08905+00', '2023-10-01 09:39:08.08905+00');
INSERT INTO public.vote_comment VALUES ('U7a8d8324441d', 'C94bb73c10a06', 9, '2023-10-01 09:39:08.08905+00', '2023-10-01 09:39:08.08905+00');
INSERT INTO public.vote_comment VALUES ('Uaa4e2be7a87a', 'Cfdde53c79a2d', 3, '2023-10-01 09:39:08.08905+00', '2023-10-01 09:39:08.08905+00');
INSERT INTO public.vote_comment VALUES ('U26aca0e369c7', 'C6acd550a4ef3', 4, '2023-10-01 09:32:00.734168+00', '2023-10-01 09:44:32.092118+00');
INSERT INTO public.vote_comment VALUES ('Uc1158424318a', 'C67e4476fda28', -1, '2023-10-01 09:32:00.734168+00', '2023-10-01 09:47:53.211502+00');
INSERT INTO public.vote_comment VALUES ('Uf2b0a6b1d423', 'C30e7409c2d5f', 9, '2023-10-01 09:49:09.949784+00', '2023-10-01 09:49:09.949784+00');
INSERT INTO public.vote_comment VALUES ('U389f9f24b31c', 'C4f2dafca724f', 5, '2023-10-01 09:51:18.771431+00', '2023-10-01 09:51:18.771431+00');
INSERT INTO public.vote_comment VALUES ('U0c17798eaab4', 'Ce1a7d8996eb0', 6, '2023-10-01 09:52:28.926471+00', '2023-10-01 09:52:28.926471+00');
INSERT INTO public.vote_comment VALUES ('Uad577360d968', 'C6a2263dc469e', 5, '2023-10-01 09:53:35.042646+00', '2023-10-01 09:53:35.042646+00');
INSERT INTO public.vote_comment VALUES ('U0c17798eaab4', 'Cd06fea6a395f', 8, '2023-10-01 09:57:37.267051+00', '2023-10-01 09:57:37.267051+00');
INSERT INTO public.vote_comment VALUES ('Uaa4e2be7a87a', 'C070e739180d6', 8, '2023-09-26 10:56:27.340119+00', '2023-10-01 09:59:04.61223+00');
INSERT INTO public.vote_comment VALUES ('U389f9f24b31c', 'C6acd550a4ef3', 6, '2023-10-01 09:59:26.704145+00', '2023-10-01 09:59:26.704145+00');
INSERT INTO public.vote_comment VALUES ('U01814d1ec9ff', 'C6d52e861b366', 3, '2023-10-05 14:03:37.623524+00', '2023-10-05 14:03:38.543894+00');
INSERT INTO public.vote_comment VALUES ('U99a0f1f7e6ee', 'C96bdee4f11e2', -18, '2023-10-06 15:21:10.945378+00', '2023-10-06 15:21:31.190046+00');
INSERT INTO public.vote_comment VALUES ('U6d2f25cc4264', 'C8d80016b8292', 1, '2023-10-08 17:06:52.638651+00', '2023-10-08 17:06:52.638651+00');
INSERT INTO public.vote_comment VALUES ('U6d2f25cc4264', 'C247501543b60', 1, '2023-10-08 17:08:14.95269+00', '2023-10-08 17:08:14.95269+00');
INSERT INTO public.vote_comment VALUES ('U6d2f25cc4264', 'C6f84810d3cd9', 1, '2023-10-08 17:10:17.888281+00', '2023-10-08 17:10:17.888281+00');
INSERT INTO public.vote_comment VALUES ('U9605bd4d1218', 'C801f204d0da8', 3, '2023-10-09 19:34:55.351728+00', '2023-10-09 19:34:55.640437+00');
INSERT INTO public.vote_comment VALUES ('U9605bd4d1218', 'Cab47a458295f', 3, '2023-10-09 19:34:56.613533+00', '2023-10-09 19:34:56.920198+00');
INSERT INTO public.vote_comment VALUES ('U8a78048d60f7', 'Cbce32a9b256a', 1, '2023-10-19 14:38:55.224603+00', '2023-10-19 14:38:55.224603+00');
INSERT INTO public.vote_comment VALUES ('U8a78048d60f7', 'C357396896bd0', 1, '2023-10-19 14:38:56.176058+00', '2023-10-19 14:38:56.176058+00');
INSERT INTO public.vote_comment VALUES ('U8a78048d60f7', 'C6acd550a4ef3', 1, '2023-10-19 14:38:57.974528+00', '2023-10-19 14:38:57.974528+00');
INSERT INTO public.vote_comment VALUES ('U8a78048d60f7', 'Cdcddfb230cb5', 1, '2023-10-19 14:39:00.022673+00', '2023-10-19 14:39:00.022673+00');
INSERT INTO public.vote_comment VALUES ('U8a78048d60f7', 'Cf4b448ef8618', 2, '2023-10-19 14:39:39.568221+00', '2023-10-19 14:39:40.671924+00');
INSERT INTO public.vote_comment VALUES ('U3c63a9b6115a', 'Cf92f90725ffc', 1, '2023-10-27 19:21:43.161414+00', '2023-10-27 19:21:43.161414+00');
INSERT INTO public.vote_comment VALUES ('U8a78048d60f7', 'Cd6c9d5cba220', 1, '2023-10-20 06:50:23.048387+00', '2023-10-30 14:53:59.912655+00');
INSERT INTO public.vote_comment VALUES ('U0cd6bd2dde4f', 'C7062e90f7422', 1, '2023-10-30 17:20:36.532603+00', '2023-10-30 17:20:36.532603+00');
INSERT INTO public.vote_comment VALUES ('U1bcba4fd7175', 'Cd4417a5d718e', 5, '2023-11-10 17:07:48.84666+00', '2023-11-10 17:07:49.4381+00');
INSERT INTO public.vote_comment VALUES ('U9a2c85753a6d', 'C6a2263dc469e', 2, '2023-09-26 10:56:27.340119+00', '2024-07-05 13:33:34.567457+00');
INSERT INTO public.vote_comment VALUES ('U1bcba4fd7175', 'C6d52e861b366', -1, '2023-11-10 17:07:59.600814+00', '2023-11-10 17:07:59.600814+00');
INSERT INTO public.vote_comment VALUES ('U77f496546efa', 'C9462ca240ceb', -1, '2023-11-20 17:51:33.704425+00', '2023-11-20 17:51:33.704425+00');
INSERT INTO public.vote_comment VALUES ('Uac897fe92894', 'Cb117f464e558', 1, '2023-11-25 23:47:51.939319+00', '2023-11-25 23:47:51.939319+00');
INSERT INTO public.vote_comment VALUES ('Uac897fe92894', 'C9462ca240ceb', 0, '2023-11-25 23:48:34.222551+00', '2023-11-25 23:48:45.341466+00');
INSERT INTO public.vote_comment VALUES ('U585dfead09c6', 'C6d52e861b366', -1, '2023-11-26 00:22:49.208559+00', '2023-11-26 00:22:49.208559+00');
INSERT INTO public.vote_comment VALUES ('U83282a51b600', 'C9462ca240ceb', 1, '2023-12-24 19:14:50.447628+00', '2023-12-24 19:14:50.447628+00');
INSERT INTO public.vote_comment VALUES ('U35eb26fc07b4', 'Cb117f464e558', -1, '2023-12-24 19:14:46.819562+00', '2023-12-24 19:15:24.874504+00');
INSERT INTO public.vote_comment VALUES ('U4ba2e4e81c0e', 'Cb117f464e558', 1, '2023-12-24 19:25:53.166016+00', '2023-12-24 19:25:53.166016+00');
INSERT INTO public.vote_comment VALUES ('U59abf06369c3', 'Cb117f464e558', -3, '2023-12-25 12:18:56.246126+00', '2023-12-25 12:19:00.815507+00');
INSERT INTO public.vote_comment VALUES ('U0e6659929c53', 'C6d52e861b366', -1, '2023-12-27 13:11:31.618479+00', '2023-12-27 13:12:35.642845+00');
INSERT INTO public.vote_comment VALUES ('Ub01f4ad1b03f', 'C5782d559baad', 1, '2024-01-13 17:54:59.64645+00', '2024-01-13 17:54:59.64645+00');
INSERT INTO public.vote_comment VALUES ('U72f88cf28226', 'Cd6c9d5cba220', 1, '2024-01-26 14:49:19.223947+00', '2024-01-26 14:49:19.223947+00');
INSERT INTO public.vote_comment VALUES ('U72f88cf28226', 'Cb11edc3d0bc7', 1, '2024-01-26 14:49:20.271833+00', '2024-01-26 14:49:20.271833+00');
INSERT INTO public.vote_comment VALUES ('U95f3426b8e5d', 'C992d8370db6b', 1, '2024-07-11 16:07:42.511595+00', '2024-07-11 16:07:42.511595+00');
INSERT INTO public.vote_comment VALUES ('Uad7e22db9014', 'Cd5983133fb67', -1, '2024-08-01 11:07:26.648657+00', '2024-08-01 11:07:26.648657+00');
INSERT INTO public.vote_comment VALUES ('Uad7e22db9014', 'Cd4417a5d718e', 1, '2024-08-01 11:07:29.49378+00', '2024-08-01 11:07:37.399118+00');
INSERT INTO public.vote_comment VALUES ('Ua0ece646c249', 'C6d52e861b366', -1, '2024-08-01 11:08:40.925423+00', '2024-08-01 11:08:40.925423+00');
INSERT INTO public.vote_comment VALUES ('Uc2fdcf17c2fe', 'C54972a5fbc16', -1, '2024-08-01 11:09:30.454931+00', '2024-08-01 11:09:30.454931+00');
INSERT INTO public.vote_comment VALUES ('Uc2fdcf17c2fe', 'C7722465c957a', -1, '2024-08-01 11:09:49.124154+00', '2024-08-01 11:09:49.124154+00');
INSERT INTO public.vote_comment VALUES ('Uebf1ab7a1e6b', 'Cd5983133fb67', -1, '2024-08-01 11:09:51.403203+00', '2024-08-01 11:09:51.403203+00');
INSERT INTO public.vote_comment VALUES ('U38c58796a985', 'Cac6ca02355da', 1, '2024-08-05 22:13:45.203624+00', '2024-08-05 22:13:45.203624+00');
INSERT INTO public.vote_comment VALUES ('U38c58796a985', 'C54972a5fbc16', 1, '2024-08-05 22:13:47.814855+00', '2024-08-05 22:13:47.814855+00');
INSERT INTO public.vote_comment VALUES ('Uc406b9444f78', 'Cb117f464e558', -1, '2024-08-05 22:14:36.870478+00', '2024-08-05 22:14:36.870478+00');
INSERT INTO public.vote_comment VALUES ('U01d7dc9f375f', 'Cbce32a9b256a', -1, '2024-08-20 22:33:06.104187+00', '2024-08-20 22:33:06.104187+00');
INSERT INTO public.vote_comment VALUES ('Ue45a5234f456', 'Cb117f464e558', -1, '2024-08-24 17:11:57.076389+00', '2024-08-24 17:11:57.076389+00');
INSERT INTO public.vote_comment VALUES ('U15333c20136a', 'C30e7409c2d5f', 0, '2024-08-05 22:15:29.312449+00', '2024-08-05 22:16:51.514515+00');
INSERT INTO public.vote_comment VALUES ('U9f2ca949e629', 'C8ece5c618ac1', -1, '2024-08-05 22:21:21.00314+00', '2024-08-05 22:21:21.00314+00');
INSERT INTO public.vote_comment VALUES ('U3de05e2162cb', 'Cb117f464e558', 0, '2024-08-08 15:25:15.839758+00', '2024-08-08 15:25:36.318061+00');
INSERT INTO public.vote_comment VALUES ('U32f453dcedfc', 'Cfa08a39f9bb9', -1, '2024-08-20 22:33:11.609937+00', '2024-08-20 22:33:41.913483+00');
INSERT INTO public.vote_comment VALUES ('U32f453dcedfc', 'C63e21d051dda', -1, '2024-08-20 22:32:51.810614+00', '2024-08-20 22:33:49.471886+00');
INSERT INTO public.vote_comment VALUES ('U2343287cf1f5', 'C9462ca240ceb', 1, '2024-08-08 15:26:11.116835+00', '2024-08-08 15:26:11.116835+00');
INSERT INTO public.vote_comment VALUES ('Uaea5ee26a787', 'Cb117f464e558', 0, '2024-08-08 15:25:47.597585+00', '2024-08-08 15:26:40.604851+00');
INSERT INTO public.vote_comment VALUES ('U2a3519a5a091', 'Cbce32a9b256a', 1, '2024-08-08 15:28:18.844369+00', '2024-08-08 15:28:18.844369+00');
INSERT INTO public.vote_comment VALUES ('U70a397181807', 'Cb117f464e558', -1, '2024-09-08 04:24:02.092317+00', '2024-09-08 04:24:02.092317+00');
INSERT INTO public.vote_comment VALUES ('U70a397181807', 'C2bbd63b00224', -1, '2024-09-08 04:24:04.215647+00', '2024-09-08 04:24:04.215647+00');
INSERT INTO public.vote_comment VALUES ('U006251a762f0', 'Cab47a458295f', 1, '2024-08-08 17:17:31.188239+00', '2024-08-08 17:17:53.786035+00');
INSERT INTO public.vote_comment VALUES ('U70a397181807', 'C8d80016b8292', 1, '2024-09-08 04:24:09.66978+00', '2024-09-08 04:24:09.66978+00');
INSERT INTO public.vote_comment VALUES ('U006251a762f0', 'C801f204d0da8', 1, '2024-08-08 17:17:34.14368+00', '2024-08-08 17:18:08.924199+00');
INSERT INTO public.vote_comment VALUES ('U70a397181807', 'Ce28175f0281e', 1, '2024-09-08 04:24:10.902194+00', '2024-09-08 04:24:10.902194+00');
INSERT INTO public.vote_comment VALUES ('U1f8687088899', 'Cbce32a9b256a', -1, '2024-08-09 01:07:50.666093+00', '2024-08-09 01:07:50.666093+00');
INSERT INTO public.vote_comment VALUES ('Uaebcaa080fa8', 'C94bb73c10a06', 1, '2024-08-20 22:34:01.719693+00', '2024-08-20 22:34:57.679261+00');
INSERT INTO public.vote_comment VALUES ('Ue28a49e571f5', 'Cbce32a9b256a', 1, '2024-08-09 01:08:49.927426+00', '2024-08-09 01:10:36.772197+00');
INSERT INTO public.vote_comment VALUES ('U4389072867c2', 'Cbce32a9b256a', -1, '2024-08-09 01:11:27.012684+00', '2024-08-09 01:11:27.012684+00');
INSERT INTO public.vote_comment VALUES ('U06f2343258bc', 'Cb117f464e558', 0, '2024-08-20 22:34:15.361452+00', '2024-08-20 22:35:47.584842+00');
INSERT INTO public.vote_comment VALUES ('U6eba124741ce', 'Cfa08a39f9bb9', -1, '2024-08-20 22:39:22.880206+00', '2024-08-20 22:39:22.880206+00');
INSERT INTO public.vote_comment VALUES ('U03f52ca325d0', 'C9462ca240ceb', 3, '2024-08-09 01:07:28.386092+00', '2024-08-09 01:11:46.015614+00');
INSERT INTO public.vote_comment VALUES ('Uf28fa5b0a7d5', 'C8ece5c618ac1', 1, '2024-08-09 01:13:37.352545+00', '2024-08-09 01:13:37.352545+00');
INSERT INTO public.vote_comment VALUES ('Uccbf9cc1fa1b', 'C481cd737c873', 1, '2024-08-09 01:19:13.232751+00', '2024-08-09 01:19:52.598316+00');
INSERT INTO public.vote_comment VALUES ('U14debbf04eba', 'C9462ca240ceb', -1, '2024-08-10 11:19:16.906735+00', '2024-08-10 11:19:16.906735+00');
INSERT INTO public.vote_comment VALUES ('U14debbf04eba', 'C54972a5fbc16', 1, '2024-08-10 11:22:30.469269+00', '2024-08-10 11:22:30.469269+00');
INSERT INTO public.vote_comment VALUES ('Ud3f25372d084', 'Cb117f464e558', -1, '2024-08-12 23:08:47.343435+00', '2024-08-12 23:08:47.343435+00');
INSERT INTO public.vote_comment VALUES ('U62360fd0833f', 'C481cd737c873', -1, '2024-08-12 23:09:46.388052+00', '2024-08-12 23:09:46.388052+00');
INSERT INTO public.vote_comment VALUES ('Ud3f25372d084', 'C30e7409c2d5f', -1, '2024-08-12 23:10:00.432874+00', '2024-08-12 23:10:00.432874+00');
INSERT INTO public.vote_comment VALUES ('U808cdf86e24f', 'C992d8370db6b', -1, '2024-08-12 23:10:26.398562+00', '2024-08-12 23:10:26.398562+00');
INSERT INTO public.vote_comment VALUES ('U27b1b14972c6', 'Cb117f464e558', 1, '2024-08-12 23:10:50.437176+00', '2024-08-12 23:10:50.437176+00');
INSERT INTO public.vote_comment VALUES ('U1715ceca6772', 'C801f204d0da8', 0, '2024-08-24 17:04:53.771232+00', '2024-08-24 17:04:56.555481+00');
INSERT INTO public.vote_comment VALUES ('U7d494d508e5e', 'C8d80016b8292', 0, '2024-09-08 04:29:29.571108+00', '2024-09-08 04:29:40.073904+00');
INSERT INTO public.vote_comment VALUES ('U808cdf86e24f', 'C8ece5c618ac1', 1, '2024-08-12 23:07:12.623619+00', '2024-08-12 23:11:11.78291+00');
INSERT INTO public.vote_comment VALUES ('Uc9fc0531972e', 'C9462ca240ceb', -1, '2024-08-24 17:05:37.89663+00', '2024-08-24 17:05:37.89663+00');
INSERT INTO public.vote_comment VALUES ('U99266e588f08', 'Cbce32a9b256a', -1, '2024-08-24 17:05:45.49238+00', '2024-08-24 17:05:45.49238+00');
INSERT INTO public.vote_comment VALUES ('Ue1c6ed610073', 'Cb117f464e558', 0, '2024-08-13 23:02:28.990449+00', '2024-08-13 23:03:19.706678+00');
INSERT INTO public.vote_comment VALUES ('U1ccc3338ee60', 'C94bb73c10a06', -1, '2024-08-13 23:03:21.327755+00', '2024-08-13 23:03:21.327755+00');
INSERT INTO public.vote_comment VALUES ('Ud23a6bb9874f', 'Cbce32a9b256a', 2, '2024-09-08 06:48:57.017973+00', '2024-09-08 06:48:57.273612+00');
INSERT INTO public.vote_comment VALUES ('U0fc148d003b7', 'Cab47a458295f', 0, '2024-08-13 23:03:28.960932+00', '2024-08-13 23:03:39.64649+00');
INSERT INTO public.vote_comment VALUES ('U0fc148d003b7', 'C801f204d0da8', -1, '2024-08-13 23:03:58.58175+00', '2024-08-13 23:03:58.58175+00');
INSERT INTO public.vote_comment VALUES ('U4bab0d326dee', 'Cbce32a9b256a', 3, '2024-08-13 23:05:41.410921+00', '2024-08-13 23:08:51.962483+00');
INSERT INTO public.vote_comment VALUES ('Ub01f4ad1b03f', 'C0f761a65e114', 2, '2024-08-19 22:24:29.893905+00', '2024-08-19 22:24:32.287365+00');
INSERT INTO public.vote_comment VALUES ('Ud21004c2382a', 'Cb117f464e558', 3, '2024-09-08 09:32:19.811093+00', '2024-09-08 09:32:20.897573+00');
INSERT INTO public.vote_comment VALUES ('Ucfdea362a41c', 'Cbce32a9b256a', 0, '2024-08-24 17:05:12.539793+00', '2024-08-24 17:05:59.638205+00');
INSERT INTO public.vote_comment VALUES ('Uc9fc0531972e', 'C30fef1977b4a', 2, '2024-08-24 17:05:45.503137+00', '2024-08-24 17:06:29.945765+00');
INSERT INTO public.vote_comment VALUES ('Ud21004c2382a', 'C2bbd63b00224', 2, '2024-09-08 09:32:22.388466+00', '2024-09-08 09:32:23.554136+00');
INSERT INTO public.vote_comment VALUES ('Uc9fc0531972e', 'C54972a5fbc16', -1, '2024-08-24 17:06:51.47184+00', '2024-08-24 17:06:51.47184+00');
INSERT INTO public.vote_comment VALUES ('Ud21004c2382a', 'C070e739180d6', -2, '2024-09-08 09:32:26.632295+00', '2024-09-08 09:32:26.779812+00');
INSERT INTO public.vote_comment VALUES ('Uc9fc0531972e', 'Cac6ca02355da', 1, '2024-08-24 17:07:30.123395+00', '2024-08-24 17:07:30.123395+00');
INSERT INTO public.vote_comment VALUES ('Ucd6310f58337', 'Cbce32a9b256a', 0, '2024-08-24 17:05:15.181194+00', '2024-08-24 17:07:36.608932+00');
INSERT INTO public.vote_comment VALUES ('U1715ceca6772', 'Cbce32a9b256a', 2, '2024-08-24 17:06:53.695355+00', '2024-08-24 17:07:51.160391+00');
INSERT INTO public.vote_comment VALUES ('U7d494d508e5e', 'Cb117f464e558', -7, '2024-09-08 04:25:55.859197+00', '2024-09-08 04:26:37.131338+00');
INSERT INTO public.vote_comment VALUES ('U7d494d508e5e', 'C2bbd63b00224', -2, '2024-09-08 04:29:23.845349+00', '2024-09-08 04:29:24.419491+00');
INSERT INTO public.vote_comment VALUES ('U7d494d508e5e', 'C070e739180d6', 3, '2024-09-08 04:29:26.367334+00', '2024-09-08 04:29:35.60518+00');
INSERT INTO public.vote_comment VALUES ('U7d494d508e5e', 'Ce28175f0281e', 1, '2024-09-08 04:29:36.711913+00', '2024-09-08 04:29:36.711913+00');
INSERT INTO public.vote_comment VALUES ('Ud21004c2382a', 'C8d80016b8292', -3, '2024-09-08 09:32:27.945135+00', '2024-09-08 09:32:29.612712+00');


--
-- Data for Name: vote_user; Type: TABLE DATA; Schema: public; Owner: postgres
--

INSERT INTO public.vote_user VALUES ('U95f3426b8e5d', 'U499f24158a40', 1, '2024-07-11 16:07:07.362438+00', '2024-07-11 16:07:07.362438+00');
INSERT INTO public.vote_user VALUES ('U5a89e961863e', 'U7a8d8324441d', 1, '2024-08-08 15:38:23.750678+00', '2024-08-08 15:38:23.750678+00');
INSERT INTO public.vote_user VALUES ('U77a03e9a08af', 'U6d2f25cc4264', 1, '2024-08-16 13:55:32.363029+00', '2024-08-16 13:55:32.363029+00');
INSERT INTO public.vote_user VALUES ('Ub47d8c364c9e', 'Ub01f4ad1b03f', 1, '2024-08-17 13:47:44.148026+00', '2024-08-17 13:47:44.148026+00');
INSERT INTO public.vote_user VALUES ('U0be96c3b9883', 'U5d33a9be1633', 1, '2024-08-21 14:39:14.386184+00', '2024-08-21 14:39:14.386184+00');
INSERT INTO public.vote_user VALUES ('U389f9f24b31c', 'U7a8d8324441d', 1, '2023-10-01 09:32:00.473916+00', '2023-10-01 09:32:00.473916+00');
INSERT INTO public.vote_user VALUES ('U016217c34c6e', 'U9a89e0679dec', 1, '2023-10-01 09:32:00.473916+00', '2023-10-01 09:32:00.473916+00');
INSERT INTO public.vote_user VALUES ('U80e22da6d8c4', 'U0c17798eaab4', 1, '2023-10-01 09:32:00.473916+00', '2023-10-01 09:32:00.473916+00');
INSERT INTO public.vote_user VALUES ('U0c17798eaab4', 'Udece0afd9a8b', -1, '2023-10-01 09:32:00.473916+00', '2023-10-01 09:32:00.473916+00');
INSERT INTO public.vote_user VALUES ('Udece0afd9a8b', 'U1c285703fc63', 1, '2023-10-01 09:32:00.473916+00', '2023-10-01 09:32:39.802406+00');
INSERT INTO public.vote_user VALUES ('Udece0afd9a8b', 'Uadeb43da4abb', -1, '2023-10-01 09:32:39.802406+00', '2023-10-01 09:32:39.802406+00');
INSERT INTO public.vote_user VALUES ('Ue7a29d5409f2', 'Uc3c31b8a022f', -1, '2023-10-01 09:32:39.802406+00', '2023-10-01 09:32:39.802406+00');
INSERT INTO public.vote_user VALUES ('U9a2c85753a6d', 'Udece0afd9a8b', 1, '2023-10-01 09:32:39.802406+00', '2023-10-01 09:32:57.111585+00');
INSERT INTO public.vote_user VALUES ('U5d33a9be1633', 'U0be96c3b9883', 1, '2024-08-21 14:39:29.606142+00', '2024-08-21 14:39:29.606142+00');
INSERT INTO public.vote_user VALUES ('U0be96c3b9883', 'U55272fd6c264', 1, '2024-08-27 18:13:56.371474+00', '2024-08-27 18:13:56.371474+00');
INSERT INTO public.vote_user VALUES ('U1c285703fc63', 'Uad577360d968', 1, '2023-10-01 09:32:57.111585+00', '2023-10-01 09:32:57.111585+00');
INSERT INTO public.vote_user VALUES ('Udece0afd9a8b', 'Uc3c31b8a022f', -1, '2023-10-01 09:32:57.111585+00', '2023-10-01 09:32:57.111585+00');
INSERT INTO public.vote_user VALUES ('Uf5096f6ab14e', 'U9e42f6dab85a', -1, '2023-10-01 09:32:39.802406+00', '2023-10-01 09:34:20.131501+00');
INSERT INTO public.vote_user VALUES ('Ue7a29d5409f2', 'Uaa4e2be7a87a', -1, '2023-10-01 09:34:20.131501+00', '2023-10-01 09:34:20.131501+00');
INSERT INTO public.vote_user VALUES ('U7a8d8324441d', 'U1c285703fc63', -1, '2023-10-01 09:34:20.131501+00', '2023-10-01 09:34:20.131501+00');
INSERT INTO public.vote_user VALUES ('U6d2f25cc4264', 'U1c285703fc63', 1, '2023-10-05 11:17:45.141268+00', '2023-10-05 11:17:45.141268+00');
INSERT INTO public.vote_user VALUES ('U01814d1ec9ff', 'U499f24158a40', 1, '2023-10-07 10:40:58.932362+00', '2023-10-07 10:41:00.951229+00');
INSERT INTO public.vote_user VALUES ('U01814d1ec9ff', 'U02fbd7c8df4c', 1, '2023-10-08 16:56:07.228996+00', '2023-10-08 16:56:07.228996+00');
INSERT INTO public.vote_user VALUES ('U682c3380036f', 'U6240251593cd', 1, '2023-10-10 11:01:24.014135+00', '2023-10-10 11:01:24.014135+00');
INSERT INTO public.vote_user VALUES ('U6d2f25cc4264', 'Ud9df8116deba', 1, '2023-10-18 19:02:34.721319+00', '2023-10-18 19:02:34.721319+00');
INSERT INTO public.vote_user VALUES ('U8a78048d60f7', 'Uad577360d968', 1, '2023-10-19 14:39:13.812352+00', '2023-10-19 14:39:13.812352+00');
INSERT INTO public.vote_user VALUES ('U8a78048d60f7', 'U1c285703fc63', 1, '2023-10-19 14:39:25.934149+00', '2023-10-19 14:39:25.934149+00');
INSERT INTO public.vote_user VALUES ('U1e41b5f3adff', 'U6d2f25cc4264', 1, '2023-10-19 22:46:43.721064+00', '2023-10-19 22:46:43.721064+00');
INSERT INTO public.vote_user VALUES ('Ud04c89aaf453', 'U8a78048d60f7', 1, '2023-10-20 18:54:40.914286+00', '2023-10-20 18:54:40.914286+00');
INSERT INTO public.vote_user VALUES ('Uef7fbf45ef11', 'U6d2f25cc4264', 1, '2023-10-26 02:29:16.342871+00', '2023-10-26 02:29:16.342871+00');
INSERT INTO public.vote_user VALUES ('U499f24158a40', 'U6d2f25cc4264', 1, '2023-10-26 02:29:33.084375+00', '2023-10-26 02:29:33.084375+00');
INSERT INTO public.vote_user VALUES ('U1c285703fc63', 'U6d2f25cc4264', 1, '2023-10-26 02:29:49.952511+00', '2023-10-26 02:29:49.952511+00');
INSERT INTO public.vote_user VALUES ('U7a8d8324441d', 'U6d2f25cc4264', 1, '2023-10-26 02:30:21.962617+00', '2023-10-26 02:30:21.962617+00');
INSERT INTO public.vote_user VALUES ('U8a78048d60f7', 'U6d2f25cc4264', 1, '2023-10-30 05:37:27.325384+00', '2023-10-30 05:37:27.325384+00');
INSERT INTO public.vote_user VALUES ('U8a78048d60f7', 'U01814d1ec9ff', 1, '2023-10-30 05:38:02.402394+00', '2023-10-30 05:38:02.402394+00');
INSERT INTO public.vote_user VALUES ('U8a78048d60f7', 'Ud9df8116deba', 1, '2023-10-30 05:38:54.537969+00', '2023-10-30 05:38:54.537969+00');
INSERT INTO public.vote_user VALUES ('U8a78048d60f7', 'Ub93799d9400e', 1, '2023-10-30 14:52:14.061346+00', '2023-10-30 14:52:14.061346+00');
INSERT INTO public.vote_user VALUES ('U8a78048d60f7', 'Ud5b22ebf52f2', 1, '2023-10-30 14:54:09.36638+00', '2023-10-30 14:54:09.36638+00');
INSERT INTO public.vote_user VALUES ('U8a78048d60f7', 'U6240251593cd', 1, '2023-10-30 14:56:34.574497+00', '2023-10-30 14:56:34.574497+00');
INSERT INTO public.vote_user VALUES ('U1c285703fc63', 'U016217c34c6e', 1, '2023-09-26 10:56:27.087712+00', '2023-11-03 02:50:32.507645+00');
INSERT INTO public.vote_user VALUES ('Uc3c31b8a022f', 'U1c285703fc63', 1, '2023-09-26 10:56:27.087712+00', '2023-11-03 02:50:32.507645+00');
INSERT INTO public.vote_user VALUES ('U80e22da6d8c4', 'Ue7a29d5409f2', 1, '2023-09-26 10:56:27.087712+00', '2023-11-03 02:50:32.507645+00');
INSERT INTO public.vote_user VALUES ('Ue7a29d5409f2', 'U016217c34c6e', 1, '2023-09-26 10:56:27.087712+00', '2023-11-03 02:50:32.507645+00');
INSERT INTO public.vote_user VALUES ('U1c285703fc63', 'U9a2c85753a6d', 1, '2023-09-26 10:56:27.087712+00', '2023-11-03 02:50:32.507645+00');
INSERT INTO public.vote_user VALUES ('U1c285703fc63', 'U9e42f6dab85a', 1, '2023-09-26 10:56:27.087712+00', '2023-11-03 02:50:32.507645+00');
INSERT INTO public.vote_user VALUES ('U389f9f24b31c', 'Uc3c31b8a022f', 1, '2023-10-01 09:32:00.473916+00', '2023-11-03 02:50:32.507645+00');
INSERT INTO public.vote_user VALUES ('U9a2c85753a6d', 'Uf5096f6ab14e', 1, '2023-10-01 09:32:00.473916+00', '2023-11-03 02:50:32.507645+00');
INSERT INTO public.vote_user VALUES ('U80e22da6d8c4', 'U9e42f6dab85a', 1, '2023-10-01 09:32:00.473916+00', '2023-11-03 02:50:32.507645+00');
INSERT INTO public.vote_user VALUES ('U9a89e0679dec', 'U7a8d8324441d', 1, '2023-10-01 09:32:00.473916+00', '2023-11-03 02:50:32.507645+00');
INSERT INTO public.vote_user VALUES ('Ue7a29d5409f2', 'Udece0afd9a8b', 1, '2023-10-01 09:32:00.473916+00', '2023-11-03 02:50:32.507645+00');
INSERT INTO public.vote_user VALUES ('Uf5096f6ab14e', 'U7a8d8324441d', 1, '2023-10-01 09:32:39.802406+00', '2023-11-03 02:50:32.507645+00');
INSERT INTO public.vote_user VALUES ('U016217c34c6e', 'U80e22da6d8c4', 1, '2023-10-01 09:32:39.802406+00', '2023-11-03 02:50:32.507645+00');
INSERT INTO public.vote_user VALUES ('U0c17798eaab4', 'U389f9f24b31c', 1, '2023-10-01 09:32:39.802406+00', '2023-11-03 02:50:32.507645+00');
INSERT INTO public.vote_user VALUES ('U9e42f6dab85a', 'U80e22da6d8c4', 1, '2023-10-01 09:32:39.802406+00', '2023-11-03 02:50:32.507645+00');
INSERT INTO public.vote_user VALUES ('Uaa4e2be7a87a', 'Uadeb43da4abb', 1, '2023-10-01 09:32:57.111585+00', '2023-11-03 02:50:32.507645+00');
INSERT INTO public.vote_user VALUES ('U0c17798eaab4', 'Uad577360d968', 1, '2023-10-01 09:32:57.111585+00', '2023-11-03 02:50:32.507645+00');
INSERT INTO public.vote_user VALUES ('Ue7a29d5409f2', 'Uf2b0a6b1d423', 1, '2023-10-01 09:34:20.131501+00', '2023-11-03 02:50:32.507645+00');
INSERT INTO public.vote_user VALUES ('Uad577360d968', 'U389f9f24b31c', 1, '2023-10-01 09:32:39.802406+00', '2023-11-03 02:50:32.507645+00');
INSERT INTO public.vote_user VALUES ('U4bab0d326dee', 'U389f9f24b31c', 1, '2024-08-13 23:06:09.274431+00', '2024-08-13 23:06:09.274431+00');
INSERT INTO public.vote_user VALUES ('U77a03e9a08af', 'Ub01f4ad1b03f', 1, '2024-08-16 13:59:09.162847+00', '2024-08-16 13:59:09.162847+00');
INSERT INTO public.vote_user VALUES ('Ue45a5234f456', 'U26aca0e369c7', 1, '2024-08-24 17:14:08.918504+00', '2024-08-24 17:14:08.918504+00');
INSERT INTO public.vote_user VALUES ('U79466f73dc0c', 'U01814d1ec9ff', 1, '2023-11-24 22:03:46.440109+00', '2023-11-24 22:03:46.440109+00');
INSERT INTO public.vote_user VALUES ('U09cf1f359454', 'U8a78048d60f7', 1, '2023-11-08 06:45:44.519659+00', '2023-11-08 06:45:44.519659+00');
INSERT INTO public.vote_user VALUES ('U09cf1f359454', 'U0cd6bd2dde4f', 1, '2023-11-08 06:47:51.694208+00', '2023-11-08 06:47:51.694208+00');
INSERT INTO public.vote_user VALUES ('U09cf1f359454', 'U6d2f25cc4264', 1, '2023-11-08 06:48:01.915475+00', '2023-11-08 06:48:01.915475+00');
INSERT INTO public.vote_user VALUES ('U1bcba4fd7175', 'U09cf1f359454', 1, '2023-11-08 10:04:03.9962+00', '2023-11-08 10:04:03.9962+00');
INSERT INTO public.vote_user VALUES ('Uf82dbb4708ba', 'U0ae9f5d0bf02', 1, '2024-08-16 14:57:54.640242+00', '2024-08-16 14:57:54.640242+00');
INSERT INTO public.vote_user VALUES ('U0ae9f5d0bf02', 'Ub01f4ad1b03f', 1, '2024-08-17 13:19:06.71276+00', '2024-08-17 13:19:06.71276+00');
INSERT INTO public.vote_user VALUES ('Ueb139752b907', 'U79466f73dc0c', 1, '2023-12-26 11:03:18.989803+00', '2023-12-26 11:03:18.989803+00');
INSERT INTO public.vote_user VALUES ('Ub01f4ad1b03f', 'U499f24158a40', 1, '2023-12-28 08:09:31.37278+00', '2023-12-28 08:09:31.37278+00');
INSERT INTO public.vote_user VALUES ('Ub01f4ad1b03f', 'U6d2f25cc4264', 1, '2023-12-28 08:10:19.86418+00', '2023-12-28 08:10:19.86418+00');
INSERT INTO public.vote_user VALUES ('Ub01f4ad1b03f', 'Ud9df8116deba', 1, '2023-12-28 08:10:33.713664+00', '2023-12-28 08:10:33.713664+00');
INSERT INTO public.vote_user VALUES ('Ub01f4ad1b03f', 'U79466f73dc0c', 1, '2023-12-28 08:11:06.094378+00', '2023-12-28 08:11:06.094378+00');
INSERT INTO public.vote_user VALUES ('Ub01f4ad1b03f', 'U01814d1ec9ff', 1, '2023-12-28 08:11:18.076818+00', '2023-12-28 08:11:18.076818+00');
INSERT INTO public.vote_user VALUES ('Ub01f4ad1b03f', 'U8a78048d60f7', 1, '2023-12-28 08:13:21.785398+00', '2023-12-28 08:13:21.785398+00');
INSERT INTO public.vote_user VALUES ('Ub01f4ad1b03f', 'U0cd6bd2dde4f', 1, '2023-12-28 08:13:52.155063+00', '2023-12-28 08:13:52.155063+00');
INSERT INTO public.vote_user VALUES ('Ub01f4ad1b03f', 'U09cf1f359454', 1, '2023-12-28 08:13:59.578592+00', '2023-12-28 08:13:59.578592+00');
INSERT INTO public.vote_user VALUES ('U72f88cf28226', 'U499f24158a40', 1, '2024-01-26 14:53:20.095876+00', '2024-01-26 14:53:20.095876+00');
INSERT INTO public.vote_user VALUES ('U72f88cf28226', 'U6d2f25cc4264', 0, '2024-01-26 14:48:21.203503+00', '2024-01-26 14:54:50.542625+00');
INSERT INTO public.vote_user VALUES ('Uf6ce05bc4e5a', 'U499f24158a40', 1, '2024-01-26 16:58:18.460878+00', '2024-01-26 16:58:18.460878+00');


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

