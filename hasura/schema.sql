SET check_function_bodies = false;
CREATE TABLE public.beacon (
    id text DEFAULT concat('b', "substring"((gen_random_uuid())::text, '\w{12}'::text)) NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    user_id text NOT NULL,
    title text NOT NULL,
    description text NOT NULL,
    timerange tstzrange,
    place public.geography,
    enabled boolean DEFAULT true NOT NULL,
    has_picture boolean DEFAULT false NOT NULL,
    comments_count integer DEFAULT 0 NOT NULL,
    CONSTRAINT beacon__description_len CHECK ((char_length(description) <= 2048)),
    CONSTRAINT beacon__title_len CHECK ((char_length(title) <= 128))
);
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
CREATE FUNCTION public.beacon_get_is_pinned(beacon_row public.beacon, hasura_session json) RETURNS boolean
    LANGUAGE sql STABLE
    AS $$
SELECT COALESCE(
(SELECT true AS "is_pinned" FROM beacon_pinned WHERE
  user_id = (hasura_session ->> 'x-hasura-user-id')::TEXT AND beacon_id = beacon_row.id),
  false);
$$;
CREATE FUNCTION public.beacon_get_my_vote(beacon_row public.beacon, hasura_session json) RETURNS integer
    LANGUAGE sql STABLE
    AS $$
  SELECT COALESCE(
    (SELECT amount FROM vote_beacon WHERE subject = (hasura_session ->> 'x-hasura-user-id')::TEXT AND object = beacon_row.id),
    0
  );
$$;
CREATE TABLE public.comment (
    id text DEFAULT concat('C', "substring"((gen_random_uuid())::text, '\w{12}'::text)) NOT NULL,
    user_id text NOT NULL,
    content text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    beacon_id text NOT NULL
);
CREATE FUNCTION public.comment_get_my_vote(comment_row public.comment, hasura_session json) RETURNS integer
    LANGUAGE sql STABLE
    AS $$
  SELECT COALESCE((SELECT amount FROM vote_comment WHERE subject = (hasura_session ->> 'x-hasura-user-id')::TEXT AND object = comment_row.id), 0);
$$;
CREATE FUNCTION public.decrement_beacon_comments_count() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    UPDATE beacon SET comments_count = comments_count - 1 WHERE id = NEW.beacon_id;
    RETURN NEW;
END;
$$;
CREATE FUNCTION public.increment_beacon_comments_count() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    UPDATE beacon SET comments_count = comments_count + 1 WHERE id = NEW.beacon_id;
    RETURN NEW;
END;
$$;
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
CREATE TABLE public."user" (
    id text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    title text NOT NULL,
    description text NOT NULL,
    has_picture boolean DEFAULT false NOT NULL,
    CONSTRAINT user__description_len CHECK ((char_length(description) <= 2048)),
    CONSTRAINT user__title_len CHECK ((char_length(title) <= 128))
);
CREATE FUNCTION public.user_get_my_vote(user_row public."user", hasura_session json) RETURNS integer
    LANGUAGE sql STABLE
    AS $$
  SELECT amount FROM vote_user WHERE subject = (hasura_session ->> 'x-hasura-user-id')::TEXT AND object = user_row.id;
$$;
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
CREATE TABLE public.beacon_hidden (
    user_id text NOT NULL,
    beacon_id text NOT NULL,
    hidden_until timestamp with time zone NOT NULL
);
CREATE TABLE public.beacon_pinned (
    user_id text NOT NULL,
    beacon_id text NOT NULL
);
CREATE TABLE public.vote_beacon (
    subject text NOT NULL,
    object text NOT NULL,
    amount integer NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);
CREATE TABLE public.vote_comment (
    subject text NOT NULL,
    object text NOT NULL,
    amount integer NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);
CREATE TABLE public.vote_user (
    subject text NOT NULL,
    object text NOT NULL,
    amount integer NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);
ALTER TABLE ONLY public.beacon_hidden
    ADD CONSTRAINT beacon_hidden_pkey PRIMARY KEY (user_id, beacon_id);
ALTER TABLE ONLY public.beacon_pinned
    ADD CONSTRAINT beacon_pinned_pkey PRIMARY KEY (user_id, beacon_id);
ALTER TABLE ONLY public.beacon
    ADD CONSTRAINT beacon_pkey PRIMARY KEY (id);
ALTER TABLE ONLY public.comment
    ADD CONSTRAINT comment_pkey PRIMARY KEY (id);
ALTER TABLE ONLY public."user"
    ADD CONSTRAINT user_pkey PRIMARY KEY (id);
ALTER TABLE ONLY public.vote_beacon
    ADD CONSTRAINT vote_beacon_pkey PRIMARY KEY (subject, object);
ALTER TABLE ONLY public.vote_comment
    ADD CONSTRAINT vote_comment_pkey PRIMARY KEY (subject, object);
ALTER TABLE ONLY public.vote_user
    ADD CONSTRAINT vote_user_pkey PRIMARY KEY (subject, object);
CREATE INDEX beacon_author_id ON public.beacon USING btree (user_id);
CREATE TRIGGER decrement_beacon_comments_count AFTER DELETE ON public.comment FOR EACH ROW EXECUTE FUNCTION public.decrement_beacon_comments_count();
CREATE TRIGGER increment_beacon_comments_count AFTER INSERT ON public.comment FOR EACH ROW EXECUTE FUNCTION public.increment_beacon_comments_count();
CREATE TRIGGER set_public_beacon_updated_at BEFORE UPDATE ON public.beacon FOR EACH ROW EXECUTE FUNCTION public.set_current_timestamp_updated_at();
COMMENT ON TRIGGER set_public_beacon_updated_at ON public.beacon IS 'trigger to set value of column "updated_at" to current timestamp on row update';
CREATE TRIGGER set_public_user_updated_at BEFORE UPDATE ON public."user" FOR EACH ROW EXECUTE FUNCTION public.set_current_timestamp_updated_at();
COMMENT ON TRIGGER set_public_user_updated_at ON public."user" IS 'trigger to set value of column "updated_at" to current timestamp on row update';
CREATE TRIGGER set_public_vote_beacon_updated_at BEFORE UPDATE ON public.vote_beacon FOR EACH ROW EXECUTE FUNCTION public.set_current_timestamp_updated_at();
COMMENT ON TRIGGER set_public_vote_beacon_updated_at ON public.vote_beacon IS 'trigger to set value of column "updated_at" to current timestamp on row update';
CREATE TRIGGER set_public_vote_comment_updated_at BEFORE UPDATE ON public.vote_comment FOR EACH ROW EXECUTE FUNCTION public.set_current_timestamp_updated_at();
COMMENT ON TRIGGER set_public_vote_comment_updated_at ON public.vote_comment IS 'trigger to set value of column "updated_at" to current timestamp on row update';
CREATE TRIGGER set_public_vote_user_updated_at BEFORE UPDATE ON public.vote_user FOR EACH ROW EXECUTE FUNCTION public.set_current_timestamp_updated_at();
COMMENT ON TRIGGER set_public_vote_user_updated_at ON public.vote_user IS 'trigger to set value of column "updated_at" to current timestamp on row update';
ALTER TABLE ONLY public.beacon_hidden
    ADD CONSTRAINT beacon_hidden_beacon_id_fkey FOREIGN KEY (beacon_id) REFERENCES public.beacon(id) ON UPDATE RESTRICT ON DELETE CASCADE;
ALTER TABLE ONLY public.beacon_hidden
    ADD CONSTRAINT beacon_hidden_user_id_fkey FOREIGN KEY (user_id) REFERENCES public."user"(id) ON UPDATE RESTRICT ON DELETE CASCADE;
ALTER TABLE ONLY public.beacon_pinned
    ADD CONSTRAINT beacon_pinned_beacon_id_fkey FOREIGN KEY (beacon_id) REFERENCES public.beacon(id) ON UPDATE CASCADE ON DELETE CASCADE;
ALTER TABLE ONLY public.beacon_pinned
    ADD CONSTRAINT beacon_pinned_user_id_fkey FOREIGN KEY (user_id) REFERENCES public."user"(id) ON UPDATE CASCADE ON DELETE CASCADE;
ALTER TABLE ONLY public.beacon
    ADD CONSTRAINT beacon_user_id_fkey FOREIGN KEY (user_id) REFERENCES public."user"(id) ON UPDATE CASCADE ON DELETE CASCADE;
ALTER TABLE ONLY public.comment
    ADD CONSTRAINT comment_beacon_id_fkey FOREIGN KEY (beacon_id) REFERENCES public.beacon(id) ON UPDATE CASCADE ON DELETE CASCADE;
ALTER TABLE ONLY public.comment
    ADD CONSTRAINT comment_user_id_fkey FOREIGN KEY (user_id) REFERENCES public."user"(id) ON UPDATE CASCADE ON DELETE CASCADE;
ALTER TABLE ONLY public.vote_beacon
    ADD CONSTRAINT vote_beacon_object_fkey FOREIGN KEY (object) REFERENCES public.beacon(id) ON UPDATE RESTRICT ON DELETE CASCADE;
ALTER TABLE ONLY public.vote_beacon
    ADD CONSTRAINT vote_beacon_subject_fkey FOREIGN KEY (subject) REFERENCES public."user"(id) ON UPDATE RESTRICT ON DELETE CASCADE;
ALTER TABLE ONLY public.vote_comment
    ADD CONSTRAINT vote_comment_object_fkey FOREIGN KEY (object) REFERENCES public.comment(id) ON UPDATE RESTRICT ON DELETE CASCADE;
ALTER TABLE ONLY public.vote_comment
    ADD CONSTRAINT vote_comment_subject_fkey FOREIGN KEY (subject) REFERENCES public."user"(id) ON UPDATE RESTRICT ON DELETE CASCADE;
ALTER TABLE ONLY public.vote_user
    ADD CONSTRAINT vote_user_object_fkey FOREIGN KEY (object) REFERENCES public."user"(id) ON UPDATE RESTRICT ON DELETE CASCADE;
ALTER TABLE ONLY public.vote_user
    ADD CONSTRAINT vote_user_subject_fkey FOREIGN KEY (subject) REFERENCES public."user"(id) ON UPDATE RESTRICT ON DELETE CASCADE;
