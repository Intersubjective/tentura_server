--
-- PostgreSQL database dump
--

-- Dumped from database version 16.3
-- Dumped by pg_dump version 16.3

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
    CONSTRAINT beacon__description_len CHECK ((char_length(description) <= 2048)),
    CONSTRAINT beacon__title_len CHECK ((char_length(title) <= 128))
);


ALTER TABLE public.beacon OWNER TO postgres;

--
-- Name: beacon_get_is_hidden(public.beacon, json); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.beacon_get_is_hidden(beacon_row public.beacon, hasura_session json) RETURNS boolean
    LANGUAGE sql STABLE
    AS $$

SELECT COALESCE(

(SELECT true AS "is_hidden" FROM beacon_hidden WHERE

  user_id = (hasura_session ->> 'x-hasura-user-id')::TEXT AND

  beacon_id = beacon_row.id AND

  hidden_until > now()),

  false);

$$;


ALTER FUNCTION public.beacon_get_is_hidden(beacon_row public.beacon, hasura_session json) OWNER TO postgres;

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
    LANGUAGE sql STABLE
    AS $$

  SELECT COALESCE(

    (SELECT amount FROM vote_beacon WHERE subject = (hasura_session ->> 'x-hasura-user-id')::TEXT AND object = beacon_row.id),

    0

  );

$$;


ALTER FUNCTION public.beacon_get_my_vote(beacon_row public.beacon, hasura_session json) OWNER TO postgres;

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
    (0)::double precision AS amount
  WHERE false;


ALTER VIEW public.edge OWNER TO postgres;

--
-- Name: graph(text, text, text, boolean, integer, integer, integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.graph(ego text, focus text, context text DEFAULT ''::text, positive_only boolean DEFAULT true, "limit" integer DEFAULT 5, index integer DEFAULT 0, count integer DEFAULT 5) RETURNS SETOF public.edge
    LANGUAGE c IMMUTABLE
    AS '$libdir/pgmer2', 'mr_graph_wrapper';


ALTER FUNCTION public.graph(ego text, focus text, context text, positive_only boolean, "limit" integer, index integer, count integer) OWNER TO postgres;

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
-- Name: edges; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.edges AS
 SELECT beacon.id AS src,
    beacon.user_id AS dst,
    1 AS amount
   FROM public.beacon
UNION
 SELECT beacon.user_id AS src,
    beacon.id AS dst,
    1 AS amount
   FROM public.beacon
UNION
 SELECT comment.id AS src,
    comment.user_id AS dst,
    1 AS amount
   FROM public.comment
UNION
 SELECT comment.user_id AS src,
    comment.id AS dst,
    1 AS amount
   FROM public.comment
UNION
 SELECT vote_user.subject AS src,
    vote_user.object AS dst,
    vote_user.amount
   FROM public.vote_user
UNION
 SELECT vote_beacon.subject AS src,
    vote_beacon.object AS dst,
    vote_beacon.amount
   FROM public.vote_beacon
UNION
 SELECT vote_comment.subject AS src,
    vote_comment.object AS dst,
    vote_comment.amount
   FROM public.vote_comment;


ALTER VIEW public.edges OWNER TO postgres;

--
-- Name: init_graph(); Type: PROCEDURE; Schema: public; Owner: postgres
--

CREATE PROCEDURE public.init_graph()
    LANGUAGE sql
    BEGIN ATOMIC
 SELECT public.mr_put_edge(edges.src, edges.dst, (edges.amount)::double precision, ''::text) AS mr_put_edge
    FROM public.edges;
END;


ALTER PROCEDURE public.init_graph() OWNER TO postgres;

--
-- Name: mr_calculate(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.mr_calculate() RETURNS text
    LANGUAGE c STRICT
    AS '$libdir/pgmer2', 'mr_zerorec_wrapper';


ALTER FUNCTION public.mr_calculate() OWNER TO postgres;

--
-- Name: notify_meritrank_entity_mutation(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.notify_meritrank_entity_mutation() RETURNS trigger
    LANGUAGE plpgsql
    AS $$

BEGIN

    IF (TG_OP = 'DELETE') THEN

        PERFORM pg_notify('edges', json_build_object('src', NEW.id, 'dest', NEW.user_id, 'weight', 0)::text);

        PERFORM pg_notify('edges', json_build_object('src', NEW.user_id, 'dest', NEW.id, 'weight', 0)::text);

    ELSIF (TG_OP = 'INSERT') THEN

        PERFORM pg_notify('edges', json_build_object('src', NEW.id, 'dest', NEW.user_id, 'weight', 1)::text);

        PERFORM pg_notify('edges', json_build_object('src', NEW.user_id, 'dest', NEW.id, 'weight', 1)::text);

    END IF;

    RETURN NEW;

END;

$$;


ALTER FUNCTION public.notify_meritrank_entity_mutation() OWNER TO postgres;

--
-- Name: notify_meritrank_vote_mutation(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.notify_meritrank_vote_mutation() RETURNS trigger
    LANGUAGE plpgsql
    AS $$

BEGIN

    PERFORM mr_put_edge(NEW.subject, NEW.object, NEW.amount, '');

    RETURN NEW;

END;

$$;


ALTER FUNCTION public.notify_meritrank_vote_mutation() OWNER TO postgres;

--
-- Name: public_vote_for_beacon_on_create(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.public_vote_for_beacon_on_create() RETURNS trigger
    LANGUAGE plpgsql
    AS $$

DECLARE

  session_variables json;

BEGIN

  session_variables := current_setting('hasura.user', 't');

  INSERT INTO vote_beacon (subject, object, amount)

    VALUES ((session_variables->>'x-hasura-user-id')::text, NEW.id, 1);

  RETURN NEW;

END;

$$;


ALTER FUNCTION public.public_vote_for_beacon_on_create() OWNER TO postgres;

--
-- Name: scores(text, boolean, text, text, double precision, double precision, double precision, double precision, integer, integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.scores(ego text, hide_personal boolean DEFAULT true, context_ text DEFAULT ''::text, start_with text DEFAULT ''::text, score_lt double precision DEFAULT NULL::double precision, score_lte double precision DEFAULT NULL::double precision, score_gt double precision DEFAULT NULL::double precision, score_gte double precision DEFAULT NULL::double precision, index integer DEFAULT 0, count integer DEFAULT 10) RETURNS SETOF public.edge
    LANGUAGE c IMMUTABLE
    AS '$libdir/pgmer2', 'mr_scores_wrapper';


ALTER FUNCTION public.scores(ego text, hide_personal boolean, context_ text, start_with text, score_lt double precision, score_lte double precision, score_gt double precision, score_gte double precision, index integer, count integer) OWNER TO postgres;

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
-- Name: vote_for_comment_on_create(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.vote_for_comment_on_create() RETURNS trigger
    LANGUAGE plpgsql
    AS $$

DECLARE

  session_variables json;

BEGIN

  session_variables := current_setting('hasura.user', 't');

  INSERT INTO vote_comment (subject, object, amount)

    VALUES ((session_variables->>'x-hasura-user-id')::text, NEW.id, 1);

  RETURN NEW;

END;

$$;


ALTER FUNCTION public.vote_for_comment_on_create() OWNER TO postgres;

--
-- Name: vote_for_zero_on_create(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.vote_for_zero_on_create() RETURNS trigger
    LANGUAGE plpgsql
    AS $$

BEGIN

  INSERT INTO vote_user (subject, object, amount) VALUES (NEW.id, 'U000000000000', 1);

  RETURN NEW;

END;

$$;


ALTER FUNCTION public.vote_for_zero_on_create() OWNER TO postgres;

--
-- Name: beacon_pinned; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.beacon_pinned (
    user_id text NOT NULL,
    beacon_id text NOT NULL
);


ALTER TABLE public.beacon_pinned OWNER TO postgres;

--
-- Data for Name: user; Type: TABLE DATA; Schema: public; Owner: postgres
--

INSERT INTO public."user" VALUES ('U000000000000', DEFAULT, DEFAULT, 'Tentura', 'Root', true, 'U000000000000');


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
-- Name: beacon notify_meritrank_entity_beacon_mutation; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER notify_meritrank_entity_beacon_mutation AFTER INSERT OR DELETE ON public.beacon FOR EACH ROW EXECUTE FUNCTION public.notify_meritrank_entity_mutation();


--
-- Name: comment notify_meritrank_entity_comment_mutation; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER notify_meritrank_entity_comment_mutation AFTER INSERT OR DELETE ON public.comment FOR EACH ROW EXECUTE FUNCTION public.notify_meritrank_entity_mutation();


--
-- Name: vote_beacon notify_meritrank_vote_beacon_mutation; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER notify_meritrank_vote_beacon_mutation AFTER INSERT OR UPDATE ON public.vote_beacon FOR EACH ROW EXECUTE FUNCTION public.notify_meritrank_vote_mutation();


--
-- Name: vote_comment notify_meritrank_vote_comment_mutation; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER notify_meritrank_vote_comment_mutation AFTER INSERT OR UPDATE ON public.vote_comment FOR EACH ROW EXECUTE FUNCTION public.notify_meritrank_vote_mutation();


--
-- Name: vote_user notify_meritrank_vote_user_mutation; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER notify_meritrank_vote_user_mutation AFTER INSERT OR UPDATE ON public.vote_user FOR EACH ROW EXECUTE FUNCTION public.notify_meritrank_vote_mutation();


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
-- Name: user vote_for_zero_on_create; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER vote_for_zero_on_create AFTER INSERT ON public."user" FOR EACH ROW EXECUTE FUNCTION public.vote_for_zero_on_create();


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

