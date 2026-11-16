SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: ar_internal_metadata; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ar_internal_metadata (
    key character varying NOT NULL,
    value character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: brands; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.brands (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    slug text NOT NULL,
    name text NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: conversation_events; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.conversation_events (
    id bigint NOT NULL,
    ticket_id uuid NOT NULL,
    brand_id uuid NOT NULL,
    kind text NOT NULL,
    actor text NOT NULL,
    data jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


--
-- Name: conversation_events_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.conversation_events_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: conversation_events_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.conversation_events_id_seq OWNED BY public.conversation_events.id;


--
-- Name: customers; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.customers (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    brand_id uuid NOT NULL,
    external_id text NOT NULL,
    name text,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: inbound_events; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.inbound_events (
    id bigint NOT NULL,
    brand_id uuid NOT NULL,
    channel text NOT NULL,
    provider_message_id text NOT NULL,
    payload jsonb DEFAULT '{}'::jsonb NOT NULL,
    received_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


--
-- Name: inbound_events_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.inbound_events_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: inbound_events_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.inbound_events_id_seq OWNED BY public.inbound_events.id;


--
-- Name: messages; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.messages (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    ticket_id uuid NOT NULL,
    brand_id uuid NOT NULL,
    inbound_event_id bigint,
    seq integer NOT NULL,
    sender text NOT NULL,
    body text NOT NULL,
    in_reply_to_seq integer,
    agent_turn_id uuid,
    stale boolean DEFAULT false NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT messages_sender_valid CHECK ((sender = ANY (ARRAY['customer'::text, 'bot'::text, 'analyst'::text, 'system'::text])))
);


--
-- Name: outbox_events; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.outbox_events (
    id bigint NOT NULL,
    event_id uuid NOT NULL,
    topic text NOT NULL,
    key text NOT NULL,
    payload jsonb NOT NULL,
    headers jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    published_at timestamp with time zone
);


--
-- Name: outbox_events_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.outbox_events_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: outbox_events_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.outbox_events_id_seq OWNED BY public.outbox_events.id;


--
-- Name: processed_events; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.processed_events (
    consumer_name text NOT NULL,
    event_id uuid NOT NULL,
    processed_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


--
-- Name: schema_migrations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.schema_migrations (
    version character varying NOT NULL
);


--
-- Name: tickets; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.tickets (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    brand_id uuid NOT NULL,
    customer_id uuid NOT NULL,
    channel text NOT NULL,
    mode text DEFAULT 'ai'::text NOT NULL,
    handoff_epoch integer DEFAULT 0 NOT NULL,
    last_seq integer DEFAULT 0 NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT tickets_channel_valid CHECK ((channel = ANY (ARRAY['app_chat'::text, 'whatsapp'::text, 'email'::text]))),
    CONSTRAINT tickets_mode_valid CHECK ((mode = ANY (ARRAY['ai'::text, 'pending_human'::text, 'human'::text, 'closed'::text])))
);


--
-- Name: users; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.users (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name text NOT NULL,
    role text NOT NULL,
    token_digest text NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT users_role_valid CHECK ((role = ANY (ARRAY['customer'::text, 'analyst'::text, 'ops'::text, 'bot'::text])))
);


--
-- Name: conversation_events id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.conversation_events ALTER COLUMN id SET DEFAULT nextval('public.conversation_events_id_seq'::regclass);


--
-- Name: inbound_events id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inbound_events ALTER COLUMN id SET DEFAULT nextval('public.inbound_events_id_seq'::regclass);


--
-- Name: outbox_events id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.outbox_events ALTER COLUMN id SET DEFAULT nextval('public.outbox_events_id_seq'::regclass);


--
-- Name: ar_internal_metadata ar_internal_metadata_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ar_internal_metadata
    ADD CONSTRAINT ar_internal_metadata_pkey PRIMARY KEY (key);


--
-- Name: brands brands_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.brands
    ADD CONSTRAINT brands_pkey PRIMARY KEY (id);


--
-- Name: conversation_events conversation_events_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.conversation_events
    ADD CONSTRAINT conversation_events_pkey PRIMARY KEY (id);


--
-- Name: customers customers_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.customers
    ADD CONSTRAINT customers_pkey PRIMARY KEY (id);


--
-- Name: inbound_events inbound_events_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inbound_events
    ADD CONSTRAINT inbound_events_pkey PRIMARY KEY (id);


--
-- Name: messages messages_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.messages
    ADD CONSTRAINT messages_pkey PRIMARY KEY (id);


--
-- Name: outbox_events outbox_events_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.outbox_events
    ADD CONSTRAINT outbox_events_pkey PRIMARY KEY (id);


--
-- Name: processed_events processed_events_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.processed_events
    ADD CONSTRAINT processed_events_pkey PRIMARY KEY (consumer_name, event_id);


--
-- Name: schema_migrations schema_migrations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.schema_migrations
    ADD CONSTRAINT schema_migrations_pkey PRIMARY KEY (version);


--
-- Name: tickets tickets_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tickets
    ADD CONSTRAINT tickets_pkey PRIMARY KEY (id);


--
-- Name: users users_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_pkey PRIMARY KEY (id);


--
-- Name: index_brands_on_slug; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_brands_on_slug ON public.brands USING btree (slug);


--
-- Name: index_conversation_events_on_ticket_id_and_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_conversation_events_on_ticket_id_and_id ON public.conversation_events USING btree (ticket_id, id);


--
-- Name: index_customers_on_brand_id_and_external_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_customers_on_brand_id_and_external_id ON public.customers USING btree (brand_id, external_id);


--
-- Name: index_inbound_events_on_channel_and_provider_message_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_inbound_events_on_channel_and_provider_message_id ON public.inbound_events USING btree (channel, provider_message_id);


--
-- Name: index_messages_on_agent_turn_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_messages_on_agent_turn_id ON public.messages USING btree (agent_turn_id);


--
-- Name: index_messages_on_inbound_event_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_messages_on_inbound_event_id ON public.messages USING btree (inbound_event_id);


--
-- Name: index_messages_on_ticket_id_and_seq; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_messages_on_ticket_id_and_seq ON public.messages USING btree (ticket_id, seq);


--
-- Name: index_outbox_events_on_event_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_outbox_events_on_event_id ON public.outbox_events USING btree (event_id);


--
-- Name: index_outbox_events_pending; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_outbox_events_pending ON public.outbox_events USING btree (id) WHERE (published_at IS NULL);


--
-- Name: index_tickets_on_brand_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_tickets_on_brand_id ON public.tickets USING btree (brand_id);


--
-- Name: index_tickets_one_open_per_customer_channel; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_tickets_one_open_per_customer_channel ON public.tickets USING btree (brand_id, customer_id, channel) WHERE (mode <> 'closed'::text);


--
-- Name: index_users_on_token_digest; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_users_on_token_digest ON public.users USING btree (token_digest);


--
-- Name: messages fk_rails_19770f78ed; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.messages
    ADD CONSTRAINT fk_rails_19770f78ed FOREIGN KEY (brand_id) REFERENCES public.brands(id);


--
-- Name: messages fk_rails_1a0b99fe7e; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.messages
    ADD CONSTRAINT fk_rails_1a0b99fe7e FOREIGN KEY (ticket_id) REFERENCES public.tickets(id);


--
-- Name: tickets fk_rails_1dfd143528; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tickets
    ADD CONSTRAINT fk_rails_1dfd143528 FOREIGN KEY (brand_id) REFERENCES public.brands(id);


--
-- Name: conversation_events fk_rails_2bc24c46db; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.conversation_events
    ADD CONSTRAINT fk_rails_2bc24c46db FOREIGN KEY (brand_id) REFERENCES public.brands(id);


--
-- Name: tickets fk_rails_5685ed71b0; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tickets
    ADD CONSTRAINT fk_rails_5685ed71b0 FOREIGN KEY (customer_id) REFERENCES public.customers(id);


--
-- Name: conversation_events fk_rails_9edaa1a04d; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.conversation_events
    ADD CONSTRAINT fk_rails_9edaa1a04d FOREIGN KEY (ticket_id) REFERENCES public.tickets(id);


--
-- Name: messages fk_rails_c631bfbc65; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.messages
    ADD CONSTRAINT fk_rails_c631bfbc65 FOREIGN KEY (inbound_event_id) REFERENCES public.inbound_events(id);


--
-- Name: customers fk_rails_df42b7b625; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.customers
    ADD CONSTRAINT fk_rails_df42b7b625 FOREIGN KEY (brand_id) REFERENCES public.brands(id);


--
-- Name: inbound_events fk_rails_ea57aae112; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inbound_events
    ADD CONSTRAINT fk_rails_ea57aae112 FOREIGN KEY (brand_id) REFERENCES public.brands(id);


--
-- PostgreSQL database dump complete
--

SET search_path TO "$user", public;

INSERT INTO "schema_migrations" (version) VALUES
('20261115000003'),
('20261115000002'),
('20261115000001');

