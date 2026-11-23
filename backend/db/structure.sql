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
-- Name: closing_summaries; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.closing_summaries (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    ticket_id uuid NOT NULL,
    brand_id uuid NOT NULL,
    customer_id uuid NOT NULL,
    version integer NOT NULL,
    source text NOT NULL,
    text text NOT NULL,
    expires_at timestamp with time zone NOT NULL,
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
    updated_at timestamp(6) without time zone NOT NULL,
    memory_erased_at timestamp with time zone
);


--
-- Name: decisions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.decisions (
    id bigint NOT NULL,
    ticket_id uuid NOT NULL,
    brand_id uuid NOT NULL,
    step text NOT NULL,
    actor text NOT NULL,
    rule_set_id uuid,
    rule_set_version integer,
    matched_rule_id text,
    facts jsonb DEFAULT '{}'::jsonb NOT NULL,
    output jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


--
-- Name: decisions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.decisions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: decisions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.decisions_id_seq OWNED BY public.decisions.id;


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
-- Name: incidents; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.incidents (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    brand_id uuid NOT NULL,
    key character varying NOT NULL,
    label character varying NOT NULL,
    status character varying DEFAULT 'open'::character varying NOT NULL,
    title character varying NOT NULL,
    draft_reply text NOT NULL,
    title_source character varying DEFAULT 'template'::character varying NOT NULL,
    prompt_version character varying,
    model character varying,
    opened_at timestamp(6) without time zone NOT NULL,
    resolved_at timestamp(6) without time zone,
    resolved_by_id uuid,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT incidents_status_check CHECK (((status)::text = ANY ((ARRAY['open'::character varying, 'resolved'::character varying])::text[])))
);


--
-- Name: memory_erasures; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.memory_erasures (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    brand_id uuid NOT NULL,
    customer_id uuid NOT NULL,
    requested_by_id uuid NOT NULL,
    summaries_deleted integer NOT NULL,
    created_at timestamp with time zone NOT NULL
);


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
    published_at timestamp with time zone,
    attempts integer DEFAULT 0 NOT NULL,
    last_error text,
    dead_at timestamp with time zone,
    discarded_at timestamp with time zone
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
-- Name: priority_levels; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.priority_levels (
    code text NOT NULL,
    name text NOT NULL,
    first_response_minutes integer NOT NULL,
    "position" integer NOT NULL,
    CONSTRAINT priority_levels_minutes_positive CHECK ((first_response_minutes > 0))
);


--
-- Name: processed_events; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.processed_events (
    consumer_name text NOT NULL,
    event_id uuid NOT NULL,
    processed_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


--
-- Name: queues; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.queues (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    brand_id uuid NOT NULL,
    slug text NOT NULL,
    name text NOT NULL,
    "default" boolean DEFAULT false NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    team_id uuid NOT NULL
);


--
-- Name: rule_sets; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.rule_sets (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    brand_id uuid NOT NULL,
    version integer NOT NULL,
    status text DEFAULT 'draft'::text NOT NULL,
    rules jsonb DEFAULT '[]'::jsonb NOT NULL,
    created_by_id uuid,
    published_at timestamp with time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT rule_sets_status_valid CHECK ((status = ANY (ARRAY['draft'::text, 'published'::text, 'archived'::text])))
);


--
-- Name: schema_migrations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.schema_migrations (
    version character varying NOT NULL
);


--
-- Name: team_memberships; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.team_memberships (
    user_id uuid NOT NULL,
    team_id uuid NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


--
-- Name: teams; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.teams (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    slug text NOT NULL,
    name text NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
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
    queue_id uuid,
    priority text DEFAULT 'p3'::text NOT NULL,
    assignee_id uuid,
    lock_version integer DEFAULT 0 NOT NULL,
    escalation_trigger text,
    escalation_reason text,
    escalated_at timestamp with time zone,
    first_response_due_at timestamp with time zone,
    first_human_response_at timestamp with time zone,
    handoff_brief jsonb,
    awaiting_agent_since timestamp with time zone,
    tags text[] DEFAULT '{}'::text[] NOT NULL,
    closed_at timestamp with time zone,
    resolution_code text,
    resolution_note text,
    llm_facts jsonb DEFAULT '{}'::jsonb NOT NULL,
    incident_id uuid,
    CONSTRAINT tickets_channel_valid CHECK ((channel = ANY (ARRAY['app_chat'::text, 'whatsapp'::text, 'email'::text]))),
    CONSTRAINT tickets_mode_valid CHECK ((mode = ANY (ARRAY['ai'::text, 'pending_human'::text, 'human'::text, 'closed'::text]))),
    CONSTRAINT tickets_resolution_code_valid CHECK (((resolution_code IS NULL) OR (resolution_code = ANY (ARRAY['resolved'::text, 'no_customer_response'::text, 'duplicate'::text, 'forwarded'::text, 'ai_resolved'::text])))),
    CONSTRAINT tickets_resolution_note_length CHECK ((char_length(resolution_note) <= 2000))
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
-- Name: decisions id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.decisions ALTER COLUMN id SET DEFAULT nextval('public.decisions_id_seq'::regclass);


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
-- Name: closing_summaries closing_summaries_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.closing_summaries
    ADD CONSTRAINT closing_summaries_pkey PRIMARY KEY (id);


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
-- Name: decisions decisions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.decisions
    ADD CONSTRAINT decisions_pkey PRIMARY KEY (id);


--
-- Name: inbound_events inbound_events_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inbound_events
    ADD CONSTRAINT inbound_events_pkey PRIMARY KEY (id);


--
-- Name: incidents incidents_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.incidents
    ADD CONSTRAINT incidents_pkey PRIMARY KEY (id);


--
-- Name: memory_erasures memory_erasures_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.memory_erasures
    ADD CONSTRAINT memory_erasures_pkey PRIMARY KEY (id);


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
-- Name: priority_levels priority_levels_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.priority_levels
    ADD CONSTRAINT priority_levels_pkey PRIMARY KEY (code);


--
-- Name: processed_events processed_events_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.processed_events
    ADD CONSTRAINT processed_events_pkey PRIMARY KEY (consumer_name, event_id);


--
-- Name: queues queues_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.queues
    ADD CONSTRAINT queues_pkey PRIMARY KEY (id);


--
-- Name: rule_sets rule_sets_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.rule_sets
    ADD CONSTRAINT rule_sets_pkey PRIMARY KEY (id);


--
-- Name: schema_migrations schema_migrations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.schema_migrations
    ADD CONSTRAINT schema_migrations_pkey PRIMARY KEY (version);


--
-- Name: team_memberships team_memberships_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.team_memberships
    ADD CONSTRAINT team_memberships_pkey PRIMARY KEY (user_id, team_id);


--
-- Name: teams teams_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.teams
    ADD CONSTRAINT teams_pkey PRIMARY KEY (id);


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
-- Name: index_closing_summaries_on_customer_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_closing_summaries_on_customer_id ON public.closing_summaries USING btree (customer_id);


--
-- Name: index_closing_summaries_on_ticket_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_closing_summaries_on_ticket_id ON public.closing_summaries USING btree (ticket_id);


--
-- Name: index_conversation_events_on_ticket_id_and_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_conversation_events_on_ticket_id_and_id ON public.conversation_events USING btree (ticket_id, id);


--
-- Name: index_customers_on_brand_id_and_external_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_customers_on_brand_id_and_external_id ON public.customers USING btree (brand_id, external_id);


--
-- Name: index_decisions_on_ticket_id_and_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_decisions_on_ticket_id_and_id ON public.decisions USING btree (ticket_id, id);


--
-- Name: index_inbound_events_on_channel_and_provider_message_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_inbound_events_on_channel_and_provider_message_id ON public.inbound_events USING btree (channel, provider_message_id);


--
-- Name: index_incidents_on_brand_id_and_status_and_opened_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_incidents_on_brand_id_and_status_and_opened_at ON public.incidents USING btree (brand_id, status, opened_at);


--
-- Name: index_incidents_open_by_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_incidents_open_by_key ON public.incidents USING btree (brand_id, key) WHERE ((status)::text = 'open'::text);


--
-- Name: index_memory_erasures_on_customer_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_memory_erasures_on_customer_id ON public.memory_erasures USING btree (customer_id);


--
-- Name: index_memory_erasures_on_requested_by_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_memory_erasures_on_requested_by_id ON public.memory_erasures USING btree (requested_by_id);


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
-- Name: index_queues_on_brand_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_queues_on_brand_id ON public.queues USING btree (brand_id);


--
-- Name: index_queues_on_slug; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_queues_on_slug ON public.queues USING btree (slug);


--
-- Name: index_queues_on_team_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_queues_on_team_id ON public.queues USING btree (team_id);


--
-- Name: index_queues_one_default_per_brand; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_queues_one_default_per_brand ON public.queues USING btree (brand_id) WHERE "default";


--
-- Name: index_rule_sets_on_brand_id_and_version; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_rule_sets_on_brand_id_and_version ON public.rule_sets USING btree (brand_id, version);


--
-- Name: index_rule_sets_one_published_per_brand; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_rule_sets_one_published_per_brand ON public.rule_sets USING btree (brand_id) WHERE (status = 'published'::text);


--
-- Name: index_team_memberships_on_team_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_team_memberships_on_team_id ON public.team_memberships USING btree (team_id);


--
-- Name: index_teams_on_slug; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_teams_on_slug ON public.teams USING btree (slug);


--
-- Name: index_tickets_awaiting_agent; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_tickets_awaiting_agent ON public.tickets USING btree (awaiting_agent_since) WHERE ((mode = 'ai'::text) AND (awaiting_agent_since IS NOT NULL));


--
-- Name: index_tickets_on_assignee_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_tickets_on_assignee_id ON public.tickets USING btree (assignee_id);


--
-- Name: index_tickets_on_brand_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_tickets_on_brand_id ON public.tickets USING btree (brand_id);


--
-- Name: index_tickets_on_brand_id_and_customer_id_and_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_tickets_on_brand_id_and_customer_id_and_created_at ON public.tickets USING btree (brand_id, customer_id, created_at);


--
-- Name: index_tickets_on_incident_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_tickets_on_incident_id ON public.tickets USING btree (incident_id);


--
-- Name: index_tickets_one_open_per_customer_channel; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_tickets_one_open_per_customer_channel ON public.tickets USING btree (brand_id, customer_id, channel) WHERE (mode <> 'closed'::text);


--
-- Name: index_tickets_waiting_for_human; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_tickets_waiting_for_human ON public.tickets USING btree (queue_id, first_response_due_at) WHERE ((mode = 'pending_human'::text) AND (assignee_id IS NULL));


--
-- Name: index_users_on_token_digest; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_users_on_token_digest ON public.users USING btree (token_digest);


--
-- Name: tickets fk_rails_150d7cf276; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tickets
    ADD CONSTRAINT fk_rails_150d7cf276 FOREIGN KEY (incident_id) REFERENCES public.incidents(id);


--
-- Name: messages fk_rails_19770f78ed; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.messages
    ADD CONSTRAINT fk_rails_19770f78ed FOREIGN KEY (brand_id) REFERENCES public.brands(id);


--
-- Name: decisions fk_rails_199a20e433; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.decisions
    ADD CONSTRAINT fk_rails_199a20e433 FOREIGN KEY (brand_id) REFERENCES public.brands(id);


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
-- Name: closing_summaries fk_rails_2139c1703b; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.closing_summaries
    ADD CONSTRAINT fk_rails_2139c1703b FOREIGN KEY (brand_id) REFERENCES public.brands(id);


--
-- Name: queues fk_rails_2167254322; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.queues
    ADD CONSTRAINT fk_rails_2167254322 FOREIGN KEY (brand_id) REFERENCES public.brands(id);


--
-- Name: conversation_events fk_rails_2bc24c46db; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.conversation_events
    ADD CONSTRAINT fk_rails_2bc24c46db FOREIGN KEY (brand_id) REFERENCES public.brands(id);


--
-- Name: memory_erasures fk_rails_2edf12199a; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.memory_erasures
    ADD CONSTRAINT fk_rails_2edf12199a FOREIGN KEY (customer_id) REFERENCES public.customers(id);


--
-- Name: memory_erasures fk_rails_30de9e80ae; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.memory_erasures
    ADD CONSTRAINT fk_rails_30de9e80ae FOREIGN KEY (requested_by_id) REFERENCES public.users(id);


--
-- Name: rule_sets fk_rails_3c89188f6a; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.rule_sets
    ADD CONSTRAINT fk_rails_3c89188f6a FOREIGN KEY (created_by_id) REFERENCES public.users(id);


--
-- Name: closing_summaries fk_rails_51ed5450fc; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.closing_summaries
    ADD CONSTRAINT fk_rails_51ed5450fc FOREIGN KEY (customer_id) REFERENCES public.customers(id);


--
-- Name: tickets fk_rails_5685ed71b0; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tickets
    ADD CONSTRAINT fk_rails_5685ed71b0 FOREIGN KEY (customer_id) REFERENCES public.customers(id);


--
-- Name: team_memberships fk_rails_5aba9331a7; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.team_memberships
    ADD CONSTRAINT fk_rails_5aba9331a7 FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: tickets fk_rails_5ce8e37f94; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tickets
    ADD CONSTRAINT fk_rails_5ce8e37f94 FOREIGN KEY (queue_id) REFERENCES public.queues(id);


--
-- Name: team_memberships fk_rails_61c29b529e; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.team_memberships
    ADD CONSTRAINT fk_rails_61c29b529e FOREIGN KEY (team_id) REFERENCES public.teams(id);


--
-- Name: closing_summaries fk_rails_70f93debce; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.closing_summaries
    ADD CONSTRAINT fk_rails_70f93debce FOREIGN KEY (ticket_id) REFERENCES public.tickets(id);


--
-- Name: decisions fk_rails_7ab6cf5919; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.decisions
    ADD CONSTRAINT fk_rails_7ab6cf5919 FOREIGN KEY (rule_set_id) REFERENCES public.rule_sets(id);


--
-- Name: decisions fk_rails_7e7558896d; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.decisions
    ADD CONSTRAINT fk_rails_7e7558896d FOREIGN KEY (ticket_id) REFERENCES public.tickets(id);


--
-- Name: tickets fk_rails_8934a030fe; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tickets
    ADD CONSTRAINT fk_rails_8934a030fe FOREIGN KEY (priority) REFERENCES public.priority_levels(code);


--
-- Name: rule_sets fk_rails_90487e8110; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.rule_sets
    ADD CONSTRAINT fk_rails_90487e8110 FOREIGN KEY (brand_id) REFERENCES public.brands(id);


--
-- Name: conversation_events fk_rails_9edaa1a04d; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.conversation_events
    ADD CONSTRAINT fk_rails_9edaa1a04d FOREIGN KEY (ticket_id) REFERENCES public.tickets(id);


--
-- Name: incidents fk_rails_ab23b80369; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.incidents
    ADD CONSTRAINT fk_rails_ab23b80369 FOREIGN KEY (resolved_by_id) REFERENCES public.users(id);


--
-- Name: memory_erasures fk_rails_bce15b3a44; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.memory_erasures
    ADD CONSTRAINT fk_rails_bce15b3a44 FOREIGN KEY (brand_id) REFERENCES public.brands(id);


--
-- Name: incidents fk_rails_c2f821d3c1; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.incidents
    ADD CONSTRAINT fk_rails_c2f821d3c1 FOREIGN KEY (brand_id) REFERENCES public.brands(id);


--
-- Name: messages fk_rails_c631bfbc65; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.messages
    ADD CONSTRAINT fk_rails_c631bfbc65 FOREIGN KEY (inbound_event_id) REFERENCES public.inbound_events(id);


--
-- Name: queues fk_rails_d2652f34b4; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.queues
    ADD CONSTRAINT fk_rails_d2652f34b4 FOREIGN KEY (team_id) REFERENCES public.teams(id);


--
-- Name: customers fk_rails_df42b7b625; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.customers
    ADD CONSTRAINT fk_rails_df42b7b625 FOREIGN KEY (brand_id) REFERENCES public.brands(id);


--
-- Name: tickets fk_rails_ea25a37fb1; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tickets
    ADD CONSTRAINT fk_rails_ea25a37fb1 FOREIGN KEY (assignee_id) REFERENCES public.users(id);


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
('20261122000010'),
('20261122000009'),
('20261118000008'),
('20261116000007'),
('20261116000006'),
('20261115000005'),
('20261115000004'),
('20261115000003'),
('20261115000002'),
('20261115000001');

