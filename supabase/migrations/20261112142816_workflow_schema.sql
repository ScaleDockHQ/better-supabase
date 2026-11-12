-- The workflow schema of the Workflow SDK's Postgres world. A schema diff does not see
-- it, and the triggers the schema files declare on it need its tables.

CREATE SCHEMA IF NOT EXISTS "workflow";

ALTER SCHEMA "workflow" OWNER TO "postgres";

CREATE TYPE "workflow"."status" AS ENUM (
    'pending',
    'running',
    'completed',
    'failed',
    'cancelled'
);

ALTER TYPE "workflow"."status" OWNER TO "postgres";

CREATE TYPE "workflow"."step_status" AS ENUM (
    'pending',
    'running',
    'completed',
    'failed',
    'cancelled'
);

ALTER TYPE "workflow"."step_status" OWNER TO "postgres";

CREATE TYPE "workflow"."wait_status" AS ENUM (
    'waiting',
    'completed'
);

ALTER TYPE "workflow"."wait_status" OWNER TO "postgres";

CREATE TABLE IF NOT EXISTS "workflow"."workflow_event_slots" (
    "run_id" character varying NOT NULL,
    "seq_in_band" integer DEFAULT 1 NOT NULL
);

ALTER TABLE "workflow"."workflow_event_slots" OWNER TO "postgres";

CREATE TABLE IF NOT EXISTS "workflow"."workflow_events" (
    "id" character varying NOT NULL,
    "type" character varying NOT NULL,
    "correlation_id" character varying,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "run_id" character varying NOT NULL,
    "payload" "jsonb",
    "payload_cbor" "bytea",
    "spec_version" integer,
    "resume_id" character varying,
    "resume_payload_digest" character varying
);

ALTER TABLE "workflow"."workflow_events" OWNER TO "postgres";

CREATE TABLE IF NOT EXISTS "workflow"."workflow_hooks" (
    "run_id" character varying NOT NULL,
    "hook_id" character varying NOT NULL,
    "token" character varying NOT NULL,
    "owner_id" character varying NOT NULL,
    "project_id" character varying NOT NULL,
    "environment" character varying NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "metadata" "jsonb",
    "metadata_cbor" "bytea",
    "spec_version" integer,
    "is_webhook" boolean DEFAULT true,
    "is_system" boolean DEFAULT false,
    "resume_context" "bytea",
    "token_retention_until" timestamp with time zone,
    "claimed_from" "bytea",
    "claims_token" boolean DEFAULT false NOT NULL
);

ALTER TABLE "workflow"."workflow_hooks" OWNER TO "postgres";

CREATE TABLE IF NOT EXISTS "workflow"."workflow_invocations" (
    "sequence" bigint NOT NULL,
    "run_id" character varying NOT NULL,
    "request_id" character varying NOT NULL,
    "payload" "bytea",
    "fingerprint" character varying,
    "result" "bytea",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "responded_at" timestamp with time zone,
    "expired_at" timestamp with time zone,
    "result_version" integer DEFAULT 0 NOT NULL
);

ALTER TABLE "workflow"."workflow_invocations" OWNER TO "postgres";

CREATE SEQUENCE IF NOT EXISTS "workflow"."workflow_invocations_sequence_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

ALTER SEQUENCE "workflow"."workflow_invocations_sequence_seq" OWNER TO "postgres";

ALTER SEQUENCE "workflow"."workflow_invocations_sequence_seq" OWNED BY "workflow"."workflow_invocations"."sequence";

CREATE TABLE IF NOT EXISTS "workflow"."workflow_run_keys" (
    "key" "text" NOT NULL,
    "run_id" character varying,
    "claimed_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "bsb_workflow_run_keys_key_check" CHECK ((("length"("key") >= 1) AND ("length"("key") <= 500)))
);

ALTER TABLE "workflow"."workflow_run_keys" OWNER TO "postgres";

CREATE TABLE IF NOT EXISTS "workflow"."workflow_runs" (
    "id" character varying NOT NULL,
    "output" "jsonb",
    "deployment_id" character varying NOT NULL,
    "name" character varying NOT NULL,
    "execution_context" "jsonb",
    "input" "jsonb",
    "error" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "completed_at" timestamp with time zone,
    "started_at" timestamp with time zone,
    "output_cbor" "bytea",
    "execution_context_cbor" "bytea",
    "input_cbor" "bytea",
    "expired_at" timestamp with time zone,
    "spec_version" character varying,
    "error_cbor" "bytea",
    "error_code" character varying,
    "attributes" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "encryption_public_key" character varying,
    "dynamic_workflow_code_cbor" "bytea",
    "status" "workflow"."status" NOT NULL,
    "start_hook_cbor" "bytea",
    "job_prefix" character varying
);

ALTER TABLE "workflow"."workflow_runs" OWNER TO "postgres";

CREATE TABLE IF NOT EXISTS "workflow"."workflow_snapshots" (
    "run_id" character varying NOT NULL,
    "data" "bytea" NOT NULL,
    "events_cursor" character varying,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);

ALTER TABLE "workflow"."workflow_snapshots" OWNER TO "postgres";

CREATE TABLE IF NOT EXISTS "workflow"."workflow_start_hook_admissions" (
    "run_id" character varying NOT NULL,
    "token" character varying NOT NULL,
    "decision" character varying NOT NULL,
    "conflicting_run_id" character varying,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);

ALTER TABLE "workflow"."workflow_start_hook_admissions" OWNER TO "postgres";

CREATE TABLE IF NOT EXISTS "workflow"."workflow_steps" (
    "run_id" character varying NOT NULL,
    "step_id" character varying NOT NULL,
    "step_name" character varying NOT NULL,
    "input" "jsonb",
    "output" "jsonb",
    "error" "text",
    "attempt" integer NOT NULL,
    "started_at" timestamp with time zone,
    "completed_at" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "retry_after" timestamp with time zone,
    "input_cbor" "bytea",
    "output_cbor" "bytea",
    "error_cbor" "bytea",
    "spec_version" integer,
    "status" "workflow"."step_status" NOT NULL
);

ALTER TABLE "workflow"."workflow_steps" OWNER TO "postgres";

CREATE TABLE IF NOT EXISTS "workflow"."workflow_stream_chunks" (
    "id" character varying NOT NULL,
    "stream_id" character varying NOT NULL,
    "data" "bytea" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "eof" boolean NOT NULL,
    "run_id" character varying
);

ALTER TABLE "workflow"."workflow_stream_chunks" OWNER TO "postgres";

CREATE TABLE IF NOT EXISTS "workflow"."workflow_waits" (
    "wait_id" character varying NOT NULL,
    "run_id" character varying NOT NULL,
    "resume_at" timestamp with time zone,
    "completed_at" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "spec_version" integer,
    "status" "workflow"."wait_status" NOT NULL
);

ALTER TABLE "workflow"."workflow_waits" OWNER TO "postgres";

ALTER TABLE ONLY "workflow"."workflow_invocations" ALTER COLUMN "sequence" SET DEFAULT "nextval"('"workflow"."workflow_invocations_sequence_seq"'::"regclass");

ALTER TABLE ONLY "workflow"."workflow_event_slots"
    ADD CONSTRAINT "workflow_event_slots_pkey" PRIMARY KEY ("run_id");

ALTER TABLE ONLY "workflow"."workflow_events"
    ADD CONSTRAINT "workflow_events_run_id_id_pk" PRIMARY KEY ("run_id", "id");

ALTER TABLE ONLY "workflow"."workflow_hooks"
    ADD CONSTRAINT "workflow_hooks_pkey" PRIMARY KEY ("hook_id");

ALTER TABLE ONLY "workflow"."workflow_invocations"
    ADD CONSTRAINT "workflow_invocations_pkey" PRIMARY KEY ("run_id", "request_id");

ALTER TABLE ONLY "workflow"."workflow_run_keys"
    ADD CONSTRAINT "workflow_run_keys_pkey" PRIMARY KEY ("key");

ALTER TABLE ONLY "workflow"."workflow_runs"
    ADD CONSTRAINT "workflow_runs_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "workflow"."workflow_snapshots"
    ADD CONSTRAINT "workflow_snapshots_pkey" PRIMARY KEY ("run_id");

ALTER TABLE ONLY "workflow"."workflow_start_hook_admissions"
    ADD CONSTRAINT "workflow_start_hook_admissions_pkey" PRIMARY KEY ("run_id");

ALTER TABLE ONLY "workflow"."workflow_steps"
    ADD CONSTRAINT "workflow_steps_pkey" PRIMARY KEY ("step_id");

ALTER TABLE ONLY "workflow"."workflow_stream_chunks"
    ADD CONSTRAINT "workflow_stream_chunks_stream_id_id_pk" PRIMARY KEY ("stream_id", "id");

ALTER TABLE ONLY "workflow"."workflow_waits"
    ADD CONSTRAINT "workflow_waits_pkey" PRIMARY KEY ("wait_id");

CREATE INDEX "workflow_events_correlation_id_index" ON "workflow"."workflow_events" USING "btree" ("correlation_id");

CREATE UNIQUE INDEX "workflow_events_entity_creation_unique" ON "workflow"."workflow_events" USING "btree" ("run_id", "correlation_id", "type") WHERE (("type")::"text" = ANY (ARRAY[('step_created'::character varying)::"text", ('hook_created'::character varying)::"text", ('wait_created'::character varying)::"text", ('attr_set'::character varying)::"text"]));

CREATE UNIQUE INDEX "workflow_events_hook_resume_unique" ON "workflow"."workflow_events" USING "btree" ("run_id", "resume_id") WHERE ((("type")::"text" = 'hook_received'::"text") AND ("resume_id" IS NOT NULL));

CREATE INDEX "workflow_hooks_run_id_index" ON "workflow"."workflow_hooks" USING "btree" ("run_id");

CREATE UNIQUE INDEX "workflow_hooks_token_claim_unique" ON "workflow"."workflow_hooks" USING "btree" ("token") WHERE "claims_token";

CREATE INDEX "workflow_hooks_token_index" ON "workflow"."workflow_hooks" USING "btree" ("token");

CREATE INDEX "workflow_invocations_pending" ON "workflow"."workflow_invocations" USING "btree" ("run_id", "sequence") WHERE ("responded_at" IS NULL);

CREATE INDEX "workflow_run_keys_run_id_idx" ON "workflow"."workflow_run_keys" USING "btree" ("run_id");

CREATE INDEX "workflow_runs_attributes_idx" ON "workflow"."workflow_runs" USING "gin" ("attributes" "jsonb_path_ops");

CREATE INDEX "workflow_runs_name_index" ON "workflow"."workflow_runs" USING "btree" ("name");

CREATE INDEX "workflow_runs_status_index" ON "workflow"."workflow_runs" USING "btree" ("status");

CREATE INDEX "workflow_start_hook_admissions_created_at_index" ON "workflow"."workflow_start_hook_admissions" USING "btree" ("created_at");

CREATE INDEX "workflow_steps_run_id_index" ON "workflow"."workflow_steps" USING "btree" ("run_id");

CREATE INDEX "workflow_steps_status_index" ON "workflow"."workflow_steps" USING "btree" ("status");

CREATE INDEX "workflow_stream_chunks_run_id_index" ON "workflow"."workflow_stream_chunks" USING "btree" ("run_id");

CREATE INDEX "workflow_waits_run_id_index" ON "workflow"."workflow_waits" USING "btree" ("run_id");

ALTER TABLE "workflow"."workflow_event_slots" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "workflow"."workflow_events" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "workflow"."workflow_hooks" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "workflow"."workflow_invocations" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "workflow"."workflow_run_keys" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "workflow"."workflow_runs" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "workflow"."workflow_snapshots" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "workflow"."workflow_start_hook_admissions" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "workflow"."workflow_steps" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "workflow"."workflow_stream_chunks" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "workflow"."workflow_waits" ENABLE ROW LEVEL SECURITY;

GRANT USAGE ON SCHEMA "workflow" TO "service_role";

GRANT ALL ON TABLE "workflow"."workflow_event_slots" TO "service_role";

GRANT ALL ON TABLE "workflow"."workflow_events" TO "service_role";

GRANT ALL ON TABLE "workflow"."workflow_hooks" TO "service_role";

GRANT ALL ON TABLE "workflow"."workflow_invocations" TO "service_role";

GRANT SELECT,USAGE ON SEQUENCE "workflow"."workflow_invocations_sequence_seq" TO "service_role";

GRANT ALL ON TABLE "workflow"."workflow_run_keys" TO "service_role";

GRANT ALL ON TABLE "workflow"."workflow_runs" TO "service_role";

GRANT ALL ON TABLE "workflow"."workflow_snapshots" TO "service_role";

GRANT ALL ON TABLE "workflow"."workflow_start_hook_admissions" TO "service_role";

GRANT ALL ON TABLE "workflow"."workflow_steps" TO "service_role";

GRANT ALL ON TABLE "workflow"."workflow_stream_chunks" TO "service_role";

GRANT ALL ON TABLE "workflow"."workflow_waits" TO "service_role";

CREATE TRIGGER bsb_workflow_sdk_runs_mirror
  AFTER INSERT OR UPDATE OF status, attributes, error ON workflow.workflow_runs
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.workflow_sdk_mirror_run();
