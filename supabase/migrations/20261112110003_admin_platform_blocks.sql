SET local check_function_bodies = off;

DROP VIEW "better_supabase"."maintenance_jobs";

CREATE TABLE "better_supabase"."hostnames" (
  "id"                 uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "tenant_id"          uuid                     NOT NULL,
  "hostname"           text                     NOT NULL,
  "kind"               text                     NOT NULL DEFAULT 'custom'::text,
  "verification_token" text                     NOT NULL DEFAULT replace((gen_random_uuid())::text, '-'::text, ''::text),
  "verified_at"        timestamp with time zone,
  "is_primary"         boolean                  NOT NULL DEFAULT false,
  "created_at"         timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "bsb_hostnames_check" CHECK (((NOT is_primary) OR (verified_at IS NOT NULL))),
  CONSTRAINT "bsb_hostnames_hostname_check" CHECK (((length(hostname) <= 253) AND (hostname ~ '^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?[.])+[a-z]{2,63}$'::text))),
  CONSTRAINT "bsb_hostnames_kind_check" CHECK ((kind = ANY (ARRAY['custom'::text, 'subdomain'::text]))),
  CONSTRAINT "hostnames_pkey" PRIMARY KEY (id),
  CONSTRAINT "hostnames_tenant_id_hostname_key" UNIQUE (tenant_id, hostname),
  "created_by"         uuid                     DEFAULT auth.uid()
);

ALTER TABLE "better_supabase"."hostnames"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."idempotency_keys" (
  "scope"           text                     NOT NULL DEFAULT ''::text,
  "key"             text                     NOT NULL,
  "request_hash"    text                     NOT NULL,
  "status"          text                     NOT NULL DEFAULT 'running'::text,
  "status_code"     integer,
  "response"        jsonb,
  "lock_expires_at" timestamp with time zone,
  "created_at"      timestamp with time zone NOT NULL DEFAULT now(),
  "expires_at"      timestamp with time zone NOT NULL,
  "holder"          uuid,
  CONSTRAINT "bsb_idempotency_keys_status_check" CHECK ((status = ANY (ARRAY['running'::text, 'completed'::text]))),
  CONSTRAINT "idempotency_keys_pkey" PRIMARY KEY (scope, key)
);

ALTER TABLE "better_supabase"."idempotency_keys"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."idempotency_leases" (
  "scope"      text                     NOT NULL DEFAULT ''::text,
  "key"        text                     NOT NULL,
  "holder"     uuid                     NOT NULL,
  "expires_at" timestamp with time zone NOT NULL,
  CONSTRAINT "idempotency_leases_pkey" PRIMARY KEY (scope, key)
);

ALTER TABLE "better_supabase"."idempotency_leases"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."incoming_webhooks" (
  "id"                         uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "tenant"                     uuid                     NOT NULL,
  "name"                       text                     NOT NULL,
  "token_hash"                 text                     NOT NULL,
  "verify"                     text                     NOT NULL DEFAULT 'none'::text,
  "secret"                     text,
  "secret_id"                  uuid,
  "previous_secret"            text,
  "previous_secret_id"         uuid,
  "previous_secret_expires_at" timestamp with time zone,
  "signature_header"           text,
  "enabled"                    boolean                  NOT NULL DEFAULT true,
  "max_body_bytes"             integer                  NOT NULL DEFAULT 1048576,
  "receive_count"              bigint                   NOT NULL DEFAULT 0,
  "last_received_at"           timestamp with time zone,
  "last_status"                integer,
  "metadata"                   jsonb                    NOT NULL DEFAULT '{}'::jsonb,
  "subject_type"               text,
  "subject_id"                 text,
  "created_by"                 uuid,
  "created_at"                 timestamp with time zone NOT NULL DEFAULT now(),
  "updated_at"                 timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "bsb_incoming_webhooks_max_body_bytes_check" CHECK ((max_body_bytes > 0)),
  CONSTRAINT "bsb_incoming_webhooks_subject_id_check" CHECK (((length(subject_id) >= 1) AND (length(subject_id) <= 200))),
  CONSTRAINT "bsb_incoming_webhooks_subject_type_check" CHECK ((subject_type ~ '^[a-z][a-z0-9_-]{0,62}$'::text)),
  CONSTRAINT "bsb_incoming_webhooks_verify_check" CHECK ((verify = ANY (ARRAY['none'::text, 'standard-webhooks'::text, 'hmac-sha256'::text, 'shared-secret'::text]))),
  CONSTRAINT "incoming_webhooks_pkey" PRIMARY KEY (id),
  CONSTRAINT "incoming_webhooks_token_hash_key" UNIQUE (token_hash)
);

ALTER TABLE "better_supabase"."incoming_webhooks"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."option_set_items" (
  "id"            uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "tenant_id"     uuid                     NOT NULL,
  "option_set_id" uuid                     NOT NULL,
  "key"           text                     NOT NULL,
  "system_key"    text,
  "label"         text                     NOT NULL,
  "color"         text,
  "icon"          text,
  "rank"          text                     COLLATE pg_catalog."C" NOT NULL DEFAULT 'V'::text,
  "level"         integer                  NOT NULL,
  "description"   text,
  "archived_at"   timestamp with time zone,
  "created_at"    timestamp with time zone NOT NULL DEFAULT now(),
  "updated_at"    timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "bsb_option_set_items_color_check" CHECK (((color IS NULL) OR (length(color) <= 50))),
  CONSTRAINT "bsb_option_set_items_description_check" CHECK (((description IS NULL) OR (length(description) <= 1000))),
  CONSTRAINT "bsb_option_set_items_icon_check" CHECK (((icon IS NULL) OR (length(icon) <= 100))),
  CONSTRAINT "bsb_option_set_items_key_check" CHECK ((key ~ '^[a-z][a-z0-9_-]{0,62}$'::text)),
  CONSTRAINT "bsb_option_set_items_label_check" CHECK (((length(label) >= 1) AND (length(label) <= 200))),
  CONSTRAINT "option_set_items_option_set_id_key_key" UNIQUE (option_set_id, key),
  CONSTRAINT "option_set_items_pkey" PRIMARY KEY (id)
);

ALTER TABLE "better_supabase"."option_set_items"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."option_sets" (
  "id"           uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "tenant_id"    uuid                     NOT NULL,
  "subject_type" text                     NOT NULL,
  "field"        text                     NOT NULL,
  "scope_id"     text,
  "key"          text                     NOT NULL,
  "name"         text                     NOT NULL,
  "is_default"   boolean                  NOT NULL DEFAULT false,
  "archived_at"  timestamp with time zone,
  "created_at"   timestamp with time zone NOT NULL DEFAULT now(),
  "updated_at"   timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "bsb_option_sets_field_check" CHECK ((field ~ '^[a-z][a-z0-9_]{0,62}$'::text)),
  CONSTRAINT "bsb_option_sets_key_check" CHECK ((key ~ '^[a-z][a-z0-9_-]{0,62}$'::text)),
  CONSTRAINT "bsb_option_sets_name_check" CHECK (((length(name) >= 1) AND (length(name) <= 200))),
  CONSTRAINT "option_sets_pkey" PRIMARY KEY (id),
  CONSTRAINT "option_sets_tenant_id_subject_type_field_scope_id_key_key" UNIQUE NULLS NOT DISTINCT (tenant_id, subject_type, field, scope_id, key)
);

ALTER TABLE "better_supabase"."option_sets"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."reserved_slugs" (
  "slug"   text NOT NULL,
  "reason" text,
  CONSTRAINT "reserved_slugs_pkey" PRIMARY KEY (slug)
);

ALTER TABLE "better_supabase"."reserved_slugs"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."ssf_events" (
  "stream_id"  uuid                     NOT NULL,
  "jti"        text                     NOT NULL,
  "token"      text                     NOT NULL,
  "created_at" timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "bsb_ssf_events_jti_check" CHECK (((length(jti) >= 1) AND (length(jti) <= 200))),
  CONSTRAINT "ssf_events_pkey" PRIMARY KEY (stream_id, jti)
);

ALTER TABLE "better_supabase"."ssf_events"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."ssf_received" (
  "issuer"      text                     NOT NULL,
  "jti"         text                     NOT NULL,
  "received_at" timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "bsb_ssf_received_jti_check" CHECK (((length(jti) >= 1) AND (length(jti) <= 200))),
  CONSTRAINT "ssf_received_pkey" PRIMARY KEY (issuer, jti)
);

ALTER TABLE "better_supabase"."ssf_received"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."ssf_streams" (
  "id"               uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "tenant"           text,
  "receiver"         text                     NOT NULL,
  "audience"         text[]                   NOT NULL,
  "description"      text,
  "events_requested" text[]                   NOT NULL DEFAULT '{}'::text[],
  "events_delivered" text[]                   NOT NULL DEFAULT '{}'::text[],
  "delivery_method"  text                     NOT NULL,
  "endpoint_id"      uuid,
  "status"           text                     NOT NULL DEFAULT 'enabled'::text,
  "reason"           text,
  "verified_at"      timestamp with time zone,
  "created_at"       timestamp with time zone NOT NULL DEFAULT now(),
  "updated_at"       timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "bsb_ssf_streams_audience_check" CHECK (((cardinality(audience) >= 1) AND (cardinality(audience) <= 20))),
  CONSTRAINT "bsb_ssf_streams_delivery_method_check" CHECK ((delivery_method = ANY (ARRAY['urn:ietf:rfc:8935'::text, 'urn:ietf:rfc:8936'::text]))),
  CONSTRAINT "bsb_ssf_streams_description_check" CHECK ((length(description) <= 1000)),
  CONSTRAINT "bsb_ssf_streams_reason_check" CHECK ((length(reason) <= 1000)),
  CONSTRAINT "bsb_ssf_streams_receiver_check" CHECK (((length(receiver) >= 1) AND (length(receiver) <= 200))),
  CONSTRAINT "bsb_ssf_streams_status_check" CHECK ((status = ANY (ARRAY['enabled'::text, 'paused'::text, 'disabled'::text]))),
  CONSTRAINT "bsb_ssf_streams_tenant_check" CHECK (((length(tenant) >= 1) AND (length(tenant) <= 200))),
  CONSTRAINT "ssf_streams_pkey" PRIMARY KEY (id)
);

ALTER TABLE "better_supabase"."ssf_streams"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."webhook_inbox" (
  "id"              bigint                   GENERATED ALWAYS AS IDENTITY NOT NULL,
  "source"          text                     NOT NULL,
  "message_id"      text                     NOT NULL,
  "event_type"      text,
  "payload"         jsonb                    NOT NULL,
  "headers"         jsonb                    NOT NULL DEFAULT '{}'::jsonb,
  "status"          text                     NOT NULL DEFAULT 'pending'::text,
  "attempts"        integer                  NOT NULL DEFAULT 0,
  "max_attempts"    integer                  NOT NULL DEFAULT 8,
  "available_at"    timestamp with time zone NOT NULL DEFAULT now(),
  "locked_by"       text,
  "lock_expires_at" timestamp with time zone,
  "last_error"      text,
  "received_at"     timestamp with time zone NOT NULL DEFAULT now(),
  "processed_at"    timestamp with time zone,
  "tenant"          text,
  "checkpoint"      jsonb                    NOT NULL DEFAULT '{}'::jsonb,
  CONSTRAINT "bsb_webhook_inbox_status_check" CHECK ((status = ANY (ARRAY['pending'::text, 'processing'::text, 'processed'::text, 'dead'::text]))),
  CONSTRAINT "webhook_inbox_pkey" PRIMARY KEY (id),
  CONSTRAINT "webhook_inbox_source_tenant_message_id_key" UNIQUE NULLS NOT DISTINCT (source, tenant, message_id)
);

ALTER TABLE "better_supabase"."webhook_inbox"
  ENABLE ROW LEVEL SECURITY;

ALTER TABLE "better_supabase"."work_items"
  ADD COLUMN "priority_option_id" uuid;

CREATE OR REPLACE FUNCTION api.acquire_lease (
  key     text,
  seconds integer DEFAULT 60,
  scope   text    DEFAULT ''::text
)
  RETURNS uuid
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."acquire_lease"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.add_hostname (
  tenant   uuid,
  hostname text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."add_hostname"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.archive_option_set_item (
  item        uuid,
  replacement uuid DEFAULT NULL::uuid
)
  RETURNS boolean
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."archive_option_set_item"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.begin_idempotent (
  scope        text,
  key          text,
  request_hash text,
  ttl          interval DEFAULT '24:00:00'::interval,
  lock         interval DEFAULT '00:01:00'::interval
)
  RETURNS TABLE (
    state       text,
    status_code integer,
    response    jsonb,
    holder      uuid
  )
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select * from "better_supabase"."begin_idempotent"($1, $2, $3, $4, $5) $function$;

CREATE OR REPLACE FUNCTION api.checkpoint_webhook (
  inbox_id bigint,
  worker   text,
  fields   jsonb,
  attempt  integer DEFAULT NULL::integer
)
  RETURNS boolean
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."checkpoint_webhook"($1, $2, $3, $4) $function$;

CREATE OR REPLACE FUNCTION api.claim_webhooks (
  source text,
  worker text,
  batch  integer  DEFAULT 10,
  lease  interval DEFAULT '00:05:00'::interval
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."claim_webhooks"($1, $2, $3, $4) $function$;

CREATE OR REPLACE FUNCTION api.complete_idempotent (
  scope       text,
  key         text,
  holder      uuid,
  status_code integer,
  response    jsonb
)
  RETURNS boolean
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."complete_idempotent"($1, $2, $3, $4, $5) $function$;

CREATE OR REPLACE FUNCTION api.complete_webhook (
  inbox_id bigint,
  worker   text,
  attempt  integer DEFAULT NULL::integer
)
  RETURNS boolean
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."complete_webhook"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.create_incoming_webhook (
  tenant           uuid,
  name             text,
  verify           text  DEFAULT 'none'::text,
  metadata         jsonb DEFAULT '{}'::jsonb,
  signature_header text  DEFAULT NULL::text,
  subject_type     text  DEFAULT NULL::text,
  subject_id       text  DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."create_incoming_webhook"($1, $2, $3, $4, $5, $6, $7) $function$;

CREATE OR REPLACE FUNCTION api.create_ssf_stream (
  id               uuid,
  receiver         text,
  tenant           text,
  audience         text[],
  delivery_method  text,
  events_requested text[],
  events_delivered text[],
  description      text   DEFAULT NULL::text,
  endpoint_url     text   DEFAULT NULL::text,
  credential_ref   jsonb  DEFAULT NULL::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."create_ssf_stream"($1, $2, $3, $4, $5, $6, $7, $8, $9, $10) $function$;

CREATE OR REPLACE FUNCTION api.default_option_set (
  tenant       uuid,
  subject_type text,
  field        text,
  scope_id     text
)
  RETURNS uuid
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."default_option_set"($1, $2, $3, $4) $function$;

CREATE OR REPLACE FUNCTION api.delete_incoming_webhook (
  endpoint uuid
)
  RETURNS boolean
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."delete_incoming_webhook"($1) $function$;

CREATE OR REPLACE FUNCTION api.delete_ssf_stream (
  id uuid
)
  RETURNS boolean
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."delete_ssf_stream"($1) $function$;

CREATE OR REPLACE FUNCTION api.ensure_option_set (
  tenant       uuid,
  subject_type text,
  field        text,
  scope_id     text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."ensure_option_set"($1, $2, $3, $4) $function$;

CREATE OR REPLACE FUNCTION api.extend_idempotent (
  scope  text,
  key    text,
  holder uuid,
  lock   interval DEFAULT '00:01:00'::interval
)
  RETURNS boolean
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."extend_idempotent"($1, $2, $3, $4) $function$;

CREATE OR REPLACE FUNCTION api.extend_lease (
  key     text,
  holder  uuid,
  seconds integer DEFAULT 60,
  scope   text    DEFAULT ''::text
)
  RETURNS boolean
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."extend_lease"($1, $2, $3, $4) $function$;

CREATE OR REPLACE FUNCTION api.extend_webhook (
  inbox_id bigint,
  worker   text,
  attempt  integer,
  lease    interval DEFAULT '00:05:00'::interval
)
  RETURNS double precision
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."extend_webhook"($1, $2, $3, $4) $function$;

CREATE OR REPLACE FUNCTION api.fail_webhook (
  inbox_id  bigint,
  worker    text,
  error     text,
  retry_in  interval DEFAULT NULL::interval,
  attempt   integer  DEFAULT NULL::integer,
  permanent boolean  DEFAULT false
)
  RETURNS text
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."fail_webhook"($1, $2, $3, $4, $5, $6) $function$;

CREATE OR REPLACE FUNCTION api.forget_ssf_received (
  issuer text,
  jti    text
)
  RETURNS boolean
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."forget_ssf_received"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.hostname_by_id (
  id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."hostname_by_id"($1) $function$;

CREATE OR REPLACE FUNCTION api.incoming_webhook_by_token (
  token text
)
  RETURNS TABLE (
    id               uuid,
    tenant           text,
    enabled          boolean,
    verify           text,
    secret           text,
    signature_header text,
    max_body_bytes   integer,
    previous_secret  text,
    metadata         jsonb
  )
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select * from "better_supabase"."incoming_webhook_by_token"($1) $function$;

CREATE OR REPLACE FUNCTION api.list_hostnames (
  tenant uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_hostnames"($1) $function$;

CREATE OR REPLACE FUNCTION api.list_incoming_webhooks (
  tenant       uuid,
  subject_type text DEFAULT NULL::text,
  subject_id   text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_incoming_webhooks"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.list_option_sets (
  tenant  uuid,
  filters jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_option_sets"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.list_webhooks (
  for_tenant text,
  for_source text    DEFAULT NULL::text,
  for_status text    DEFAULT NULL::text,
  max_rows   integer DEFAULT 100
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_webhooks"($1, $2, $3, $4) $function$;

CREATE OR REPLACE FUNCTION api.maintenance (
  job_name  text    DEFAULT NULL::text,
  force_run boolean DEFAULT false
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."maintenance"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.maintenance_schedule (
  cron_schedule text DEFAULT '*/5 * * * *'::text
)
  RETURNS text
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."maintenance_schedule"($1) $function$;

CREATE OR REPLACE FUNCTION api.maintenance_scheduler()
  RETURNS text
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."maintenance_scheduler"() $function$;

CREATE OR REPLACE FUNCTION api.note_ssf_verification (
  stream_id    uuid,
  min_interval interval
)
  RETURNS boolean
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."note_ssf_verification"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.poll_ssf_events (
  stream_id  uuid,
  max_events integer,
  ack        text[]  DEFAULT '{}'::text[],
  errors     jsonb   DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."poll_ssf_events"($1, $2, $3, $4) $function$;

CREATE OR REPLACE FUNCTION api.purge_idempotency_keys()
  RETURNS integer
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."purge_idempotency_keys"() $function$;

CREATE OR REPLACE FUNCTION api.purge_shared_signals (
  older_than interval DEFAULT NULL::interval
)
  RETURNS integer
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."purge_shared_signals"($1) $function$;

CREATE OR REPLACE FUNCTION api.purge_webhooks (
  older_than   interval DEFAULT '30 days'::interval,
  include_dead boolean  DEFAULT false,
  batch        integer  DEFAULT 10000,
  for_tenant   text     DEFAULT NULL::text
)
  RETURNS integer
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."purge_webhooks"($1, $2, $3, $4) $function$;

CREATE OR REPLACE FUNCTION api.queue_ssf_set (
  stream_id uuid,
  jti       text,
  token     text
)
  RETURNS text
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."queue_ssf_set"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.rank_option_set_item (
  item uuid,
  rank text
)
  RETURNS boolean
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."rank_option_set_item"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.receive_webhook (
  source       text,
  message_id   text,
  event_type   text,
  payload      jsonb,
  headers      jsonb   DEFAULT '{}'::jsonb,
  tenant       text    DEFAULT NULL::text,
  max_attempts integer DEFAULT NULL::integer
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."receive_webhook"($1, $2, $3, $4, $5, $6, $7) $function$;

CREATE OR REPLACE FUNCTION api.record_incoming_webhook (
  endpoint uuid,
  status   integer
)
  RETURNS void
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."record_incoming_webhook"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.record_ssf_received (
  issuer text,
  jti    text
)
  RETURNS boolean
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."record_ssf_received"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.release_idempotent (
  scope  text,
  key    text,
  holder uuid
)
  RETURNS boolean
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."release_idempotent"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.release_lease (
  key    text,
  holder uuid,
  scope  text DEFAULT ''::text
)
  RETURNS boolean
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."release_lease"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.remove_hostname (
  id uuid
)
  RETURNS boolean
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."remove_hostname"($1) $function$;

CREATE OR REPLACE FUNCTION api.resolve_hostname (
  hostname text
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."resolve_hostname"($1) $function$;

CREATE OR REPLACE FUNCTION api.rotate_incoming_webhook (
  endpoint      uuid,
  rotate_secret boolean DEFAULT false
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."rotate_incoming_webhook"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.rotate_incoming_webhook_secret (
  endpoint uuid,
  grace    interval DEFAULT NULL::interval
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."rotate_incoming_webhook_secret"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.save_option_set (
  tenant       uuid,
  option_set   uuid,
  subject_type text,
  field        text,
  key          text,
  name         text,
  scope_id     text    DEFAULT NULL::text,
  is_default   boolean DEFAULT false
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."save_option_set"($1, $2, $3, $4, $5, $6, $7, $8) $function$;

CREATE OR REPLACE FUNCTION api.save_option_set_item (
  option_set  uuid,
  item        uuid,
  key         text,
  label       text,
  level       integer,
  color       text    DEFAULT NULL::text,
  icon        text    DEFAULT NULL::text,
  description text    DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."save_option_set_item"($1, $2, $3, $4, $5, $6, $7, $8) $function$;

CREATE OR REPLACE FUNCTION api.set_incoming_webhook_enabled (
  endpoint uuid,
  enabled  boolean
)
  RETURNS boolean
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."set_incoming_webhook_enabled"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.set_primary_hostname (
  id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."set_primary_hostname"($1) $function$;

CREATE OR REPLACE FUNCTION api.set_ssf_stream_status (
  id     uuid,
  status text,
  reason text DEFAULT NULL::text
)
  RETURNS text
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."set_ssf_stream_status"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.slug_problem (
  slug text
)
  RETURNS text
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."slug_problem"($1) $function$;

CREATE OR REPLACE FUNCTION api.ssf_stream (
  id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."ssf_stream"($1) $function$;

CREATE OR REPLACE FUNCTION api.ssf_streams (
  receiver text
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."ssf_streams"($1) $function$;

CREATE OR REPLACE FUNCTION api.ssf_streams_for_event (
  tenant     text,
  event_type text
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."ssf_streams_for_event"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.update_incoming_webhook (
  endpoint         uuid,
  name             text  DEFAULT NULL::text,
  metadata         jsonb DEFAULT NULL::jsonb,
  verify           text  DEFAULT NULL::text,
  signature_header text  DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."update_incoming_webhook"($1, $2, $3, $4, $5) $function$;

CREATE OR REPLACE FUNCTION api.update_ssf_stream (
  id    uuid,
  patch jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."update_ssf_stream"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.verify_hostname (
  id    uuid,
  actor uuid DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."verify_hostname"($1, $2) $function$;

CREATE OR REPLACE FUNCTION better_supabase.acquire_lease (
  key     text,
  seconds integer DEFAULT 60,
  scope   text    DEFAULT ''::text
)
  RETURNS uuid
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  token uuid := gen_random_uuid();
  taken uuid;
begin
  insert into "better_supabase"."idempotency_leases" as l ("scope", "key", "holder", "expires_at")
  values (scope, key, token, now() + make_interval(secs => greatest(seconds, 1)))
  on conflict ("scope", "key") do update
    set "holder" = excluded."holder", "expires_at" = excluded."expires_at"
    where l."expires_at" <= now()
  returning l."holder" into taken;
  return taken;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.add_hostname (
  tenant   uuid,
  hostname text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_row "better_supabase"."hostnames";
  v_hostname text := lower(trim(trailing '.' from trim(add_hostname.hostname)));
  v_kind text := 'custom';
  v_label text;
  v_new boolean;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', add_hostname.tenant, 'domains.manage'), false)) then
    raise exception 'You may not manage this organization''s hostnames' using errcode = '42501', hint = 'HOSTNAME_FORBIDDEN';
  end if;
  if v_hostname is null or length(v_hostname) > 253 or v_hostname !~ '^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?[.])+[a-z]{2,63}$' then
    raise exception 'Not a hostname: %', add_hostname.hostname using errcode = '22023', hint = 'HOSTNAME_INVALID';
  end if;
  select * into v_row from "better_supabase"."hostnames" x where x."tenant_id" = add_hostname.tenant and x."hostname" = v_hostname;
  if v_row."id" is not null then
    return (to_jsonb(v_row) - 'verification_token') || case when v_row."verified_at" is null then jsonb_build_object('record', jsonb_build_object('type', 'TXT', 'name', '_better-supabase.' || v_row."hostname", 'value', 'better-supabase-hostname-verification=' || v_row."verification_token")) else '{}'::jsonb end;
  end if;
  if v_kind = 'subdomain' and exists (select 1 from "better_supabase"."hostnames" x where x."hostname" = v_hostname and x."verified_at" is not null) then
    raise exception 'Another organization holds %', v_hostname using errcode = '23505', hint = 'HOSTNAME_TAKEN';
  end if;
  insert into "better_supabase"."hostnames" ("tenant_id", "hostname", "kind", "verified_at")
  values (add_hostname.tenant, v_hostname, v_kind, case when v_kind = 'subdomain' then now() end)
  returning * into v_row;
  perform "better_supabase".emit_event('hostname.added', jsonb_build_object('organizationId', v_row."tenant_id"::text, 'hostnameId', v_row."id"::text, 'hostname', v_row."hostname"), 'hostnames/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/domains');
  perform better_supabase.audit_event(
    event_type => 'hostname.added',
    category => 'configuration',
    target_type => 'hostname',
    record_id => v_row."id"::text,
    target_label => v_row."hostname",
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id"::text, 'hostnameId', v_row."id"::text, 'hostname', v_row."hostname"),
    actor_id => auth.uid()
  );
  if v_row."verified_at" is not null then
    perform "better_supabase".emit_event('hostname.verified', jsonb_build_object('organizationId', v_row."tenant_id"::text, 'hostnameId', v_row."id"::text, 'hostname', v_row."hostname"), 'hostnames/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/domains');
  perform better_supabase.audit_event(
    event_type => 'hostname.verified',
    category => 'configuration',
    target_type => 'hostname',
    record_id => v_row."id"::text,
    target_label => v_row."hostname",
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id"::text, 'hostnameId', v_row."id"::text, 'hostname', v_row."hostname"),
    actor_id => auth.uid()
  );
  end if;
  return (to_jsonb(v_row) - 'verification_token') || case when v_row."verified_at" is null then jsonb_build_object('record', jsonb_build_object('type', 'TXT', 'name', '_better-supabase.' || v_row."hostname", 'value', 'better-supabase-hostname-verification=' || v_row."verification_token")) else '{}'::jsonb end;
exception when unique_violation then
  raise exception 'Another organization holds %', v_hostname using errcode = '23505', hint = 'HOSTNAME_TAKEN';
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.archive_option_set_item (
  item        uuid,
  replacement uuid DEFAULT NULL::uuid
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_tenant uuid;
  v_set uuid;
  v_type text;
  v_field text;
  v_used boolean;
  v_item uuid := archive_option_set_item.item;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id", x."option_set_id", y."subject_type", y."field" into v_tenant, v_set, v_type, v_field
  from "better_supabase"."option_set_items" x join "better_supabase"."option_sets" y on y."id" = x."option_set_id"
  where x."id" = archive_option_set_item.item and x."archived_at" is null;
  if v_tenant is null then
    return false;
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'option_sets.manage'), false)) then
    raise exception 'not allowed to manage option sets' using errcode = '42501', hint = 'OPTION_SET_FORBIDDEN';
  end if;
  if archive_option_set_item.replacement is not null and not exists (
    select 1 from "better_supabase"."option_set_items" x
    where x."id" = archive_option_set_item.replacement and x."option_set_id" = v_set
      and x."archived_at" is null and x."id" <> archive_option_set_item.item
  ) then
    raise exception 'the replacement must be another active item of the same set' using errcode = '22023', hint = 'OPTION_SET_REPLACEMENT_INVALID';
  end if;
  if not exists (
    select 1 from "better_supabase"."option_set_items" x
    where x."option_set_id" = v_set and x."archived_at" is null and x."id" <> archive_option_set_item.item
  ) then
    raise exception 'an option set keeps at least one item' using errcode = '23514', hint = 'OPTION_SET_LAST_ITEM';
  end if;
      if v_type = 'work_item' and v_field = 'priority' then
      perform 1 from "better_supabase"."work_items" r where r."priority_option_id" = archive_option_set_item.item limit 1;
      v_used := found;
    else
      v_used := false;
    end if;
  if v_used then
    if archive_option_set_item.replacement is null then
      raise exception 'records use this item; pass a replacement' using errcode = '23503', hint = 'OPTION_SET_ITEM_IN_USE';
    end if;
        if v_type = 'work_item' and v_field = 'priority' then
      update "better_supabase"."work_items" r set "priority_option_id" = archive_option_set_item.replacement
      where r."priority_option_id" = archive_option_set_item.item;
    else
      null;
    end if;
  end if;
  update "better_supabase"."option_set_items" x set "archived_at" = now(), "updated_at" = now() where x."id" = archive_option_set_item.item;
  perform "better_supabase".emit_event('option_set_item.archived', jsonb_build_object('organizationId', v_tenant, 'optionSetId', v_set, 'itemId', v_item), 'option-sets/' || v_set::text, (v_tenant::text)::text, null, 'better-supabase/option-sets');
  perform better_supabase.audit_event(
    event_type => 'option_set_item.archived',
    category => 'configuration',
    target_type => 'option_set_item',
    record_id => v_item::text,
    summary => 'archived an option set item',
    tenant => (v_tenant::text)::uuid,
    metadata => jsonb_build_object('organizationId', v_tenant, 'optionSetId', v_set, 'itemId', v_item)
  );
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.begin_idempotent (
  scope        text,
  key          text,
  request_hash text,
  ttl          interval DEFAULT '24:00:00'::interval,
  lock         interval DEFAULT '00:01:00'::interval
)
  RETURNS TABLE (
    state       text,
    status_code integer,
    response    jsonb,
    holder      uuid
  )
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  existing "better_supabase"."idempotency_keys";
  token uuid := gen_random_uuid();
begin
  delete from "better_supabase"."idempotency_keys" k
  where k."scope" = begin_idempotent.scope and k."key" = begin_idempotent.key and k."expires_at" < now();

  insert into "better_supabase"."idempotency_keys" ("scope", "key", "request_hash", "status", "lock_expires_at", "expires_at", "holder")
  values (scope, key, request_hash, 'running', now() + lock, now() + ttl, token)
  on conflict ("scope", "key") do nothing;
  if found then
    return query select 'started'::text, null::integer, null::jsonb, token;
    return;
  end if;

  select * into existing from "better_supabase"."idempotency_keys" k
  where k."scope" = begin_idempotent.scope and k."key" = begin_idempotent.key
  for update;
  if existing."request_hash" <> request_hash then
    return query select 'mismatch'::text, null::integer, null::jsonb, null::uuid;
  elsif existing."status" = 'completed' then
    return query select 'replay'::text, existing."status_code", existing."response", null::uuid;
  elsif existing."lock_expires_at" < now() then
    -- The holder's lock ran out: this request takes the key over, and the
    -- former holder's complete and release now return false.
    update "better_supabase"."idempotency_keys" k set "lock_expires_at" = now() + lock, "holder" = token
    where k."scope" = begin_idempotent.scope and k."key" = begin_idempotent.key;
    return query select 'started'::text, null::integer, null::jsonb, token;
  else
    return query select 'running'::text, null::integer, null::jsonb, null::uuid;
  end if;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.bsb_option_work_item_priority()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_level integer;
begin
  if tg_op = 'UPDATE' and new."priority_option_id" is not distinct from old."priority_option_id" and new."priority" is not distinct from old."priority" then
    return new;
  end if;
  if new."priority_option_id" is not null and (tg_op = 'INSERT' or new."priority_option_id" is distinct from old."priority_option_id") then
    select x."level" into v_level
    from "better_supabase"."option_set_items" x
    join "better_supabase"."option_sets" y on y."id" = x."option_set_id"
    where x."id" = new."priority_option_id"
      and x."archived_at" is null
      and y."archived_at" is null
      and y."tenant_id"::text = new."tenant_id"::text
      and y."subject_type" = 'work_item'
      and y."field" = 'priority'
      and y."scope_id" is not distinct from null;
    if not found then
      raise exception 'the item is not an active item of this record''s option set' using errcode = '22023', hint = 'OPTION_SET_ITEM_INVALID';
    end if;
    new."priority" := v_level;
  end if;
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.checkpoint_webhook (
  inbox_id bigint,
  worker   text,
  fields   jsonb,
  attempt  integer DEFAULT NULL::integer
)
  RETURNS boolean
  LANGUAGE sql
  SET search_path TO ''
  AS $function$
  with saved as (
    update better_supabase.webhook_inbox
    set checkpoint = checkpoint || coalesce(fields, '{}')
    where id = inbox_id and locked_by = worker and status = 'processing'
      and (attempt is null or attempts = attempt)
    returning 1
  )
  select exists (select 1 from saved)
$function$;

CREATE OR REPLACE FUNCTION better_supabase.claim_webhooks (
  source text,
  worker text,
  batch  integer  DEFAULT 10,
  lease  interval DEFAULT '00:05:00'::interval
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$
  update better_supabase.webhook_inbox d
  set status = 'dead', last_error = 'The lease ran out on the last attempt', locked_by = null, lock_expires_at = null
  where d.source = claim_webhooks.source and d.status = 'processing'
    and d.lock_expires_at < now() and d.attempts >= d.max_attempts;
  with next as materialized (
    select c.id from better_supabase.webhook_inbox c
    where c.source = claim_webhooks.source
      and (
        (c.status = 'pending' and c.available_at <= now())
        or (c.status = 'processing' and c.lock_expires_at < now())
      )
    order by c.available_at, c.id
    for update skip locked
    limit batch
  ),
  claimed as (
    update better_supabase.webhook_inbox w
    set status = 'processing', attempts = w.attempts + 1, locked_by = worker, lock_expires_at = now() + lease
    from next
    where w.id = next.id
    returning w.id as id, jsonb_build_object('id', w.id, 'source', w.source, 'message_id', w.message_id, 'event_type', w.event_type, 'payload', w.payload, 'headers', w.headers, 'status', w.status, 'attempts', w.attempts, 'max_attempts', w.max_attempts, 'available_at', w.available_at, 'locked_by', w.locked_by, 'lock_expires_at', w.lock_expires_at, 'last_error', w.last_error, 'received_at', w.received_at, 'processed_at', w.processed_at, 'tenant', w.tenant, 'checkpoint', w.checkpoint) as message
  )
  select coalesce(jsonb_agg(claimed.message order by claimed.id), '[]'::jsonb) from claimed
$function$;

CREATE OR REPLACE FUNCTION better_supabase.complete_idempotent (
  scope       text,
  key         text,
  holder      uuid,
  status_code integer,
  response    jsonb
)
  RETURNS boolean
  LANGUAGE sql
  SET search_path TO ''
  AS $function$
  with done as (
    update "better_supabase"."idempotency_keys" k
    set "status" = 'completed', "status_code" = complete_idempotent.status_code,
        "response" = complete_idempotent.response, "lock_expires_at" = null, "holder" = null
    where k."scope" = complete_idempotent.scope and k."key" = complete_idempotent.key
      and k."status" = 'running' and k."holder" = complete_idempotent.holder
    returning 1
  )
  select exists (select 1 from done)
$function$;

CREATE OR REPLACE FUNCTION better_supabase.complete_webhook (
  inbox_id bigint,
  worker   text,
  attempt  integer DEFAULT NULL::integer
)
  RETURNS boolean
  LANGUAGE sql
  SET search_path TO ''
  AS $function$
  with done as (
    update better_supabase.webhook_inbox
    set status = 'processed', processed_at = now(), locked_by = null, lock_expires_at = null, last_error = null
    where id = inbox_id and locked_by = worker and status = 'processing'
      and (attempt is null or attempts = attempt)
    returning 1
  )
  select exists (select 1 from done)
$function$;

CREATE OR REPLACE FUNCTION better_supabase.create_incoming_webhook (
  tenant           uuid,
  name             text,
  verify           text  DEFAULT 'none'::text,
  metadata         jsonb DEFAULT '{}'::jsonb,
  signature_header text  DEFAULT NULL::text,
  subject_type     text  DEFAULT NULL::text,
  subject_id       text  DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_id uuid := gen_random_uuid();
  token text := encode(extensions.gen_random_bytes(24), 'hex');
  secret text := case verify
    when 'standard-webhooks' then 'whsec_' || encode(extensions.gen_random_bytes(32), 'base64')
    when 'hmac-sha256' then encode(extensions.gen_random_bytes(32), 'hex')
    when 'shared-secret' then encode(extensions.gen_random_bytes(32), 'hex')
  end;
  created "better_supabase"."incoming_webhooks";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.member_can(auth.uid(), tenant, 'webhooks.manage'), false)) then
    raise exception 'Not allowed to manage incoming webhooks' using errcode = '42501', hint = 'WEBHOOK_IN_FORBIDDEN';
  end if;
  if verify not in ('none', 'standard-webhooks', 'hmac-sha256', 'shared-secret') then
    raise exception 'Unknown verification mode' using errcode = '22023', hint = 'WEBHOOK_IN_VERIFY_UNKNOWN';
  end if;
  if (subject_type is null) <> (subject_id is null) then
    raise exception 'Pass subject_type and subject_id together' using errcode = '22023', hint = 'WEBHOOK_IN_SUBJECT_INVALID';
  end if;
  if subject_type is not null and not (true) then
    raise exception 'No such subject in this tenant' using errcode = '22023', hint = 'WEBHOOK_IN_SUBJECT_INVALID';
  end if;
  insert into "better_supabase"."incoming_webhooks" ("id", "tenant", "name", "token_hash", "verify", "secret", "secret_id", "signature_header", "metadata", "subject_type", "subject_id", "created_by")
  values (v_id,
    tenant,
    name,
    encode(extensions.digest(token, 'sha256'), 'hex'),
    verify,
    null,
    case when secret is null then null else vault.create_secret(secret, 'webhook-in:' || v_id::text || ':' || gen_random_uuid()::text, 'better-supabase incoming webhook secret') end,
    case verify
      when 'hmac-sha256' then coalesce(signature_header, null, 'x-signature')
      when 'shared-secret' then coalesce(signature_header, null, 'x-webhook-secret')
    end,
    coalesce(metadata, '{}'),
    subject_type,
    subject_id,
    auth.uid())
  returning * into created;
  perform "better_supabase".emit_event('incoming_webhook.created', jsonb_build_object('organizationId', created."tenant"::text, 'endpointId', created."id", 'name', created."name"), 'organizations/' || created."tenant"::text || '/incoming-webhooks/' || created."id"::text, (created."tenant")::text, null, 'better-supabase/webhooks-in');
  perform better_supabase.audit_event(
    event_type => 'incoming_webhook.created',
    category => 'integration',
    target_type => 'incoming_webhook',
    record_id => created."id"::text,
    tenant => (created."tenant")::uuid,
    metadata => jsonb_build_object('organizationId', created."tenant"::text, 'endpointId', created."id", 'name', created."name")
  );
  return jsonb_build_object('id', created."id", 'tenant', created."tenant", 'name', created."name",
    'verify', created."verify", 'token', token, 'secret', secret, 'signatureHeader', created."signature_header",
    'subjectType', created."subject_type", 'subjectId', created."subject_id");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.create_ssf_stream (
  id               uuid,
  receiver         text,
  tenant           text,
  audience         text[],
  delivery_method  text,
  events_requested text[],
  events_delivered text[],
  description      text   DEFAULT NULL::text,
  endpoint_url     text   DEFAULT NULL::text,
  credential_ref   jsonb  DEFAULT NULL::jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."ssf_streams";
  v_endpoint uuid;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role manages shared signals streams' using errcode = '42501', hint = 'SSF_FORBIDDEN';
  end if;
  insert into "better_supabase"."ssf_streams" ("id", "tenant", "receiver", "audience", "delivery_method", "events_requested", "events_delivered", "description")
  values (create_ssf_stream.id, create_ssf_stream.tenant, create_ssf_stream.receiver, create_ssf_stream.audience,
    create_ssf_stream.delivery_method, coalesce(create_ssf_stream.events_requested, '{}'),
    coalesce(create_ssf_stream.events_delivered, '{}'), create_ssf_stream.description)
  returning * into v_row;
  if v_row."delivery_method" = 'urn:ietf:rfc:8935' then
    if coalesce(create_ssf_stream.endpoint_url, '') = '' then
      raise exception 'a push stream needs an endpoint_url' using errcode = '22023', hint = 'SSF_ENDPOINT_REQUIRED';
    end if;
    if v_row."tenant" is null then
      raise exception 'a push stream needs a tenant when webhook endpoints have one' using errcode = '22023', hint = 'SSF_TENANT_REQUIRED';
    end if;
    insert into "better_supabase"."webhook_endpoints" as we ("tenant_id", "name", "url", "format", "credential_ref")
    values (v_row."tenant"::uuid, 'Shared Signals stream ' || v_row."id", create_ssf_stream.endpoint_url, 'set', create_ssf_stream.credential_ref)
    returning we."id" into v_endpoint;
    update "better_supabase"."ssf_streams" s set "endpoint_id" = v_endpoint where s."id" = v_row."id"
    returning s.* into v_row;
  end if;
  perform "better_supabase".emit_event('ssf_stream.created', jsonb_build_object('streamId', v_row."id", 'receiver', v_row."receiver", 'tenant', v_row."tenant", 'method', v_row."delivery_method"), 'shared-signals/' || v_row."id", null, null, 'better-supabase/security-events');
  perform better_supabase.audit_event(
    event_type => 'ssf_stream.created',
    category => 'security',
    target_type => 'ssf_stream',
    record_id => v_row."id"::text,
    metadata => jsonb_build_object('streamId', v_row."id", 'receiver', v_row."receiver", 'tenant', v_row."tenant", 'method', v_row."delivery_method")
  );
  return jsonb_build_object(
    'id', v_row."id",
    'tenant', v_row."tenant",
    'receiver', v_row."receiver",
    'audience', to_jsonb(v_row."audience"),
    'description', v_row."description",
    'eventsRequested', to_jsonb(v_row."events_requested"),
    'eventsDelivered', to_jsonb(v_row."events_delivered"),
    'method', v_row."delivery_method",
    'endpointUrl', (select we."url" from "better_supabase"."webhook_endpoints" we where we."id" = v_row."endpoint_id"),
    'status', v_row."status",
    'reason', v_row."reason",
    'createdAt', v_row."created_at",
    'updatedAt', v_row."updated_at"
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.default_option_set (
  tenant       uuid,
  subject_type text,
  field        text,
  scope_id     text
)
  RETURNS uuid
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_id uuid;
  v_brand text;
begin
  select x."id" into v_id from "better_supabase"."option_sets" x
  where x."tenant_id" = default_option_set.tenant
    and x."subject_type" = default_option_set.subject_type
    and x."field" = default_option_set.field
    and x."scope_id" is not distinct from default_option_set.scope_id
    and x."archived_at" is null
  order by x."is_default" desc, x."created_at", x."id"
  limit 1;
  if v_id is not null then
    return v_id;
  end if;
      if default_option_set.subject_type = 'work_item' and default_option_set.field = 'priority' then
      insert into "better_supabase"."option_sets" ("tenant_id", "subject_type", "field", "scope_id", "key", "name", "is_default")
      values (default_option_set.tenant, default_option_set.subject_type, default_option_set.field, default_option_set.scope_id, 'default', 'Default', true)
      on conflict do nothing
      returning "id" into v_id;
      if v_id is null then
        select x."id" into v_id from "better_supabase"."option_sets" x
        where x."tenant_id" = default_option_set.tenant
          and x."subject_type" = default_option_set.subject_type
          and x."field" = default_option_set.field
          and x."scope_id" is not distinct from default_option_set.scope_id
          and x."archived_at" is null
        order by x."is_default" desc, x."created_at", x."id"
        limit 1;
        if v_id is null then
          raise exception 'the default option set of this field is archived' using errcode = '55000', hint = 'OPTION_SET_UNAVAILABLE';
        end if;
        return v_id;
      end if;
      insert into "better_supabase"."option_set_items" ("tenant_id", "option_set_id", "key", "system_key", "label", "color", "icon", "rank", "level")
      select default_option_set.tenant, v_id, x.key, x.key, x.label, x.color, x.icon, x.rank, x.level
      from (values
          ('none', 'None', 0, null::text, null::text, 'A'),
          ('low', 'Low', 1, null::text, null::text, 'K'),
          ('medium', 'Medium', 2, null::text, null::text, 'U'),
          ('high', 'High', 3, null::text, null::text, 'e'),
          ('urgent', 'Urgent', 4, null::text, null::text, 'o')
      ) x(key, label, level, color, icon, rank);
    else
      raise exception 'this field has no option set binding' using errcode = '22023', hint = 'OPTION_SET_FIELD_UNKNOWN';
    end if;
  return v_id;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.delete_incoming_webhook (
  endpoint uuid
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  tenant uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select e."tenant" into tenant from "better_supabase"."incoming_webhooks" e where e."id" = endpoint;
  if tenant is null or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.member_can(auth.uid(), tenant, 'webhooks.manage'), false)) then
    return false;
  end if;
  delete from "better_supabase"."incoming_webhooks" e where e."id" = endpoint;
  perform "better_supabase".emit_event('incoming_webhook.deleted', jsonb_build_object('organizationId', tenant::text, 'endpointId', endpoint), 'organizations/' || tenant::text || '/incoming-webhooks/' || endpoint::text, (tenant)::text, null, 'better-supabase/webhooks-in');
  perform better_supabase.audit_event(
    event_type => 'incoming_webhook.deleted',
    category => 'integration',
    target_type => 'incoming_webhook',
    record_id => endpoint::text,
    tenant => (tenant)::uuid,
    metadata => jsonb_build_object('organizationId', tenant::text, 'endpointId', endpoint)
  );
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.delete_ssf_stream (
  id uuid
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."ssf_streams";
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role manages shared signals streams' using errcode = '42501', hint = 'SSF_FORBIDDEN';
  end if;
  delete from "better_supabase"."ssf_streams" s where s."id" = delete_ssf_stream.id returning s.* into v_row;
  if not found then
    return false;
  end if;
  if v_row."endpoint_id" is not null then
    delete from "better_supabase"."webhook_endpoints" we where we."id" = v_row."endpoint_id";
  end if;
  perform "better_supabase".emit_event('ssf_stream.deleted', jsonb_build_object('streamId', v_row."id", 'receiver', v_row."receiver", 'tenant', v_row."tenant"), 'shared-signals/' || v_row."id", null, null, 'better-supabase/security-events');
  perform better_supabase.audit_event(
    event_type => 'ssf_stream.deleted',
    category => 'security',
    target_type => 'ssf_stream',
    record_id => v_row."id"::text,
    metadata => jsonb_build_object('streamId', v_row."id", 'receiver', v_row."receiver", 'tenant', v_row."tenant")
  );
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.drop_incoming_webhook_secret()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  delete from vault.secrets vs where vs.id in (old."secret_id", old."previous_secret_id");
  return null;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.enforce_slug()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
declare
  value text := to_jsonb(new) ->> coalesce(tg_argv[0], 'slug');
  problem text := better_supabase.slug_problem(value);
begin
  if problem = 'invalid' then
    raise exception 'Invalid slug "%"', value using errcode = '23514', hint = 'SLUG_INVALID';
  elsif problem = 'reserved' then
    raise exception 'The slug "%" is reserved', value using errcode = '23514', hint = 'SLUG_RESERVED';
  end if;
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.ensure_option_set (
  tenant       uuid,
  subject_type text,
  field        text,
  scope_id     text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_set uuid;
begin
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', ensure_option_set.tenant, 'option_sets.read'), false)) then
    raise exception 'not allowed to read option sets' using errcode = '42501', hint = 'OPTION_SET_FORBIDDEN';
  end if;
  v_set := "better_supabase"."default_option_set"(ensure_option_set.tenant, ensure_option_set.subject_type, ensure_option_set.field, ensure_option_set.scope_id);
  return (select to_jsonb(y) || jsonb_build_object('items', coalesce((
      select jsonb_agg(to_jsonb(z) order by z."rank" collate "C", z."id")
      from "better_supabase"."option_set_items" z
      where z."option_set_id" = y."id" and (false or z."archived_at" is null)
    ), '[]'::jsonb)) from "better_supabase"."option_sets" y where y."id" = v_set);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.extend_idempotent (
  scope  text,
  key    text,
  holder uuid,
  lock   interval DEFAULT '00:01:00'::interval
)
  RETURNS boolean
  LANGUAGE sql
  SET search_path TO ''
  AS $function$
  with extended as (
    update "better_supabase"."idempotency_keys" k
    set "lock_expires_at" = now() + extend_idempotent.lock
    where k."scope" = extend_idempotent.scope and k."key" = extend_idempotent.key
      and k."status" = 'running' and k."holder" = extend_idempotent.holder
      and k."lock_expires_at" > now()
    returning 1
  )
  select exists (select 1 from extended)
$function$;

CREATE OR REPLACE FUNCTION better_supabase.extend_lease (
  key     text,
  holder  uuid,
  seconds integer DEFAULT 60,
  scope   text    DEFAULT ''::text
)
  RETURNS boolean
  LANGUAGE sql
  SET search_path TO ''
  AS $function$
  with extended as (
    update "better_supabase"."idempotency_leases" l
    set "expires_at" = now() + make_interval(secs => greatest(extend_lease.seconds, 1))
    where l."scope" = extend_lease.scope and l."key" = extend_lease.key
      and l."holder" = extend_lease.holder and l."expires_at" > now()
    returning 1
  )
  select exists (select 1 from extended)
$function$;

CREATE OR REPLACE FUNCTION better_supabase.extend_webhook (
  inbox_id bigint,
  worker   text,
  attempt  integer,
  lease    interval DEFAULT '00:05:00'::interval
)
  RETURNS double precision
  LANGUAGE sql
  SET search_path TO ''
  AS $function$
  update better_supabase.webhook_inbox
  set lock_expires_at = now() + lease
  where id = inbox_id and locked_by = worker and status = 'processing'
    and attempts = attempt
  returning extract(epoch from lease)::double precision
$function$;

CREATE OR REPLACE FUNCTION better_supabase.fail_webhook (
  inbox_id  bigint,
  worker    text,
  error     text,
  retry_in  interval DEFAULT NULL::interval,
  attempt   integer  DEFAULT NULL::integer,
  permanent boolean  DEFAULT false
)
  RETURNS text
  LANGUAGE sql
  SET search_path TO ''
  AS $function$
  update better_supabase.webhook_inbox
  set status = case when permanent or attempts >= max_attempts then 'dead' else 'pending' end,
      available_at = now() + coalesce(retry_in, least(interval '1 hour', interval '1 second' * power(2, attempts))),
      last_error = left(error, 4000),
      locked_by = null,
      lock_expires_at = null
  where id = inbox_id and locked_by = worker and status = 'processing'
    and (attempt is null or attempts = attempt)
  returning status
$function$;

CREATE OR REPLACE FUNCTION better_supabase.forget_ssf_received (
  issuer text,
  jti    text
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role manages shared signals streams' using errcode = '42501', hint = 'SSF_FORBIDDEN';
  end if;
  delete from "better_supabase"."ssf_received" x where x."issuer" = forget_ssf_received.issuer and x."jti" = forget_ssf_received.jti;
  return found;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.hostname_by_id (
  id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."hostnames";
begin
  select * into v_row from "better_supabase"."hostnames" x where x."id" = hostname_by_id.id;
  if v_row."id" is null or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'domains.manage'), false)) then
    return null;
  end if;
  return (to_jsonb(v_row) - 'verification_token') || case when v_row."verified_at" is null then jsonb_build_object('record', jsonb_build_object('type', 'TXT', 'name', '_better-supabase.' || v_row."hostname", 'value', 'better-supabase-hostname-verification=' || v_row."verification_token")) else '{}'::jsonb end;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.incoming_webhook_by_token (
  token text
)
  RETURNS TABLE (
    id               uuid,
    tenant           text,
    enabled          boolean,
    verify           text,
    secret           text,
    signature_header text,
    max_body_bytes   integer,
    previous_secret  text,
    metadata         jsonb
  )
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select e."id", e."tenant"::text, e."enabled", e."verify", coalesce(ds.decrypted_secret, e."secret"), e."signature_header", e."max_body_bytes",
    case when e."previous_secret_expires_at" > now() then coalesce(dp.decrypted_secret, e."previous_secret") end, e."metadata"
  from "better_supabase"."incoming_webhooks" e
  left join vault.decrypted_secrets ds on ds.id = e."secret_id"
  left join vault.decrypted_secrets dp on dp.id = e."previous_secret_id"
  where e."token_hash" = encode(extensions.digest(incoming_webhook_by_token.token, 'sha256'), 'hex')
$function$;

CREATE OR REPLACE FUNCTION better_supabase.incoming_webhook_subject_readable (
  subject_type text,
  subject_id   text,
  tenant       uuid
)
  RETURNS boolean
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select subject_type is null or true
$function$;

CREATE OR REPLACE FUNCTION better_supabase.incoming_webhook_tenant_ids()
  RETURNS SETOF uuid
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  return query select better_supabase.tenant_ids_with('webhooks.read');
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_hostnames (
  tenant uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', list_hostnames.tenant, 'domains.read'), false)) then
    raise exception 'You may not read this organization''s hostnames' using errcode = '42501', hint = 'HOSTNAME_FORBIDDEN';
  end if;
  return (
    select coalesce(jsonb_agg((to_jsonb(x) - 'verification_token') || case when x."verified_at" is null then jsonb_build_object('record', jsonb_build_object('type', 'TXT', 'name', '_better-supabase.' || x."hostname", 'value', 'better-supabase-hostname-verification=' || x."verification_token")) else '{}'::jsonb end order by x."is_primary" desc, x."hostname"), '[]'::jsonb)
    from "better_supabase"."hostnames" x where x."tenant_id" = list_hostnames.tenant
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_incoming_webhooks (
  tenant       uuid,
  subject_type text DEFAULT NULL::text,
  subject_id   text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', e."id",
    'tenant', e."tenant",
    'name', e."name",
    'verify', e."verify",
    'signature_header', e."signature_header",
    'enabled', e."enabled",
    'max_body_bytes', e."max_body_bytes",
    'receive_count', e."receive_count",
    'last_received_at', e."last_received_at",
    'last_status', e."last_status",
    'metadata', e."metadata",
    'subject_type', e."subject_type",
    'subject_id', e."subject_id",
    'created_by', e."created_by",
    'created_at', e."created_at"
  ) order by e."created_at"), '[]'::jsonb)
  from "better_supabase"."incoming_webhooks" e
  where e."tenant" = list_incoming_webhooks.tenant
    and (list_incoming_webhooks.subject_type is null or e."subject_type" = list_incoming_webhooks.subject_type)
    and (list_incoming_webhooks.subject_id is null or e."subject_id" = list_incoming_webhooks.subject_id)
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_option_sets (
  tenant  uuid,
  filters jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_filters jsonb := coalesce(list_option_sets.filters, '{}'::jsonb);
  v_archived boolean := coalesce((v_filters ->> 'includeArchived')::boolean, false);
begin
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', list_option_sets.tenant, 'option_sets.read'), false)) then
    raise exception 'not allowed to read option sets' using errcode = '42501', hint = 'OPTION_SET_FORBIDDEN';
  end if;
  return coalesce((
    select jsonb_agg(to_jsonb(y) || jsonb_build_object('items', coalesce((
      select jsonb_agg(to_jsonb(z) order by z."rank" collate "C", z."id")
      from "better_supabase"."option_set_items" z
      where z."option_set_id" = y."id" and (v_archived or z."archived_at" is null)
    ), '[]'::jsonb)) order by y."is_default" desc, y."created_at", y."id")
    from "better_supabase"."option_sets" y
    where y."tenant_id" = list_option_sets.tenant
      and (v_archived or y."archived_at" is null)
      and (not v_filters ? 'subjectType' or y."subject_type" = v_filters ->> 'subjectType')
      and (not v_filters ? 'field' or y."field" = v_filters ->> 'field')
      and (not v_filters ? 'scopeId' or y."scope_id" is not distinct from (v_filters ->> 'scopeId'))
  ), '[]'::jsonb);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_webhooks (
  for_tenant text,
  for_source text    DEFAULT NULL::text,
  for_status text    DEFAULT NULL::text,
  max_rows   integer DEFAULT 100
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select coalesce(jsonb_agg(x.message order by x.n), '[]'::jsonb)
  from (
    select jsonb_build_object('id', w.id, 'source', w.source, 'message_id', w.message_id, 'event_type', w.event_type, 'payload', w.payload, 'headers', w.headers, 'status', w.status, 'attempts', w.attempts, 'max_attempts', w.max_attempts, 'available_at', w.available_at, 'locked_by', w.locked_by, 'lock_expires_at', w.lock_expires_at, 'last_error', w.last_error, 'received_at', w.received_at, 'processed_at', w.processed_at, 'tenant', w.tenant, 'checkpoint', w.checkpoint) as message, row_number() over (order by w.received_at desc, w.id desc) as n
    from better_supabase.webhook_inbox w
    where w.tenant = for_tenant
      and (for_source is null or w.source = for_source)
      and (for_status is null or w.status = for_status)
    order by w.received_at desc, w.id desc
    limit least(greatest(max_rows, 1), 1000)
  ) x
$function$;

CREATE OR REPLACE FUNCTION better_supabase.note_ssf_verification (
  stream_id    uuid,
  min_interval interval
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_noted boolean;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role manages shared signals streams' using errcode = '42501', hint = 'SSF_FORBIDDEN';
  end if;
  if not exists (select 1 from "better_supabase"."ssf_streams" s where s."id" = note_ssf_verification.stream_id) then
    raise exception 'stream not found' using errcode = 'P0002', hint = 'SSF_STREAM_NOT_FOUND';
  end if;
  update "better_supabase"."ssf_streams" s set "verified_at" = now()
  where s."id" = note_ssf_verification.stream_id
    and (s."verified_at" is null or s."verified_at" + coalesce(note_ssf_verification.min_interval, '0 seconds') <= now())
  returning true into v_noted;
  return coalesce(v_noted, false);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.operation_permission (
  op text
)
  RETURNS text
  LANGUAGE sql
  IMMUTABLE
  SET search_path TO ''
  AS $function$
  select case op
    when 'access-requests.create' then 'access_requests.create'
    when 'access-requests.emergency' then 'access_requests.emergency'
    when 'access-requests.manage' then 'access_requests.manage'
    when 'access-requests.read' then 'access_requests.read'
    when 'access-requests.review' then 'access_requests.review'
    when 'accounting.close' then 'accounting.close'
    when 'accounting.manage' then 'accounting.manage'
    when 'accounting.post' then 'accounting.post'
    when 'accounting.read' then 'accounting.read'
    when 'accounting.write' then 'accounting.write'
    when 'acknowledgements.acknowledge' then 'acknowledgements.acknowledge'
    when 'acknowledgements.manage' then 'acknowledgements.manage'
    when 'acknowledgements.read' then 'acknowledgements.read'
    when 'activities.manage' then 'activities.manage'
    when 'activities.read' then 'activities.read'
    when 'activities.readRestricted' then 'activities.read_restricted'
    when 'activities.write' then 'activities.write'
    when 'agents.create' then 'agents.write'
    when 'agents.moderate' then 'agents.moderate'
    when 'agents.publish' then 'agents.publish'
    when 'agents.read' then 'agents.read'
    when 'ai-chat.create' then 'ai_chat.create'
    when 'ai-chat.manage' then 'ai_chat.manage'
    when 'ai-chat.moderate' then 'ai_chat.moderate'
    when 'ai-chat.read' then 'ai_chat.read'
    when 'ai-chat.share' then 'ai_chat.share'
    when 'ai-files.manage' then 'ai_files.manage'
    when 'ai-files.upload' then 'ai_files.upload'
    when 'ai-keys.manage' then 'ai_keys.manage'
    when 'ai-keys.use' then 'ai_keys.use'
    when 'ai-schedules.create' then 'ai_schedules.write'
    when 'ai-schedules.manage' then 'ai_schedules.manage'
    when 'announcements.manage' then 'announcements.manage'
    when 'api-keys.manage' then 'api_keys.manage'
    when 'api-keys.own' then 'api_keys.own'
    when 'appraisals.manage' then 'appraisals.manage'
    when 'appraisals.read' then 'appraisals.read'
    when 'appraisals.review' then 'appraisals.review'
    when 'approvals.manage' then 'approvals.manage'
    when 'approvals.read' then 'approvals.read'
    when 'approvals.request' then 'approvals.request'
    when 'assets.assign' then 'assets.assign'
    when 'assets.manage' then 'assets.manage'
    when 'assets.read' then 'assets.read'
    when 'assignment.assign' then 'assignment.assign'
    when 'assignment.manage' then 'assignment.manage'
    when 'assignment.read' then 'assignment.read'
    when 'attachments.manage' then 'attachments.manage'
    when 'attachments.read' then 'attachments.read'
    when 'attachments.upload' then 'attachments.upload'
    when 'audit.read' then 'audit.read'
    when 'audit.readAll' then 'audit.read'
    when 'audit.revert' then 'audit.revert'
    when 'automations.manage' then 'automations.manage'
    when 'automations.publish' then 'automations.publish'
    when 'automations.read' then 'automations.read'
    when 'automations.write' then 'automations.write'
    when 'banking.import' then 'banking.import'
    when 'banking.manage' then 'banking.manage'
    when 'banking.read' then 'banking.read'
    when 'banking.reconcile' then 'banking.reconcile'
    when 'billable-time.invoice' then 'billable_time.invoice'
    when 'billable-time.manage' then 'billable_time.manage'
    when 'billable-time.read' then 'billable_time.read'
    when 'bookings.create' then 'bookings.create'
    when 'bookings.manage' then 'bookings.manage'
    when 'bookings.read' then 'bookings.read'
    when 'bulk-actions.run' then 'bulk_actions.run'
    when 'calendar.manage' then 'calendar.manage'
    when 'calendar.read' then 'calendar.read'
    when 'calendar.write' then 'calendar.write'
    when 'care-plans.evaluate' then 'care_plans.evaluate'
    when 'care-plans.manage' then 'care_plans.manage'
    when 'care-plans.publish' then 'care_plans.publish'
    when 'care-plans.read' then 'care_plans.read'
    when 'care-plans.write' then 'care_plans.write'
    when 'cases.close' then 'cases.close'
    when 'cases.create' then 'cases.create'
    when 'cases.manage' then 'cases.manage'
    when 'cases.read' then 'cases.read'
    when 'cases.write' then 'cases.write'
    when 'catalog.manage' then 'catalog.manage'
    when 'catalog.read' then 'catalog.read'
    when 'channels.create' then 'channels.create'
    when 'channels.manage' then 'channels.manage'
    when 'channels.read' then 'messages.read'
    when 'clinical-decision-support.manage' then 'clinical_decision_support.manage'
    when 'clinical-decision-support.read' then 'clinical_decision_support.read'
    when 'clinical-decision-support.write' then 'clinical_decision_support.write'
    when 'comments.create' then 'messages.send'
    when 'comments.moderate' then 'messages.moderate'
    when 'comments.read' then 'messages.read'
    when 'commissions.manage' then 'commissions.manage'
    when 'commissions.read' then 'commissions.read'
    when 'commissions.write' then 'commissions.write'
    when 'compliance.collect' then 'compliance.collect'
    when 'compliance.manage' then 'compliance.manage'
    when 'compliance.read' then 'compliance.read'
    when 'connectors.manage' then 'connectors.manage'
    when 'connectors.read' then 'connectors.read'
    when 'connectors.use' then 'connectors.use'
    when 'consents.manage' then 'consents.manage'
    when 'consents.read' then 'consents.read'
    when 'consents.record' then 'consents.record'
    when 'contacts.approveSupplier' then 'contacts.approve_supplier'
    when 'contacts.manage' then 'contacts.manage'
    when 'contacts.read' then 'contacts.read'
    when 'contacts.write' then 'contacts.write'
    when 'content.publish' then 'content.publish'
    when 'content.read' then 'content.read'
    when 'content.write' then 'content.write'
    when 'contracts.manage' then 'contracts.manage'
    when 'contracts.read' then 'contracts.read'
    when 'contracts.write' then 'contracts.write'
    when 'courses.enroll' then 'courses.enroll'
    when 'courses.manage' then 'courses.manage'
    when 'courses.read' then 'courses.read'
    when 'custom-fields.manage' then 'custom_fields.manage'
    when 'custom-fields.read' then 'custom_fields.read'
    when 'custom-fields.sensitive' then 'custom_fields.read_sensitive'
    when 'dam.read' then 'dam.read'
    when 'dam.write' then 'dam.write'
    when 'data-lifecycle.cancelDelete' then 'organization.delete'
    when 'data-lifecycle.delete' then 'organization.delete'
    when 'data-lifecycle.export' then 'data_lifecycle.export'
    when 'deadlines.manage' then 'deadlines.manage'
    when 'deadlines.read' then 'deadlines.read'
    when 'deadlines.write' then 'deadlines.write'
    when 'deals.manage' then 'deals.manage'
    when 'deals.read' then 'deals.read'
    when 'deals.write' then 'deals.write'
    when 'dispatch.manage' then 'dispatch.manage'
    when 'dispatch.read' then 'dispatch.read'
    when 'dispatch.work' then 'dispatch.work'
    when 'document-templates.manage' then 'document_templates.manage'
    when 'document-templates.read' then 'document_templates.read'
    when 'documents.manage' then 'documents.manage'
    when 'documents.read' then 'documents.read'
    when 'documents.suggest' then 'documents.suggest'
    when 'documents.write' then 'documents.write'
    when 'domains.manage' then 'domains.manage'
    when 'domains.read' then 'domains.read'
    when 'donations.manage' then 'donations.manage'
    when 'donations.read' then 'donations.read'
    when 'drive.create' then 'drive.create'
    when 'drive.manage' then 'drive.manage'
    when 'drive.read' then 'drive.read'
    when 'e-prescribing.manage' then 'e_prescribing.manage'
    when 'e-prescribing.read' then 'e_prescribing.read'
    when 'e-prescribing.sign' then 'e_prescribing.sign'
    when 'e-prescribing.write' then 'e_prescribing.write'
    when 'employees.read' then 'employees.read'
    when 'employees.readSensitive' then 'employees.read_sensitive'
    when 'employees.write' then 'employees.write'
    when 'enrichment.read' then 'enrichment.read'
    when 'enrichment.run' then 'enrichment.run'
    when 'enrollments.enroll' then 'enrollments.enroll'
    when 'enrollments.manage' then 'enrollments.manage'
    when 'enrollments.read' then 'enrollments.read'
    when 'expenses.approve' then 'expenses.approve'
    when 'expenses.manage' then 'expenses.manage'
    when 'expenses.read' then 'expenses.read'
    when 'expenses.submit' then 'expenses.submit'
    when 'field-history.read' then 'field_history.read'
    when 'flags.manage' then 'flags.manage'
    when 'forecasts.read' then 'forecasts.read'
    when 'forecasts.snapshot' then 'forecasts.snapshot'
    when 'forms.manage' then 'forms.manage'
    when 'forms.read' then 'forms.read'
    when 'forms.review' then 'forms.review'
    when 'forms.submit' then 'forms.submit'
    when 'funding.approve' then 'funding.approve'
    when 'funding.claim' then 'funding.claim'
    when 'funding.manage' then 'funding.manage'
    when 'funding.read' then 'funding.read'
    when 'funding.register' then 'funding.register'
    when 'funding.write' then 'funding.write'
    when 'goals.manage' then 'goals.manage'
    when 'goals.read' then 'goals.read'
    when 'guests.manage' then 'guests.manage'
    when 'guests.read' then 'guests.read'
    when 'hiring.manage' then 'hiring.manage'
    when 'hiring.read' then 'hiring.read'
    when 'hiring.write' then 'hiring.write'
    when 'imports.manage' then 'imports.manage'
    when 'inbox.assign' then 'inbox.assign'
    when 'inbox.manage' then 'inbox.manage'
    when 'inbox.read' then 'inbox.read'
    when 'inbox.reply' then 'inbox.reply'
    when 'incidents.manage' then 'incidents.manage'
    when 'incidents.read' then 'incidents.read'
    when 'incidents.write' then 'incidents.write'
    when 'inspections.manage' then 'inspections.manage'
    when 'inspections.read' then 'inspections.read'
    when 'inspections.write' then 'inspections.write'
    when 'inventory.manage' then 'inventory.manage'
    when 'inventory.purchase' then 'inventory.purchase'
    when 'inventory.read' then 'inventory.read'
    when 'inventory.reserve' then 'inventory.reserve'
    when 'invitations.invite' then 'members.invite'
    when 'invitations.invitePlatform' then 'platform.invite'
    when 'invitations.read' then 'members.invite'
    when 'invitations.revoke' then 'members.invite'
    when 'invoices.approve' then 'invoices.approve'
    when 'invoices.collect' then 'invoices.collect'
    when 'invoices.manage' then 'invoices.manage'
    when 'invoices.overrideMatch' then 'invoices.override_match'
    when 'invoices.purchase' then 'invoices.purchase'
    when 'invoices.read' then 'invoices.read'
    when 'invoices.send' then 'invoices.send'
    when 'invoices.write' then 'invoices.write'
    when 'knowledge.manage' then 'knowledge.manage'
    when 'knowledge.read' then 'knowledge.read'
    when 'knowledge.write' then 'knowledge.write'
    when 'leases.maintain' then 'leases.maintain'
    when 'leases.manage' then 'leases.manage'
    when 'leases.read' then 'leases.read'
    when 'ledger.manage' then 'ledger.manage'
    when 'ledger.post' then 'ledger.post'
    when 'ledger.read' then 'ledger.read'
    when 'legal-entities.manage' then 'legal_entities.manage'
    when 'legal-entities.read' then 'legal_entities.read'
    when 'lims.manage' then 'lims.manage'
    when 'lims.read' then 'lims.read'
    when 'lims.write' then 'lims.write'
    when 'mail-sync.connect' then 'mail_sync.connect'
    when 'mail-sync.manage' then 'mail_sync.manage'
    when 'mail-sync.read' then 'mail_sync.read'
    when 'mail-sync.send' then 'mail_sync.send'
    when 'maintenance.manage' then 'maintenance.manage'
    when 'maintenance.read' then 'maintenance.read'
    when 'maintenance.record' then 'maintenance.record'
    when 'manufacturing.manage' then 'manufacturing.manage'
    when 'manufacturing.produce' then 'manufacturing.produce'
    when 'manufacturing.read' then 'manufacturing.read'
    when 'manufacturing.write' then 'manufacturing.write'
    when 'medications.administer' then 'medications.administer'
    when 'medications.manage' then 'medications.manage'
    when 'medications.prescribe' then 'medications.prescribe'
    when 'medications.read' then 'medications.read'
    when 'meetings.manage' then 'meetings.manage'
    when 'meetings.read' then 'meetings.read'
    when 'meetings.write' then 'meetings.write'
    when 'memory.manage' then 'memory.manage'
    when 'memory.read' then 'memory.read'
    when 'messaging.moderate' then 'messages.moderate'
    when 'messaging.read' then 'messages.read'
    when 'messaging.send' then 'messages.send'
    when 'metrics.manage' then 'metrics.manage'
    when 'metrics.read' then 'metrics.read'
    when 'moderation.ban' then 'moderation.ban'
    when 'moderation.manage' then 'moderation.manage'
    when 'moderation.read' then 'moderation.read'
    when 'moderation.report' then 'moderation.report'
    when 'notifications.read' then 'notifications.read'
    when 'notifications.send' then 'notifications.send'
    when 'numbering.assign' then 'numbering.assign'
    when 'observations.manage' then 'observations.manage'
    when 'observations.read' then 'observations.read'
    when 'observations.record' then 'observations.record'
    when 'onboarding.complete' then 'onboarding.complete'
    when 'onboarding.read' then 'onboarding.read'
    when 'option-sets.manage' then 'option_sets.manage'
    when 'option-sets.read' then 'option_sets.read'
    when 'orders.manage' then 'orders.manage'
    when 'orders.overrideCredit' then 'orders.override_credit'
    when 'orders.prepare' then 'orders.prepare'
    when 'orders.read' then 'orders.read'
    when 'organizations.delete' then 'organization.delete'
    when 'organizations.listMembers' then 'members.read'
    when 'organizations.removeMember' then 'members.remove'
    when 'organizations.suspendMember' then 'members.remove'
    when 'organizations.transferOwnership' then 'organization.transfer_ownership'
    when 'organizations.update' then 'organization.update'
    when 'organizations.updateRole' then 'members.update_role'
    when 'passes.checkIn' then 'passes.check_in'
    when 'passes.manage' then 'passes.manage'
    when 'passes.read' then 'passes.read'
    when 'payroll-export.export' then 'payroll_export.export'
    when 'payroll-export.read' then 'payroll_export.read'
    when 'periods.manage' then 'periods.manage'
    when 'periods.read' then 'periods.read'
    when 'periods.write' then 'periods.write'
    when 'permissions.listRoles' then 'members.read'
    when 'permissions.setOverride' then 'roles.manage'
    when 'pipelines.manage' then 'pipelines.manage'
    when 'pipelines.read' then 'pipelines.read'
    when 'posts.manage' then 'posts.manage'
    when 'posts.moderate' then 'posts.moderate'
    when 'posts.read' then 'posts.read'
    when 'posts.write' then 'posts.write'
    when 'promotions.manage' then 'promotions.manage'
    when 'promotions.read' then 'promotions.read'
    when 'qualifications.grant' then 'qualifications.grant'
    when 'qualifications.manage' then 'qualifications.manage'
    when 'qualifications.read' then 'qualifications.read'
    when 'quotes.manage' then 'quotes.manage'
    when 'quotes.read' then 'quotes.read'
    when 'quotes.write' then 'quotes.write'
    when 'reactions.create' then 'reactions.create'
    when 'reactions.manage' then 'reactions.manage'
    when 'reactions.read' then 'reactions.read'
    when 'referrals.manage' then 'referrals.manage'
    when 'referrals.read' then 'referrals.read'
    when 'referrals.write' then 'referrals.write'
    when 'relations.manage' then 'relations.manage'
    when 'relations.read' then 'relations.read'
    when 'reminders.manage' then 'reminders.manage'
    when 'reminders.read' then 'reminders.read'
    when 'rfqs.manage' then 'rfqs.manage'
    when 'rfqs.read' then 'rfqs.read'
    when 'rfqs.write' then 'rfqs.write'
    when 'risks.assess' then 'risks.assess'
    when 'risks.manage' then 'risks.manage'
    when 'risks.read' then 'risks.read'
    when 'risks.write' then 'risks.write'
    when 'saved-views.read' then 'saved_views.read'
    when 'saved-views.share' then 'saved_views.share'
    when 'scores.compute' then 'scores.compute'
    when 'scores.manage' then 'scores.manage'
    when 'scores.read' then 'scores.read'
    when 'search.read' then 'search.read'
    when 'segments.read' then 'segments.read'
    when 'segments.write' then 'segments.write'
    when 'sequences.enroll' then 'sequences.enroll'
    when 'sequences.manage' then 'sequences.manage'
    when 'sequences.read' then 'sequences.read'
    when 'service-accounts.manage' then 'service_accounts.manage'
    when 'service-accounts.read' then 'service_accounts.read'
    when 'settings.platform' then 'settings.manage'
    when 'settings.read' then 'settings.read'
    when 'settings.update' then 'settings.update'
    when 'share-links.create' then 'share_links.create'
    when 'share-links.read' then 'share_links.read'
    when 'shifts.manage' then 'shifts.manage'
    when 'shifts.read' then 'shifts.read'
    when 'shifts.request' then 'shifts.request'
    when 'shifts.write' then 'shifts.write'
    when 'shipments.manage' then 'shipments.manage'
    when 'shipments.read' then 'shipments.read'
    when 'signatures.manage' then 'signatures.manage'
    when 'signatures.read' then 'signatures.read'
    when 'signatures.request' then 'signatures.request'
    when 'sla.manage' then 'sla.manage'
    when 'sla.read' then 'sla.read'
    when 'sso.manage' then 'sso.manage'
    when 'subjects.manage' then 'subjects.manage'
    when 'tags.apply' then 'tags.apply'
    when 'tags.manage' then 'tags.manage'
    when 'tags.read' then 'tags.read'
    when 'tasks.manage' then 'tasks.manage'
    when 'tasks.read' then 'tasks.read'
    when 'tasks.write' then 'tasks.write'
    when 'tax.manage' then 'tax.manage'
    when 'tax.read' then 'tax.read'
    when 'teams.manage' then 'teams.manage'
    when 'teams.read' then 'teams.read'
    when 'templates.apply' then 'templates.apply'
    when 'templates.manage' then 'templates.manage'
    when 'templates.read' then 'templates.read'
    when 'tills.manage' then 'tills.manage'
    when 'tills.read' then 'tills.read'
    when 'tills.write' then 'tills.write'
    when 'time-entries.approve' then 'time_entries.approve'
    when 'time-entries.manage' then 'time_entries.manage'
    when 'time-entries.read' then 'time_entries.read'
    when 'time-entries.track' then 'time_entries.track'
    when 'timeline.read' then 'timeline.read'
    when 'trash.create' then 'trash.create'
    when 'trash.manage' then 'trash.manage'
    when 'trash.read' then 'trash.read'
    when 'trash.restore' then 'trash.restore'
    when 'usage.read' then 'usage.read'
    when 'usage.record' then 'usage.record'
    when 'versions.create' then 'versions.create'
    when 'versions.manage' then 'versions.manage'
    when 'versions.read' then 'versions.read'
    when 'versions.restore' then 'versions.restore'
    when 'waitlist.invite' then 'waitlist.invite'
    when 'waitlist.manage' then 'waitlist.manage'
    when 'warehouse.manage' then 'warehouse.manage'
    when 'warehouse.pick' then 'warehouse.pick'
    when 'warehouse.read' then 'warehouse.read'
    when 'webhooks-in.create' then 'webhooks.manage'
    when 'webhooks-in.delete' then 'webhooks.manage'
    when 'webhooks-in.read' then 'webhooks.read'
    when 'webhooks-in.update' then 'webhooks.manage'
    when 'webhooks-out.manage' then 'webhooks.manage'
    when 'webhooks-out.read' then 'webhooks.read'
    when 'workflow-editor.manage' then 'workflow_editor.manage'
    when 'workflow-editor.publish' then 'workflow_editor.publish'
    when 'workflow-editor.read' then 'workflow_editor.read'
    when 'workflow-editor.run' then 'workflow_editor.run'
    when 'workflow-editor.write' then 'workflow_editor.write'
    when 'workflows.manage' then 'workflows.manage'
    when 'workflows.read' then 'workflows.read'
    when 'workflows.run' then 'workflows.run'
  end
$function$;

CREATE OR REPLACE FUNCTION better_supabase.organization_slug_problem (
  value               text,
  except_organization uuid DEFAULT NULL::uuid
)
  RETURNS text
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select case
    when value is null then null
    when length(value) < 2 or length(value) > 48 or value !~ '^[a-z0-9](?:[a-z0-9-]*[a-z0-9])?$' then 'invalid'
    when exists (select 1 from "better_supabase"."reserved_slugs" r where r."slug" = lower(value)) then 'reserved'
    when exists (
      select 1 from "public"."organizations" o
      where lower(o."slug"::text) = lower(value)
        and o."id" is distinct from except_organization
    ) then 'taken'
  end
$function$;

CREATE OR REPLACE FUNCTION better_supabase.poll_ssf_events (
  stream_id  uuid,
  max_events integer,
  ack        text[]  DEFAULT '{}'::text[],
  errors     jsonb   DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."ssf_streams";
  v_limit integer := least(greatest(coalesce(poll_ssf_events.max_events, 100), 0), 1000);
  v_sets jsonb;
  v_more boolean;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role manages shared signals streams' using errcode = '42501', hint = 'SSF_FORBIDDEN';
  end if;
  select * into v_row from "better_supabase"."ssf_streams" s where s."id" = poll_ssf_events.stream_id;
  if not found then
    raise exception 'stream not found' using errcode = 'P0002', hint = 'SSF_STREAM_NOT_FOUND';
  end if;
  if v_row."delivery_method" <> 'urn:ietf:rfc:8936' then
    raise exception 'the stream is not delivered by polling' using errcode = '22023', hint = 'SSF_STREAM_NOT_POLL';
  end if;
  delete from "better_supabase"."ssf_events" q
  where q."stream_id" = v_row."id"
    and (q."jti" = any (coalesce(poll_ssf_events.ack, '{}'))
      or coalesce(poll_ssf_events.errors, '{}'::jsonb) ? q."jti");
  if v_row."status" <> 'enabled' or v_limit = 0 then
    return jsonb_build_object('sets', '{}'::jsonb, 'moreAvailable', false);
  end if;
  select count(*) > v_limit into v_more
  from (select 1 from "better_supabase"."ssf_events" q where q."stream_id" = v_row."id" limit v_limit + 1) x;
  select coalesce(jsonb_object_agg(l.jti, l.token), '{}'::jsonb) into v_sets
  from (
    select q."jti" as jti, q."token" as token from "better_supabase"."ssf_events" q
    where q."stream_id" = v_row."id"
    order by q."created_at", q."jti"
    limit v_limit
  ) l;
  return jsonb_build_object('sets', v_sets, 'moreAvailable', v_more);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.purge_idempotency_keys()
  RETURNS integer
  LANGUAGE sql
  SET search_path TO ''
  AS $function$
  with purged as (
    delete from "better_supabase"."idempotency_keys" k where k."expires_at" < now() returning 1
  )
  select count(*)::integer from purged
$function$;

CREATE OR REPLACE FUNCTION better_supabase.purge_shared_signals (
  older_than interval DEFAULT NULL::interval
)
  RETURNS integer
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_cutoff timestamptz := now() - coalesce(purge_shared_signals.older_than, '7 days'::interval);
  v_received integer;
  v_events integer;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role manages shared signals streams' using errcode = '42501', hint = 'SSF_FORBIDDEN';
  end if;
  delete from "better_supabase"."ssf_received" x where x."received_at" < v_cutoff;
  get diagnostics v_received = row_count;
  delete from "better_supabase"."ssf_events" q where q."created_at" < v_cutoff;
  get diagnostics v_events = row_count;
  return v_received + v_events;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.purge_webhooks (
  older_than   interval DEFAULT '30 days'::interval,
  include_dead boolean  DEFAULT false,
  batch        integer  DEFAULT 10000,
  for_tenant   text     DEFAULT NULL::text
)
  RETURNS integer
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
declare
  v_purged integer;
begin
  with purged as (
    delete from better_supabase.webhook_inbox
    where id in (
      select w.id from better_supabase.webhook_inbox w
      where ((w.status = 'processed' and (w.processed_at < now() - least(older_than, "better_supabase"."retention_floor"('webhooks'))
      and w.processed_at < now() - coalesce("better_supabase"."retention_for_memo"('webhooks', (w.tenant)::text), older_than)
      and not "better_supabase"."is_held_memo"('webhooks', (w.tenant)::text)))
        or (include_dead and w.status = 'dead' and (w.received_at < now() - least(older_than, "better_supabase"."retention_floor"('webhooks'))
      and w.received_at < now() - coalesce("better_supabase"."retention_for_memo"('webhooks', (w.tenant)::text), older_than)
      and not "better_supabase"."is_held_memo"('webhooks', (w.tenant)::text))))
        and (for_tenant is null or w.tenant = for_tenant)
      order by w.id
      limit batch
    )
    returning 1
  )
  select count(*)::integer into v_purged from purged;
  return v_purged;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.queue_ssf_set (
  stream_id uuid,
  jti       text,
  token     text
)
  RETURNS text
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."ssf_streams";
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role manages shared signals streams' using errcode = '42501', hint = 'SSF_FORBIDDEN';
  end if;
  select * into v_row from "better_supabase"."ssf_streams" s where s."id" = queue_ssf_set.stream_id for update;
  if not found then
    raise exception 'stream not found' using errcode = 'P0002', hint = 'SSF_STREAM_NOT_FOUND';
  end if;
  if v_row."status" = 'disabled' then
    return 'dropped';
  end if;
  if v_row."delivery_method" = 'urn:ietf:rfc:8935' and v_row."status" = 'enabled' and exists (select 1 from "better_supabase"."webhook_endpoints" we where we."id" = v_row."endpoint_id" and we."enabled") then
    perform "better_supabase"."dispatch_webhook"(v_row."endpoint_id", 'ssf.set', jsonb_build_object('set', queue_ssf_set.token), null, queue_ssf_set.jti);
    return 'dispatched';
  end if;
  insert into "better_supabase"."ssf_events" ("stream_id", "jti", "token")
  values (v_row."id", queue_ssf_set.jti, queue_ssf_set.token)
  on conflict do nothing;
  return case when v_row."delivery_method" = 'urn:ietf:rfc:8936' and v_row."status" = 'enabled' then 'queued' else 'held' end;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.rank_option_set_item (
  item uuid,
  rank text
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_tenant uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id" into v_tenant from "better_supabase"."option_set_items" x where x."id" = rank_option_set_item.item;
  if v_tenant is null then
    return false;
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'option_sets.manage'), false)) then
    raise exception 'not allowed to manage option sets' using errcode = '42501', hint = 'OPTION_SET_FORBIDDEN';
  end if;
  if rank_option_set_item.rank is null or rank_option_set_item.rank !~ '^[0-9A-Za-z]*[1-9A-Za-z]$' then
    raise exception 'not a rank key' using errcode = '22023', hint = 'OPTION_SET_RANK_INVALID';
  end if;
  update "better_supabase"."option_set_items" x set "rank" = rank_option_set_item.rank, "updated_at" = now()
  where x."id" = rank_option_set_item.item;
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.receive_webhook (
  source       text,
  message_id   text,
  event_type   text,
  payload      jsonb,
  headers      jsonb   DEFAULT '{}'::jsonb,
  tenant       text    DEFAULT NULL::text,
  max_attempts integer DEFAULT NULL::integer
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  inbox_id bigint;
begin
  insert into better_supabase.webhook_inbox (source, message_id, event_type, payload, headers, tenant, max_attempts)
  values (source, message_id, event_type, payload, headers, receive_webhook.tenant, greatest(coalesce(receive_webhook.max_attempts, 8), 1))
  on conflict on constraint webhook_inbox_source_tenant_message_id_key do nothing
  returning webhook_inbox.id into inbox_id;
  if inbox_id is not null then
    return jsonb_build_object('id', inbox_id, 'duplicate', false);
  end if;
  select w.id into inbox_id from better_supabase.webhook_inbox w
  where w.source = receive_webhook.source
    and w.tenant is not distinct from receive_webhook.tenant
    and w.message_id = receive_webhook.message_id;
  return jsonb_build_object('id', inbox_id, 'duplicate', true);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.record_incoming_webhook (
  endpoint uuid,
  status   integer
)
  RETURNS void
  LANGUAGE sql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  update "better_supabase"."incoming_webhooks" e
  set "receive_count" = e."receive_count" + 1, "last_received_at" = now(), "last_status" = record_incoming_webhook.status
  where e."id" = endpoint
$function$;

CREATE OR REPLACE FUNCTION better_supabase.record_ssf_received (
  issuer text,
  jti    text
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_new boolean;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role manages shared signals streams' using errcode = '42501', hint = 'SSF_FORBIDDEN';
  end if;
  insert into "better_supabase"."ssf_received" ("issuer", "jti")
  values (record_ssf_received.issuer, record_ssf_received.jti)
  on conflict do nothing
  returning true into v_new;
  return coalesce(v_new, false);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.release_idempotent (
  scope  text,
  key    text,
  holder uuid
)
  RETURNS boolean
  LANGUAGE sql
  SET search_path TO ''
  AS $function$
  with released as (
    delete from "better_supabase"."idempotency_keys" k
    where k."scope" = release_idempotent.scope and k."key" = release_idempotent.key
      and k."status" = 'running' and k."holder" = release_idempotent.holder
    returning 1
  )
  select exists (select 1 from released)
$function$;

CREATE OR REPLACE FUNCTION better_supabase.release_lease (
  key    text,
  holder uuid,
  scope  text DEFAULT ''::text
)
  RETURNS boolean
  LANGUAGE sql
  SET search_path TO ''
  AS $function$
  with released as (
    delete from "better_supabase"."idempotency_leases" l
    where l."scope" = release_lease.scope and l."key" = release_lease.key and l."holder" = release_lease.holder
    returning 1
  )
  select exists (select 1 from released)
$function$;

CREATE OR REPLACE FUNCTION better_supabase.remove_hostname (
  id uuid
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."hostnames";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."hostnames" x where x."id" = remove_hostname.id;
  if v_row."id" is null or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'domains.manage'), false)) then
    return false;
  end if;
  delete from "better_supabase"."hostnames" x where x."id" = v_row."id";
  perform "better_supabase".emit_event('hostname.deleted', jsonb_build_object('organizationId', v_row."tenant_id"::text, 'hostnameId', v_row."id"::text, 'hostname', v_row."hostname"), 'hostnames/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/domains');
  perform better_supabase.audit_event(
    event_type => 'hostname.deleted',
    category => 'configuration',
    target_type => 'hostname',
    record_id => v_row."id"::text,
    target_label => v_row."hostname",
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id"::text, 'hostnameId', v_row."id"::text, 'hostname', v_row."hostname"),
    actor_id => auth.uid()
  );
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.resolve_hostname (
  hostname text
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select jsonb_build_object(
    'organizationId', x."tenant_id",
    'hostname', x."hostname",
    'primary', x."is_primary",
    'primaryHostname', (
      select p."hostname" from "better_supabase"."hostnames" p
      where p."tenant_id" = x."tenant_id" and p."is_primary"
    )
  )
  from "better_supabase"."hostnames" x
  where x."hostname" = lower(trim(trailing '.' from trim(resolve_hostname.hostname)))
    and x."verified_at" is not null
$function$;

CREATE OR REPLACE FUNCTION better_supabase.rotate_incoming_webhook (
  endpoint      uuid,
  rotate_secret boolean DEFAULT false
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  token text := encode(extensions.gen_random_bytes(24), 'hex');
  v_secret text;
  updated "better_supabase"."incoming_webhooks";
  previous "better_supabase"."incoming_webhooks";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into previous from "better_supabase"."incoming_webhooks" e where e."id" = endpoint for update;
  if previous."id" is null or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.member_can(auth.uid(), previous."tenant", 'webhooks.manage'), false)) then
    raise exception 'No incoming webhook %', endpoint using errcode = 'P0002', hint = 'WEBHOOK_IN_NOT_FOUND';
  end if;
  if rotate_secret then
    v_secret := case previous."verify"
    when 'standard-webhooks' then 'whsec_' || encode(extensions.gen_random_bytes(32), 'base64')
    when 'hmac-sha256' then encode(extensions.gen_random_bytes(32), 'hex')
    when 'shared-secret' then encode(extensions.gen_random_bytes(32), 'hex')
  end;
  end if;
  update "better_supabase"."incoming_webhooks" e set "token_hash" = encode(extensions.digest(token, 'sha256'), 'hex'),
    "secret" = case when rotate_secret then null else e."secret" end,
    "secret_id" = case when rotate_secret then case when v_secret is null then null else vault.create_secret(v_secret, 'webhook-in:' || e."id"::text || ':' || gen_random_uuid()::text, 'better-supabase incoming webhook secret') end else e."secret_id" end,
    "previous_secret" = case when rotate_secret then null else e."previous_secret" end,
    "previous_secret_id" = case when rotate_secret then null else e."previous_secret_id" end,
    "previous_secret_expires_at" = case when rotate_secret then null else e."previous_secret_expires_at" end
  where e."id" = endpoint
  returning * into updated;
  if rotate_secret then
    delete from vault.secrets vs where vs.id in (previous."secret_id", previous."previous_secret_id");
  end if;
  perform "better_supabase".emit_event('incoming_webhook.token_rotated', jsonb_build_object('organizationId', updated."tenant"::text, 'endpointId', updated."id", 'secretRotated', rotate_secret), 'organizations/' || updated."tenant"::text || '/incoming-webhooks/' || updated."id"::text, (updated."tenant")::text, null, 'better-supabase/webhooks-in');
  perform better_supabase.audit_event(
    event_type => 'incoming_webhook.token_rotated',
    category => 'security',
    target_type => 'incoming_webhook',
    record_id => updated."id"::text,
    tenant => (updated."tenant")::uuid,
    metadata => jsonb_build_object('organizationId', updated."tenant"::text, 'endpointId', updated."id", 'secretRotated', rotate_secret)
  );
  return jsonb_build_object('id', updated."id", 'token', token, 'secret', v_secret);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.rotate_incoming_webhook_secret (
  endpoint uuid,
  grace    interval DEFAULT NULL::interval
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  previous "better_supabase"."incoming_webhooks";
  updated "better_supabase"."incoming_webhooks";
  v_secret text;
  v_keep boolean := coalesce(grace > interval '0', false);
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into previous from "better_supabase"."incoming_webhooks" e where e."id" = endpoint for update;
  if previous."id" is null or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.member_can(auth.uid(), previous."tenant", 'webhooks.manage'), false)) then
    raise exception 'No incoming webhook %', endpoint using errcode = 'P0002', hint = 'WEBHOOK_IN_NOT_FOUND';
  end if;
  v_secret := case previous."verify"
    when 'standard-webhooks' then 'whsec_' || encode(extensions.gen_random_bytes(32), 'base64')
    when 'hmac-sha256' then encode(extensions.gen_random_bytes(32), 'hex')
    when 'shared-secret' then encode(extensions.gen_random_bytes(32), 'hex')
  end;
  if v_secret is null then
    raise exception 'This endpoint verifies no secret' using errcode = '22023', hint = 'WEBHOOK_IN_NO_SECRET';
  end if;
  update "better_supabase"."incoming_webhooks" e set
    "secret" = null,
    "secret_id" = case when v_secret is null then null else vault.create_secret(v_secret, 'webhook-in:' || e."id"::text || ':' || gen_random_uuid()::text, 'better-supabase incoming webhook secret') end,
    "previous_secret" = case when v_keep then e."secret" end,
    "previous_secret_id" = case when v_keep then e."secret_id" end,
    "previous_secret_expires_at" = case when v_keep then now() + grace end
  where e."id" = endpoint
  returning * into updated;
  delete from vault.secrets vs
  where vs.id = previous."previous_secret_id" or (not v_keep and vs.id = previous."secret_id");
  perform "better_supabase".emit_event('incoming_webhook.secret_rotated', jsonb_build_object('organizationId', updated."tenant"::text, 'endpointId', updated."id"), 'organizations/' || updated."tenant"::text || '/incoming-webhooks/' || updated."id"::text, (updated."tenant")::text, null, 'better-supabase/webhooks-in');
  perform better_supabase.audit_event(
    event_type => 'incoming_webhook.secret_rotated',
    category => 'security',
    target_type => 'incoming_webhook',
    record_id => updated."id"::text,
    tenant => (updated."tenant")::uuid,
    metadata => jsonb_build_object('organizationId', updated."tenant"::text, 'endpointId', updated."id")
  );
  return jsonb_build_object('id', updated."id", 'secret', v_secret, 'previousSecretExpiresAt', updated."previous_secret_expires_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.save_option_set (
  tenant       uuid,
  option_set   uuid,
  subject_type text,
  field        text,
  key          text,
  name         text,
  scope_id     text    DEFAULT NULL::text,
  is_default   boolean DEFAULT false
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_set uuid := save_option_set.option_set;
  v_tenant uuid := save_option_set.tenant;
  v_type text := save_option_set.subject_type;
  v_field text := save_option_set.field;
  v_created boolean := save_option_set.option_set is null;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', save_option_set.tenant, 'option_sets.manage'), false)) then
    raise exception 'not allowed to manage option sets' using errcode = '42501', hint = 'OPTION_SET_FORBIDDEN';
  end if;
  if not (save_option_set.subject_type || '.' || save_option_set.field = any ('{work_item.priority}'::text[])) then
    raise exception 'this field has no option set binding' using errcode = '22023', hint = 'OPTION_SET_FIELD_UNKNOWN';
  end if;
  if coalesce(save_option_set.is_default, false) then
    update "better_supabase"."option_sets" x set "is_default" = false
    where x."tenant_id" = save_option_set.tenant and x."subject_type" = save_option_set.subject_type
      and x."field" = save_option_set.field
      and x."scope_id" is not distinct from save_option_set.scope_id and x."is_default"
      and x."id" is distinct from save_option_set.option_set;
  end if;
  begin
    if v_created then
      insert into "better_supabase"."option_sets" ("tenant_id", "subject_type", "field", "scope_id", "key", "name", "is_default")
      values (save_option_set.tenant, save_option_set.subject_type, save_option_set.field, save_option_set.scope_id, save_option_set.key, save_option_set.name,
        coalesce(save_option_set.is_default, false) or not exists (
          select 1 from "better_supabase"."option_sets" x where x."tenant_id" = save_option_set.tenant and x."subject_type" = save_option_set.subject_type
            and x."field" = save_option_set.field
            and x."scope_id" is not distinct from save_option_set.scope_id and x."archived_at" is null))
      returning "id" into v_set;
    else
      update "better_supabase"."option_sets" x set "key" = save_option_set.key, "name" = save_option_set.name,
        "is_default" = coalesce(save_option_set.is_default, x."is_default"), "updated_at" = now()
      where x."id" = save_option_set.option_set and x."tenant_id" = save_option_set.tenant
        and x."subject_type" = save_option_set.subject_type and x."field" = save_option_set.field;
      if not found then
        raise exception 'option set not found' using errcode = 'P0002', hint = 'OPTION_SET_NOT_FOUND';
      end if;
    end if;
  exception when unique_violation then
    raise exception 'another option set of this field has this key' using errcode = '23505', hint = 'OPTION_SET_KEY_TAKEN';
  end;
  if v_created then
    perform "better_supabase".emit_event('option_set.created', jsonb_build_object('organizationId', v_tenant, 'optionSetId', v_set, 'subjectType', v_type, 'field', v_field, 'key', save_option_set.key), 'option-sets/' || v_set::text, (v_tenant::text)::text, null, 'better-supabase/option-sets');
  perform better_supabase.audit_event(
    event_type => 'option_set.created',
    category => 'configuration',
    target_type => 'option_set',
    record_id => v_set::text,
    summary => 'created option set ' || save_option_set.name,
    tenant => (v_tenant::text)::uuid,
    metadata => jsonb_build_object('organizationId', v_tenant, 'optionSetId', v_set, 'subjectType', v_type, 'field', v_field, 'key', save_option_set.key)
  );
  else
    perform "better_supabase".emit_event('option_set.updated', jsonb_build_object('organizationId', v_tenant, 'optionSetId', v_set, 'subjectType', v_type, 'field', v_field, 'key', save_option_set.key), 'option-sets/' || v_set::text, (v_tenant::text)::text, null, 'better-supabase/option-sets');
  perform better_supabase.audit_event(
    event_type => 'option_set.updated',
    category => 'configuration',
    target_type => 'option_set',
    record_id => v_set::text,
    summary => 'updated option set ' || save_option_set.name,
    tenant => (v_tenant::text)::uuid,
    metadata => jsonb_build_object('organizationId', v_tenant, 'optionSetId', v_set, 'subjectType', v_type, 'field', v_field, 'key', save_option_set.key)
  );
  end if;
  return (select to_jsonb(y) || jsonb_build_object('items', coalesce((
      select jsonb_agg(to_jsonb(z) order by z."rank" collate "C", z."id")
      from "better_supabase"."option_set_items" z
      where z."option_set_id" = y."id" and (false or z."archived_at" is null)
    ), '[]'::jsonb)) from "better_supabase"."option_sets" y where y."id" = v_set);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.save_option_set_item (
  option_set  uuid,
  item        uuid,
  key         text,
  label       text,
  level       integer,
  color       text    DEFAULT NULL::text,
  icon        text    DEFAULT NULL::text,
  description text    DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_tenant uuid;
  v_type text;
  v_field text;
  v_min integer;
  v_max integer;
  v_set uuid := save_option_set_item.option_set;
  v_item uuid := save_option_set_item.item;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id", x."subject_type", x."field" into v_tenant, v_type, v_field
  from "better_supabase"."option_sets" x where x."id" = save_option_set_item.option_set and x."archived_at" is null;
  if v_tenant is null then
    raise exception 'option set not found' using errcode = 'P0002', hint = 'OPTION_SET_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'option_sets.manage'), false)) then
    raise exception 'not allowed to manage option sets' using errcode = '42501', hint = 'OPTION_SET_FORBIDDEN';
  end if;
      if v_type = 'work_item' and v_field = 'priority' then
      v_min := 0;
      v_max := 4;
    else
      raise exception 'this field has no option set binding' using errcode = '22023', hint = 'OPTION_SET_FIELD_UNKNOWN';
    end if;
  if save_option_set_item.level is null or save_option_set_item.level < v_min or save_option_set_item.level > v_max then
    raise exception 'the level is outside the bounds of this field' using errcode = '22023', hint = 'OPTION_SET_LEVEL_INVALID';
  end if;
  begin
    if v_item is null then
      insert into "better_supabase"."option_set_items" ("tenant_id", "option_set_id", "key", "label", "level", "color", "icon", "description", "rank")
      values (v_tenant, save_option_set_item.option_set, save_option_set_item.key, save_option_set_item.label, save_option_set_item.level,
        save_option_set_item.color, save_option_set_item.icon, save_option_set_item.description,
        case
    when (select max(x."rank" collate "C") from "better_supabase"."option_set_items" x where x."option_set_id" = save_option_set_item.option_set) is null then 'V'
    when length(substring((select max(x."rank" collate "C") from "better_supabase"."option_set_items" x where x."option_set_id" = save_option_set_item.option_set) from '^z*')) = length((select max(x."rank" collate "C") from "better_supabase"."option_set_items" x where x."option_set_id" = save_option_set_item.option_set)) then (select max(x."rank" collate "C") from "better_supabase"."option_set_items" x where x."option_set_id" = save_option_set_item.option_set) || 'V'
    else left((select max(x."rank" collate "C") from "better_supabase"."option_set_items" x where x."option_set_id" = save_option_set_item.option_set), length(substring((select max(x."rank" collate "C") from "better_supabase"."option_set_items" x where x."option_set_id" = save_option_set_item.option_set) from '^z*'))) || substr('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', (strpos('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', substr((select max(x."rank" collate "C") from "better_supabase"."option_set_items" x where x."option_set_id" = save_option_set_item.option_set), length(substring((select max(x."rank" collate "C") from "better_supabase"."option_set_items" x where x."option_set_id" = save_option_set_item.option_set) from '^z*')) + 1, 1)) - 1 + 62) / 2 + 1, 1)
  end)
      returning "id" into v_item;
    else
      update "better_supabase"."option_set_items" x set "key" = save_option_set_item.key, "label" = save_option_set_item.label,
        "level" = save_option_set_item.level, "color" = save_option_set_item.color, "icon" = save_option_set_item.icon,
        "description" = save_option_set_item.description, "updated_at" = now()
      where x."id" = v_item and x."option_set_id" = save_option_set_item.option_set;
      if not found then
        raise exception 'item not found' using errcode = 'P0002', hint = 'OPTION_SET_ITEM_NOT_FOUND';
      end if;
          if v_type = 'work_item' and v_field = 'priority' then
      update "better_supabase"."work_items" r set "priority" = save_option_set_item.level
      where r."priority_option_id" = v_item;
    else
      null;
    end if;
    end if;
  exception when unique_violation then
    raise exception 'another item of this set has this key' using errcode = '23505', hint = 'OPTION_SET_ITEM_KEY_TAKEN';
  end;
  if save_option_set_item.item is null then
    perform "better_supabase".emit_event('option_set_item.created', jsonb_build_object('organizationId', v_tenant, 'optionSetId', v_set, 'itemId', v_item, 'key', save_option_set_item.key, 'level', save_option_set_item.level), 'option-sets/' || v_set::text, (v_tenant::text)::text, null, 'better-supabase/option-sets');
  perform better_supabase.audit_event(
    event_type => 'option_set_item.created',
    category => 'configuration',
    target_type => 'option_set_item',
    record_id => v_item::text,
    summary => 'created option set item ' || save_option_set_item.label,
    tenant => (v_tenant::text)::uuid,
    metadata => jsonb_build_object('organizationId', v_tenant, 'optionSetId', v_set, 'itemId', v_item, 'key', save_option_set_item.key, 'level', save_option_set_item.level)
  );
  else
    perform "better_supabase".emit_event('option_set_item.updated', jsonb_build_object('organizationId', v_tenant, 'optionSetId', v_set, 'itemId', v_item, 'key', save_option_set_item.key, 'level', save_option_set_item.level), 'option-sets/' || v_set::text, (v_tenant::text)::text, null, 'better-supabase/option-sets');
  perform better_supabase.audit_event(
    event_type => 'option_set_item.updated',
    category => 'configuration',
    target_type => 'option_set_item',
    record_id => v_item::text,
    summary => 'updated option set item ' || save_option_set_item.label,
    tenant => (v_tenant::text)::uuid,
    metadata => jsonb_build_object('organizationId', v_tenant, 'optionSetId', v_set, 'itemId', v_item, 'key', save_option_set_item.key, 'level', save_option_set_item.level)
  );
  end if;
  return (select to_jsonb(x) from "better_supabase"."option_set_items" x where x."id" = v_item);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.set_incoming_webhook_enabled (
  endpoint uuid,
  enabled  boolean
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  tenant uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select e."tenant" into tenant from "better_supabase"."incoming_webhooks" e where e."id" = endpoint;
  if tenant is null or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.member_can(auth.uid(), tenant, 'webhooks.manage'), false)) then
    return false;
  end if;
  update "better_supabase"."incoming_webhooks" e set "enabled" = set_incoming_webhook_enabled.enabled where e."id" = endpoint;
  perform "better_supabase".emit_event('incoming_webhook.enabled_changed', jsonb_build_object('organizationId', tenant::text, 'endpointId', endpoint, 'enabled', set_incoming_webhook_enabled.enabled), 'organizations/' || tenant::text || '/incoming-webhooks/' || endpoint::text, (tenant)::text, null, 'better-supabase/webhooks-in');
  perform better_supabase.audit_event(
    event_type => 'incoming_webhook.enabled_changed',
    category => 'integration',
    target_type => 'incoming_webhook',
    record_id => endpoint::text,
    tenant => (tenant)::uuid,
    metadata => jsonb_build_object('organizationId', tenant::text, 'endpointId', endpoint, 'enabled', set_incoming_webhook_enabled.enabled)
  );
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.set_primary_hostname (
  id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."hostnames";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."hostnames" x where x."id" = set_primary_hostname.id for update;
  if v_row."id" is null or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'domains.manage'), false)) then
    raise exception 'No hostname you manage has this id' using errcode = 'P0002', hint = 'HOSTNAME_NOT_FOUND';
  end if;
  if v_row."verified_at" is null then
    raise exception 'Verify the hostname first' using errcode = '22023', hint = 'HOSTNAME_NOT_VERIFIED';
  end if;
  if v_row."is_primary" then
    return (to_jsonb(v_row) - 'verification_token') || case when v_row."verified_at" is null then jsonb_build_object('record', jsonb_build_object('type', 'TXT', 'name', '_better-supabase.' || v_row."hostname", 'value', 'better-supabase-hostname-verification=' || v_row."verification_token")) else '{}'::jsonb end;
  end if;
  update "better_supabase"."hostnames" x set "is_primary" = false where x."tenant_id" = v_row."tenant_id" and x."is_primary";
  update "better_supabase"."hostnames" x set "is_primary" = true where x."id" = v_row."id" returning * into v_row;
  perform "better_supabase".emit_event('hostname.primary_changed', jsonb_build_object('organizationId', v_row."tenant_id"::text, 'hostnameId', v_row."id"::text, 'hostname', v_row."hostname"), 'hostnames/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/domains');
  perform better_supabase.audit_event(
    event_type => 'hostname.primary_changed',
    category => 'configuration',
    target_type => 'hostname',
    record_id => v_row."id"::text,
    target_label => v_row."hostname",
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id"::text, 'hostnameId', v_row."id"::text, 'hostname', v_row."hostname"),
    actor_id => auth.uid()
  );
  return (to_jsonb(v_row) - 'verification_token') || case when v_row."verified_at" is null then jsonb_build_object('record', jsonb_build_object('type', 'TXT', 'name', '_better-supabase.' || v_row."hostname", 'value', 'better-supabase-hostname-verification=' || v_row."verification_token")) else '{}'::jsonb end;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.set_ssf_stream_status (
  id     uuid,
  status text,
  reason text DEFAULT NULL::text
)
  RETURNS text
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."ssf_streams";
  v_previous text;
  v_held record;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role manages shared signals streams' using errcode = '42501', hint = 'SSF_FORBIDDEN';
  end if;
  if set_ssf_stream_status.status not in ('enabled', 'paused', 'disabled') then
    raise exception 'status is enabled, paused or disabled' using errcode = '22023', hint = 'SSF_STATUS_INVALID';
  end if;
  select s."status" into v_previous from "better_supabase"."ssf_streams" s where s."id" = set_ssf_stream_status.id for update;
  if not found then
    raise exception 'stream not found' using errcode = 'P0002', hint = 'SSF_STREAM_NOT_FOUND';
  end if;
  update "better_supabase"."ssf_streams" s set "status" = set_ssf_stream_status.status, "reason" = set_ssf_stream_status.reason
  where s."id" = set_ssf_stream_status.id
  returning s.* into v_row;
  if v_row."status" = 'disabled' then
    delete from "better_supabase"."ssf_events" q where q."stream_id" = v_row."id";
  elsif v_row."status" = 'enabled' and v_row."delivery_method" = 'urn:ietf:rfc:8935' and exists (select 1 from "better_supabase"."webhook_endpoints" we where we."id" = v_row."endpoint_id" and we."enabled") then
    for v_held in
      select q."jti" as jti, q."token" as token from "better_supabase"."ssf_events" q
      where q."stream_id" = v_row."id" order by q."created_at"
    loop
      perform "better_supabase"."dispatch_webhook"(v_row."endpoint_id", 'ssf.set', jsonb_build_object('set', v_held.token), null, v_held.jti);
    end loop;
    delete from "better_supabase"."ssf_events" q where q."stream_id" = v_row."id";
  end if;
  if v_previous is distinct from v_row."status" then
    perform "better_supabase".emit_event('ssf_stream.status_changed', jsonb_build_object('streamId', v_row."id", 'receiver', v_row."receiver", 'tenant', v_row."tenant", 'status', v_row."status", 'reason', v_row."reason"), 'shared-signals/' || v_row."id", null, null, 'better-supabase/security-events');
  perform better_supabase.audit_event(
    event_type => 'ssf_stream.status_changed',
    category => 'security',
    target_type => 'ssf_stream',
    record_id => v_row."id"::text,
    metadata => jsonb_build_object('streamId', v_row."id", 'receiver', v_row."receiver", 'tenant', v_row."tenant", 'status', v_row."status", 'reason', v_row."reason")
  );
  end if;
  return v_previous;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.slug_problem (
  slug text
)
  RETURNS text
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select case
    when slug is null then null
    when slug !~ '^[a-z0-9](?:[a-z0-9-]*[a-z0-9])?$' then 'invalid'
    when slug ~ '--' then 'invalid'
    when length(slug) < 1 or length(slug) > 63 then 'invalid'
    when exists (select 1 from "better_supabase"."reserved_slugs" r where r."slug" = slug_problem.slug) then 'reserved'
  end
$function$;

CREATE OR REPLACE FUNCTION better_supabase.ssf_stream (
  id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role manages shared signals streams' using errcode = '42501', hint = 'SSF_FORBIDDEN';
  end if;
  return (select jsonb_build_object(
    'id', s."id",
    'tenant', s."tenant",
    'receiver', s."receiver",
    'audience', to_jsonb(s."audience"),
    'description', s."description",
    'eventsRequested', to_jsonb(s."events_requested"),
    'eventsDelivered', to_jsonb(s."events_delivered"),
    'method', s."delivery_method",
    'endpointUrl', (select we."url" from "better_supabase"."webhook_endpoints" we where we."id" = s."endpoint_id"),
    'status', s."status",
    'reason', s."reason",
    'createdAt', s."created_at",
    'updatedAt', s."updated_at"
  ) from "better_supabase"."ssf_streams" s where s."id" = ssf_stream.id);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.ssf_streams (
  receiver text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role manages shared signals streams' using errcode = '42501', hint = 'SSF_FORBIDDEN';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
    'id', s."id",
    'tenant', s."tenant",
    'receiver', s."receiver",
    'audience', to_jsonb(s."audience"),
    'description', s."description",
    'eventsRequested', to_jsonb(s."events_requested"),
    'eventsDelivered', to_jsonb(s."events_delivered"),
    'method', s."delivery_method",
    'endpointUrl', (select we."url" from "better_supabase"."webhook_endpoints" we where we."id" = s."endpoint_id"),
    'status', s."status",
    'reason', s."reason",
    'createdAt', s."created_at",
    'updatedAt', s."updated_at"
  ) order by s."created_at")
    from "better_supabase"."ssf_streams" s where s."receiver" = ssf_streams.receiver
  ), '[]'::jsonb);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.ssf_streams_for_event (
  tenant     text,
  event_type text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role manages shared signals streams' using errcode = '42501', hint = 'SSF_FORBIDDEN';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', s."id", 'audience', to_jsonb(s."audience")) order by s."created_at")
    from "better_supabase"."ssf_streams" s
    where s."status" <> 'disabled'
      and ssf_streams_for_event.event_type = any (s."events_delivered")
      and (s."tenant" is null or s."tenant" = ssf_streams_for_event.tenant)
  ), '[]'::jsonb);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.track_slug (
  target      regclass,
  column_name text     DEFAULT 'slug'::text
)
  RETURNS void
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
begin
  execute format('drop trigger if exists bsb_slug on %s', target);
  execute format(
    'create trigger bsb_slug before insert or update of %I on %s for each row execute function better_supabase.enforce_slug(%L)',
    column_name,
    target,
    column_name
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.update_incoming_webhook (
  endpoint         uuid,
  name             text  DEFAULT NULL::text,
  metadata         jsonb DEFAULT NULL::jsonb,
  verify           text  DEFAULT NULL::text,
  signature_header text  DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  previous "better_supabase"."incoming_webhooks";
  updated "better_supabase"."incoming_webhooks";
  v_verify text;
  v_secret text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into previous from "better_supabase"."incoming_webhooks" e where e."id" = endpoint for update;
  if previous."id" is null or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.member_can(auth.uid(), previous."tenant", 'webhooks.manage'), false)) then
    raise exception 'No incoming webhook %', endpoint using errcode = 'P0002', hint = 'WEBHOOK_IN_NOT_FOUND';
  end if;
  if name is not null and btrim(name) = '' then
    raise exception 'An endpoint needs a name' using errcode = '22023', hint = 'WEBHOOK_IN_NAME_REQUIRED';
  end if;
  if metadata is not null and jsonb_typeof(metadata) <> 'object' then
    raise exception 'metadata must be a JSON object' using errcode = '22023', hint = 'WEBHOOK_IN_METADATA_INVALID';
  end if;
  v_verify := coalesce(verify, previous."verify");
  if v_verify not in ('none', 'standard-webhooks', 'hmac-sha256', 'shared-secret') then
    raise exception 'Unknown verification mode' using errcode = '22023', hint = 'WEBHOOK_IN_VERIFY_UNKNOWN';
  end if;
  if v_verify <> previous."verify" then
    v_secret := case v_verify
    when 'standard-webhooks' then 'whsec_' || encode(extensions.gen_random_bytes(32), 'base64')
    when 'hmac-sha256' then encode(extensions.gen_random_bytes(32), 'hex')
    when 'shared-secret' then encode(extensions.gen_random_bytes(32), 'hex')
  end;
  end if;
  update "better_supabase"."incoming_webhooks" e set
    "name" = coalesce(update_incoming_webhook.name, e."name"),
    "metadata" = coalesce(update_incoming_webhook.metadata, e."metadata"),
    "verify" = v_verify,
    "secret" = case when v_verify = previous."verify" then e."secret" else null end,
    "secret_id" = case when v_verify = previous."verify" then e."secret_id" else case when v_secret is null then null else vault.create_secret(v_secret, 'webhook-in:' || e."id"::text || ':' || gen_random_uuid()::text, 'better-supabase incoming webhook secret') end end,
    "previous_secret" = case when v_verify = previous."verify" then e."previous_secret" end,
    "previous_secret_id" = case when v_verify = previous."verify" then e."previous_secret_id" end,
    "previous_secret_expires_at" = case when v_verify = previous."verify" then e."previous_secret_expires_at" end,
    "signature_header" = case v_verify
      when 'hmac-sha256' then coalesce(update_incoming_webhook.signature_header, case when v_verify = previous."verify" then e."signature_header" end, 'x-signature')
      when 'shared-secret' then coalesce(update_incoming_webhook.signature_header, case when v_verify = previous."verify" then e."signature_header" end, 'x-webhook-secret')
    end
  where e."id" = endpoint
  returning * into updated;
  if v_verify <> previous."verify" then
    delete from vault.secrets vs where vs.id in (previous."secret_id", previous."previous_secret_id");
  end if;
  perform "better_supabase".emit_event('incoming_webhook.updated', jsonb_build_object('organizationId', updated."tenant"::text, 'endpointId', updated."id", 'name', updated."name", 'verify', updated."verify"), 'organizations/' || updated."tenant"::text || '/incoming-webhooks/' || updated."id"::text, (updated."tenant")::text, null, 'better-supabase/webhooks-in');
  perform better_supabase.audit_event(
    event_type => 'incoming_webhook.updated',
    category => 'integration',
    target_type => 'incoming_webhook',
    record_id => updated."id"::text,
    tenant => (updated."tenant")::uuid,
    metadata => jsonb_build_object('organizationId', updated."tenant"::text, 'endpointId', updated."id", 'name', updated."name", 'verify', updated."verify")
  );
  return jsonb_build_object('id', updated."id", 'tenant', updated."tenant", 'name', updated."name",
    'verify', updated."verify", 'secret', v_secret, 'signatureHeader', updated."signature_header",
    'metadata', updated."metadata");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.update_ssf_stream (
  id    uuid,
  patch jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."ssf_streams";
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role manages shared signals streams' using errcode = '42501', hint = 'SSF_FORBIDDEN';
  end if;
  update "better_supabase"."ssf_streams" s set
    "description" = case when update_ssf_stream.patch ? 'description' then update_ssf_stream.patch ->> 'description' else s."description" end,
    "events_requested" = case when update_ssf_stream.patch ? 'eventsRequested'
      then array(select jsonb_array_elements_text(update_ssf_stream.patch -> 'eventsRequested')) else s."events_requested" end,
    "events_delivered" = case when update_ssf_stream.patch ? 'eventsDelivered'
      then array(select jsonb_array_elements_text(update_ssf_stream.patch -> 'eventsDelivered')) else s."events_delivered" end
  where s."id" = update_ssf_stream.id
  returning s.* into v_row;
  if not found then
    return null;
  end if;
  if update_ssf_stream.patch ? 'endpointUrl' and v_row."endpoint_id" is not null then
    update "better_supabase"."webhook_endpoints" we set "url" = update_ssf_stream.patch ->> 'endpointUrl'
    where we."id" = v_row."endpoint_id";
  end if;
  return jsonb_build_object(
    'id', v_row."id",
    'tenant', v_row."tenant",
    'receiver', v_row."receiver",
    'audience', to_jsonb(v_row."audience"),
    'description', v_row."description",
    'eventsRequested', to_jsonb(v_row."events_requested"),
    'eventsDelivered', to_jsonb(v_row."events_delivered"),
    'method', v_row."delivery_method",
    'endpointUrl', (select we."url" from "better_supabase"."webhook_endpoints" we where we."id" = v_row."endpoint_id"),
    'status', v_row."status",
    'reason', v_row."reason",
    'createdAt', v_row."created_at",
    'updatedAt', v_row."updated_at"
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.verify_hostname (
  id    uuid,
  actor uuid DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."hostnames";
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'Only the service role verifies hostnames' using errcode = '42501', hint = 'HOSTNAME_FORBIDDEN';
  end if;
  select * into v_row from "better_supabase"."hostnames" x where x."id" = verify_hostname.id for update;
  if v_row."id" is null or not (verify_hostname.actor is null or coalesce(better_supabase.can_user(verify_hostname.actor, 'tenant', v_row."tenant_id", 'domains.manage'), false)) then
    raise exception 'No hostname you manage has this id' using errcode = 'P0002', hint = 'HOSTNAME_NOT_FOUND';
  end if;
  if v_row."verified_at" is not null then
    return (to_jsonb(v_row) - 'verification_token') || case when v_row."verified_at" is null then jsonb_build_object('record', jsonb_build_object('type', 'TXT', 'name', '_better-supabase.' || v_row."hostname", 'value', 'better-supabase-hostname-verification=' || v_row."verification_token")) else '{}'::jsonb end;
  end if;
  if exists (select 1 from "better_supabase"."hostnames" x where x."hostname" = v_row."hostname" and x."verified_at" is not null) then
    raise exception 'Another organization holds %', v_row."hostname" using errcode = '23505', hint = 'HOSTNAME_TAKEN';
  end if;
  update "better_supabase"."hostnames" x set "verified_at" = now() where x."id" = v_row."id" returning * into v_row;
  perform "better_supabase".emit_event('hostname.verified', jsonb_build_object('organizationId', v_row."tenant_id"::text, 'hostnameId', v_row."id"::text, 'hostname', v_row."hostname"), 'hostnames/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/domains');
  perform better_supabase.audit_event(
    event_type => 'hostname.verified',
    category => 'configuration',
    target_type => 'hostname',
    record_id => v_row."id"::text,
    target_label => v_row."hostname",
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id"::text, 'hostnameId', v_row."id"::text, 'hostname', v_row."hostname"),
    actor_id => verify_hostname.actor
  );
  return (to_jsonb(v_row) - 'verification_token') || case when v_row."verified_at" is null then jsonb_build_object('record', jsonb_build_object('type', 'TXT', 'name', '_better-supabase.' || v_row."hostname", 'value', 'better-supabase-hostname-verification=' || v_row."verification_token")) else '{}'::jsonb end;
end;
$function$;

ALTER TABLE "better_supabase"."incoming_webhooks"
  ADD CONSTRAINT "incoming_webhooks_created_by_fkey" FOREIGN KEY (created_by) REFERENCES auth.users(id) ON DELETE SET NULL;

ALTER TABLE "better_supabase"."option_set_items"
  ADD CONSTRAINT "option_set_items_option_set_id_fkey" FOREIGN KEY (option_set_id) REFERENCES better_supabase.option_sets(id) ON DELETE CASCADE;

ALTER TABLE "better_supabase"."ssf_streams"
  ADD CONSTRAINT "ssf_streams_endpoint_id_fkey" FOREIGN KEY (endpoint_id) REFERENCES better_supabase.webhook_endpoints(id) ON DELETE SET NULL;

ALTER TABLE "better_supabase"."ssf_events"
  ADD CONSTRAINT "ssf_events_stream_id_fkey" FOREIGN KEY (stream_id) REFERENCES better_supabase.ssf_streams(id) ON DELETE CASCADE;

ALTER TABLE "better_supabase"."work_items"
  ADD CONSTRAINT "work_items_priority_option_id_fkey" FOREIGN KEY (priority_option_id) REFERENCES better_supabase.option_set_items(id) ON DELETE SET NULL;

CREATE VIEW "better_supabase"."maintenance_jobs" WITH (security_invoker=true) AS  SELECT j.job,
    j.fn AS function,
    j.every_interval AS every,
    s.last_run_at,
    s.last_status,
    s.last_error,
    COALESCE(s.runs, (0)::bigint) AS runs,
    ((s.last_run_at IS NULL) OR ((s.last_run_at + j.every_interval) <= now())) AS due
   FROM (( VALUES ('digest_run'::text,'"better_supabase"."run_notification_digests"'::text,'01:00:00'::interval), ('expire_approvals'::text,'"better_supabase"."expire_approvals"'::text,'00:15:00'::interval), ('purge_chat_state'::text,'"better_supabase"."purge_chat_state"'::text,'00:15:00'::interval), ('purge_expired_trash'::text,'"better_supabase"."purge_expired_trash"'::text,'1 day'::interval), ('purge_idempotency_keys'::text,'better_supabase.purge_idempotency_keys'::text,'01:00:00'::interval), ('purge_rate_limits'::text,'better_supabase.purge_rate_limits'::text,'00:15:00'::interval), ('purge_usage_events'::text,'"better_supabase"."purge_usage_events"'::text,'1 day'::interval), ('purge_webhook_deliveries'::text,'"better_supabase"."purge_webhook_deliveries"'::text,'1 day'::interval), ('purge_webhooks'::text,'better_supabase.purge_webhooks'::text,'1 day'::interval)) j(job, fn, every_interval)
     LEFT JOIN better_supabase.maintenance_state s ON ((s.job = j.job)));

CREATE INDEX bsb_work_item_priority_option_id_idx ON better_supabase.work_items USING btree (priority_option_id);

CREATE UNIQUE INDEX hostnames_primary_idx ON better_supabase.hostnames USING btree (tenant_id)
  WHERE is_primary;

CREATE UNIQUE INDEX hostnames_verified_idx ON better_supabase.hostnames USING btree (hostname)
  WHERE (verified_at IS NOT NULL);

CREATE INDEX idempotency_keys_expiry_idx ON better_supabase.idempotency_keys USING btree (expires_at);

CREATE INDEX incoming_webhooks_created_by_idx ON better_supabase.incoming_webhooks USING btree (created_by)
  WHERE (created_by IS NOT NULL);

CREATE INDEX incoming_webhooks_subject_idx ON better_supabase.incoming_webhooks USING btree (tenant, subject_type, subject_id);

CREATE INDEX incoming_webhooks_tenant_idx ON better_supabase.incoming_webhooks USING btree (tenant);

CREATE INDEX option_set_items_set_idx ON better_supabase.option_set_items USING btree (option_set_id, rank);

CREATE UNIQUE INDEX option_set_items_system_key_idx ON better_supabase.option_set_items USING btree (option_set_id, system_key)
  WHERE (system_key IS NOT NULL);

CREATE UNIQUE INDEX option_sets_default_idx ON better_supabase.option_sets USING btree (tenant_id, subject_type, field, COALESCE(scope_id, ''::text))
  WHERE (is_default AND (archived_at IS NULL));

CREATE INDEX ssf_events_created_idx ON better_supabase.ssf_events USING btree (created_at);

CREATE INDEX ssf_events_order_idx ON better_supabase.ssf_events USING btree (stream_id, created_at);

CREATE INDEX ssf_received_at_idx ON better_supabase.ssf_received USING btree (received_at);

CREATE INDEX ssf_streams_endpoint_idx ON better_supabase.ssf_streams USING btree (endpoint_id)
  WHERE (endpoint_id IS NOT NULL);

CREATE INDEX ssf_streams_events_idx ON better_supabase.ssf_streams USING gin (events_delivered);

CREATE INDEX ssf_streams_receiver_idx ON better_supabase.ssf_streams USING btree (receiver);

CREATE INDEX webhook_inbox_dead_idx ON better_supabase.webhook_inbox USING btree (received_at)
  WHERE (status = 'dead'::text);

CREATE INDEX webhook_inbox_processed_idx ON better_supabase.webhook_inbox USING btree (processed_at)
  WHERE (status = 'processed'::text);

CREATE INDEX webhook_inbox_ready_idx ON better_supabase.webhook_inbox USING btree (source, available_at, id)
  WHERE (status = ANY (ARRAY['pending'::text, 'processing'::text]));

CREATE INDEX webhook_inbox_tenant_idx ON better_supabase.webhook_inbox USING btree (tenant, received_at)
  WHERE (tenant IS NOT NULL);

CREATE TRIGGER bsb_incoming_webhook_vault
  AFTER DELETE ON better_supabase.incoming_webhooks
  FOR EACH ROW
  WHEN (((old.secret_id IS NOT NULL) OR (old.previous_secret_id IS NOT NULL)))
  EXECUTE FUNCTION better_supabase.drop_incoming_webhook_secret();

CREATE TRIGGER bsb_updated_at
  BEFORE UPDATE ON better_supabase.incoming_webhooks
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.set_updated_at('updated_at');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.option_sets DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  WHEN (((better_supabase.import_run() IS NULL) OR (current_setting('better_supabase.import_audit'::text, true) IS DISTINCT FROM 'summary'::text)))
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore":[],"redact":[],"target_type":"option_set","event_prefix":"option_set"}');

CREATE TRIGGER bsb_updated_at
  BEFORE UPDATE ON better_supabase.ssf_streams
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.set_updated_at('updated_at');

CREATE TRIGGER bsb_option_work_item_priority
  BEFORE INSERT OR UPDATE OF priority, priority_option_id ON better_supabase.work_items
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.bsb_option_work_item_priority();

CREATE POLICY "bsb_incoming_webhooks_read" ON "better_supabase"."incoming_webhooks"
  FOR SELECT
  TO "authenticated"
  USING
    (((tenant IN ( SELECT better_supabase.incoming_webhook_tenant_ids() AS incoming_webhook_tenant_ids)) AND better_supabase.incoming_webhook_subject_readable(subject_type,
    subject_id, tenant)));

CREATE POLICY "bsb_tenant_scope_delete" ON "better_supabase"."incoming_webhooks"
  AS RESTRICTIVE
  FOR DELETE
  TO PUBLIC
  USING ((tenant IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope_insert" ON "better_supabase"."incoming_webhooks"
  AS RESTRICTIVE
  FOR INSERT
  TO PUBLIC
  WITH CHECK ((tenant IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope_select" ON "better_supabase"."incoming_webhooks"
  AS RESTRICTIVE
  FOR SELECT
  TO PUBLIC
  USING
    (((tenant IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR ((tenant IN ( SELECT better_supabase.incoming_webhook_tenant_ids() AS
    incoming_webhook_tenant_ids)) AND better_supabase.incoming_webhook_subject_readable(subject_type, subject_id, tenant))));

CREATE POLICY "bsb_tenant_scope_update" ON "better_supabase"."incoming_webhooks"
  AS RESTRICTIVE
  FOR UPDATE
  TO PUBLIC
  USING ((tenant IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)))
  WITH CHECK ((tenant IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_option_set_items_read" ON "better_supabase"."option_set_items"
  FOR SELECT
  TO "authenticated"
  USING ((tenant_id IN ( SELECT better_supabase.tenant_ids_with('option_sets.read'::text) AS tenant_ids_with)));

CREATE POLICY "bsb_tenant_scope_delete" ON "better_supabase"."option_set_items"
  AS RESTRICTIVE
  FOR DELETE
  TO PUBLIC
  USING ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope_insert" ON "better_supabase"."option_set_items"
  AS RESTRICTIVE
  FOR INSERT
  TO PUBLIC
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope_select" ON "better_supabase"."option_set_items"
  AS RESTRICTIVE
  FOR SELECT
  TO PUBLIC
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (tenant_id IN ( SELECT
    better_supabase.tenant_ids_with('option_sets.read'::text) AS tenant_ids_with))));

CREATE POLICY "bsb_tenant_scope_update" ON "better_supabase"."option_set_items"
  AS RESTRICTIVE
  FOR UPDATE
  TO PUBLIC
  USING ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_option_sets_read" ON "better_supabase"."option_sets"
  FOR SELECT
  TO "authenticated"
  USING ((tenant_id IN ( SELECT better_supabase.tenant_ids_with('option_sets.read'::text) AS tenant_ids_with)));

CREATE POLICY "bsb_tenant_scope_delete" ON "better_supabase"."option_sets"
  AS RESTRICTIVE
  FOR DELETE
  TO PUBLIC
  USING ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope_insert" ON "better_supabase"."option_sets"
  AS RESTRICTIVE
  FOR INSERT
  TO PUBLIC
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope_select" ON "better_supabase"."option_sets"
  AS RESTRICTIVE
  FOR SELECT
  TO PUBLIC
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (tenant_id IN ( SELECT
    better_supabase.tenant_ids_with('option_sets.read'::text) AS tenant_ids_with))));

CREATE POLICY "bsb_tenant_scope_update" ON "better_supabase"."option_sets"
  AS RESTRICTIVE
  FOR UPDATE
  TO PUBLIC
  USING ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_reserved_slugs_read" ON "better_supabase"."reserved_slugs"
  FOR SELECT
  TO "anon", "authenticated", "service_role"
  USING (true);

REVOKE ALL ON FUNCTION "api"."acquire_lease"(text, integer, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."acquire_lease"(text, integer, text) TO "service_role";

REVOKE ALL ON FUNCTION "api"."add_hostname"(uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."add_hostname"(uuid, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."archive_option_set_item"(uuid, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."archive_option_set_item"(uuid, uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."begin_idempotent"(text, text, text, interval, interval) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."begin_idempotent"(text, text, text, interval, interval) TO "service_role";

REVOKE ALL ON FUNCTION "api"."checkpoint_webhook"(bigint, text, jsonb, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."checkpoint_webhook"(bigint, text, jsonb, integer) TO "service_role";

REVOKE ALL ON FUNCTION "api"."claim_webhooks"(text, text, integer, interval) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."claim_webhooks"(text, text, integer, interval) TO "service_role";

REVOKE ALL ON FUNCTION "api"."complete_idempotent"(text, text, uuid, integer, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."complete_idempotent"(text, text, uuid, integer, jsonb) TO "service_role";

REVOKE ALL ON FUNCTION "api"."complete_webhook"(bigint, text, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."complete_webhook"(bigint, text, integer) TO "service_role";

REVOKE ALL ON FUNCTION "api"."create_incoming_webhook"(uuid, text, text, jsonb, text, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."create_incoming_webhook"(uuid, text, text, jsonb, text, text, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."create_ssf_stream"(uuid, text, text, text[], text, text[], text[], text, text, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."create_ssf_stream"(uuid, text, text, text[], text, text[], text[], text, text, jsonb) TO "service_role";

REVOKE ALL ON FUNCTION "api"."default_option_set"(uuid, text, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."default_option_set"(uuid, text, text, text) TO "service_role";

REVOKE ALL ON FUNCTION "api"."delete_incoming_webhook"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."delete_incoming_webhook"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."delete_ssf_stream"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."delete_ssf_stream"(uuid) TO "service_role";

REVOKE ALL ON FUNCTION "api"."ensure_option_set"(uuid, text, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."ensure_option_set"(uuid, text, text, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."extend_idempotent"(text, text, uuid, interval) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."extend_idempotent"(text, text, uuid, interval) TO "service_role";

REVOKE ALL ON FUNCTION "api"."extend_lease"(text, uuid, integer, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."extend_lease"(text, uuid, integer, text) TO "service_role";

REVOKE ALL ON FUNCTION "api"."extend_webhook"(bigint, text, integer, interval) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."extend_webhook"(bigint, text, integer, interval) TO "service_role";

REVOKE ALL ON FUNCTION "api"."fail_webhook"(bigint, text, text, interval, integer, boolean) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."fail_webhook"(bigint, text, text, interval, integer, boolean) TO "service_role";

REVOKE ALL ON FUNCTION "api"."forget_ssf_received"(text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."forget_ssf_received"(text, text) TO "service_role";

REVOKE ALL ON FUNCTION "api"."hostname_by_id"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."hostname_by_id"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."incoming_webhook_by_token"(text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."incoming_webhook_by_token"(text) TO "service_role";

REVOKE ALL ON FUNCTION "api"."list_hostnames"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."list_hostnames"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."list_incoming_webhooks"(uuid, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."list_incoming_webhooks"(uuid, text, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."list_option_sets"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."list_option_sets"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."list_webhooks"(text, text, text, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."list_webhooks"(text, text, text, integer) TO "service_role";

REVOKE ALL ON FUNCTION "api"."maintenance"(text, boolean) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."maintenance"(text, boolean) TO "service_role";

REVOKE ALL ON FUNCTION "api"."maintenance_schedule"(text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."maintenance_schedule"(text) TO "service_role";

REVOKE ALL ON FUNCTION "api"."maintenance_scheduler"() FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."maintenance_scheduler"() TO "service_role";

REVOKE ALL ON FUNCTION "api"."note_ssf_verification"(uuid, interval) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."note_ssf_verification"(uuid, interval) TO "service_role";

REVOKE ALL ON FUNCTION "api"."poll_ssf_events"(uuid, integer, text[], jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."poll_ssf_events"(uuid, integer, text[], jsonb) TO "service_role";

REVOKE ALL ON FUNCTION "api"."purge_idempotency_keys"() FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."purge_idempotency_keys"() TO "service_role";

REVOKE ALL ON FUNCTION "api"."purge_shared_signals"(interval) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."purge_shared_signals"(interval) TO "service_role";

REVOKE ALL ON FUNCTION "api"."purge_webhooks"(interval, boolean, integer, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."purge_webhooks"(interval, boolean, integer, text) TO "service_role";

REVOKE ALL ON FUNCTION "api"."queue_ssf_set"(uuid, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."queue_ssf_set"(uuid, text, text) TO "service_role";

REVOKE ALL ON FUNCTION "api"."rank_option_set_item"(uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."rank_option_set_item"(uuid, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."receive_webhook"(text, text, text, jsonb, jsonb, text, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."receive_webhook"(text, text, text, jsonb, jsonb, text, integer) TO "service_role";

REVOKE ALL ON FUNCTION "api"."record_incoming_webhook"(uuid, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."record_incoming_webhook"(uuid, integer) TO "service_role";

REVOKE ALL ON FUNCTION "api"."record_ssf_received"(text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."record_ssf_received"(text, text) TO "service_role";

REVOKE ALL ON FUNCTION "api"."release_idempotent"(text, text, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."release_idempotent"(text, text, uuid) TO "service_role";

REVOKE ALL ON FUNCTION "api"."release_lease"(text, uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."release_lease"(text, uuid, text) TO "service_role";

REVOKE ALL ON FUNCTION "api"."remove_hostname"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."remove_hostname"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."resolve_hostname"(text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."resolve_hostname"(text) TO "anon", "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."rotate_incoming_webhook"(uuid, boolean) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."rotate_incoming_webhook"(uuid, boolean) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."rotate_incoming_webhook_secret"(uuid, interval) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."rotate_incoming_webhook_secret"(uuid, interval) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."save_option_set"(uuid, uuid, text, text, text, text, text, boolean) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."save_option_set"(uuid, uuid, text, text, text, text, text, boolean) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."save_option_set_item"(uuid, uuid, text, text, integer, text, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."save_option_set_item"(uuid, uuid, text, text, integer, text, text, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."set_incoming_webhook_enabled"(uuid, boolean) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."set_incoming_webhook_enabled"(uuid, boolean) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."set_primary_hostname"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."set_primary_hostname"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."set_ssf_stream_status"(uuid, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."set_ssf_stream_status"(uuid, text, text) TO "service_role";

REVOKE ALL ON FUNCTION "api"."slug_problem"(text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."slug_problem"(text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."ssf_stream"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."ssf_stream"(uuid) TO "service_role";

REVOKE ALL ON FUNCTION "api"."ssf_streams"(text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."ssf_streams"(text) TO "service_role";

REVOKE ALL ON FUNCTION "api"."ssf_streams_for_event"(text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."ssf_streams_for_event"(text, text) TO "service_role";

REVOKE ALL ON FUNCTION "api"."update_incoming_webhook"(uuid, text, jsonb, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."update_incoming_webhook"(uuid, text, jsonb, text, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."update_ssf_stream"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."update_ssf_stream"(uuid, jsonb) TO "service_role";

REVOKE ALL ON FUNCTION "api"."verify_hostname"(uuid, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."verify_hostname"(uuid, uuid) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."acquire_lease"(text, integer, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."acquire_lease"(text, integer, text) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."add_hostname"(uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."add_hostname"(uuid, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."archive_option_set_item"(uuid, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."archive_option_set_item"(uuid, uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."begin_idempotent"(text, text, text, interval, interval) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."begin_idempotent"(text, text, text, interval, interval) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."checkpoint_webhook"(bigint, text, jsonb, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."checkpoint_webhook"(bigint, text, jsonb, integer) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."claim_webhooks"(text, text, integer, interval) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."claim_webhooks"(text, text, integer, interval) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."complete_idempotent"(text, text, uuid, integer, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."complete_idempotent"(text, text, uuid, integer, jsonb) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."complete_webhook"(bigint, text, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."complete_webhook"(bigint, text, integer) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."create_incoming_webhook"(uuid, text, text, jsonb, text, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."create_incoming_webhook"(uuid, text, text, jsonb, text, text, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."create_ssf_stream"(uuid, text, text, text[], text, text[], text[], text, text, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."create_ssf_stream"(uuid, text, text, text[], text, text[], text[], text, text, jsonb) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."default_option_set"(uuid, text, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."default_option_set"(uuid, text, text, text) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."delete_incoming_webhook"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."delete_incoming_webhook"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."delete_ssf_stream"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."delete_ssf_stream"(uuid) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."drop_incoming_webhook_secret"() FROM PUBLIC;

REVOKE ALL ON FUNCTION "better_supabase"."ensure_option_set"(uuid, text, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."ensure_option_set"(uuid, text, text, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."extend_idempotent"(text, text, uuid, interval) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."extend_idempotent"(text, text, uuid, interval) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."extend_lease"(text, uuid, integer, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."extend_lease"(text, uuid, integer, text) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."extend_webhook"(bigint, text, integer, interval) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."extend_webhook"(bigint, text, integer, interval) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."fail_webhook"(bigint, text, text, interval, integer, boolean) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."fail_webhook"(bigint, text, text, interval, integer, boolean) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."forget_ssf_received"(text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."forget_ssf_received"(text, text) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."hostname_by_id"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."hostname_by_id"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."incoming_webhook_by_token"(text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."incoming_webhook_by_token"(text) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."incoming_webhook_subject_readable"(text, text, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."incoming_webhook_subject_readable"(text, text, uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."incoming_webhook_tenant_ids"() FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."incoming_webhook_tenant_ids"() TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."list_hostnames"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."list_hostnames"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."list_incoming_webhooks"(uuid, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."list_incoming_webhooks"(uuid, text, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."list_option_sets"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."list_option_sets"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."list_webhooks"(text, text, text, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."list_webhooks"(text, text, text, integer) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."note_ssf_verification"(uuid, interval) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."note_ssf_verification"(uuid, interval) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."poll_ssf_events"(uuid, integer, text[], jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."poll_ssf_events"(uuid, integer, text[], jsonb) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."purge_idempotency_keys"() FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."purge_idempotency_keys"() TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."purge_shared_signals"(interval) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."purge_shared_signals"(interval) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."purge_webhooks"(interval, boolean, integer, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."purge_webhooks"(interval, boolean, integer, text) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."queue_ssf_set"(uuid, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."queue_ssf_set"(uuid, text, text) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."rank_option_set_item"(uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."rank_option_set_item"(uuid, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."receive_webhook"(text, text, text, jsonb, jsonb, text, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."receive_webhook"(text, text, text, jsonb, jsonb, text, integer) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."record_incoming_webhook"(uuid, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."record_incoming_webhook"(uuid, integer) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."record_ssf_received"(text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."record_ssf_received"(text, text) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."release_idempotent"(text, text, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."release_idempotent"(text, text, uuid) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."release_lease"(text, uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."release_lease"(text, uuid, text) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."remove_hostname"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."remove_hostname"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."resolve_hostname"(text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."resolve_hostname"(text) TO "anon", "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."rotate_incoming_webhook"(uuid, boolean) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."rotate_incoming_webhook"(uuid, boolean) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."rotate_incoming_webhook_secret"(uuid, interval) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."rotate_incoming_webhook_secret"(uuid, interval) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."save_option_set"(uuid, uuid, text, text, text, text, text, boolean) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."save_option_set"(uuid, uuid, text, text, text, text, text, boolean) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."save_option_set_item"(uuid, uuid, text, text, integer, text, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."save_option_set_item"(uuid, uuid, text, text, integer, text, text, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."set_incoming_webhook_enabled"(uuid, boolean) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."set_incoming_webhook_enabled"(uuid, boolean) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."set_primary_hostname"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."set_primary_hostname"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."set_ssf_stream_status"(uuid, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."set_ssf_stream_status"(uuid, text, text) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."slug_problem"(text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."slug_problem"(text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."ssf_stream"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."ssf_stream"(uuid) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."ssf_streams"(text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."ssf_streams"(text) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."ssf_streams_for_event"(text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."ssf_streams_for_event"(text, text) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."track_slug"(regclass, text) FROM PUBLIC;

REVOKE ALL ON FUNCTION "better_supabase"."update_incoming_webhook"(uuid, text, jsonb, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."update_incoming_webhook"(uuid, text, jsonb, text, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."update_ssf_stream"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."update_ssf_stream"(uuid, jsonb) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."verify_hostname"(uuid, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."verify_hostname"(uuid, uuid) TO "service_role";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."hostnames" TO "service_role";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."idempotency_keys" TO "service_role";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."idempotency_leases" TO "service_role";

GRANT SELECT ("created_at") ON TABLE "better_supabase"."incoming_webhooks" TO "authenticated";

GRANT SELECT ("created_by") ON TABLE "better_supabase"."incoming_webhooks" TO "authenticated";

GRANT SELECT ("enabled") ON TABLE "better_supabase"."incoming_webhooks" TO "authenticated";

GRANT SELECT ("id") ON TABLE "better_supabase"."incoming_webhooks" TO "authenticated";

GRANT SELECT ("last_received_at") ON TABLE "better_supabase"."incoming_webhooks" TO "authenticated";

GRANT SELECT ("last_status") ON TABLE "better_supabase"."incoming_webhooks" TO "authenticated";

GRANT SELECT ("max_body_bytes") ON TABLE "better_supabase"."incoming_webhooks" TO "authenticated";

GRANT SELECT ("metadata") ON TABLE "better_supabase"."incoming_webhooks" TO "authenticated";

GRANT SELECT ("name") ON TABLE "better_supabase"."incoming_webhooks" TO "authenticated";

GRANT SELECT ("receive_count") ON TABLE "better_supabase"."incoming_webhooks" TO "authenticated";

GRANT SELECT ("signature_header") ON TABLE "better_supabase"."incoming_webhooks" TO "authenticated";

GRANT SELECT ("subject_id") ON TABLE "better_supabase"."incoming_webhooks" TO "authenticated";

GRANT SELECT ("subject_type") ON TABLE "better_supabase"."incoming_webhooks" TO "authenticated";

GRANT SELECT ("tenant") ON TABLE "better_supabase"."incoming_webhooks" TO "authenticated";

GRANT SELECT ("updated_at") ON TABLE "better_supabase"."incoming_webhooks" TO "authenticated";

GRANT SELECT ("verify") ON TABLE "better_supabase"."incoming_webhooks" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."incoming_webhooks" TO "service_role";

GRANT SELECT ON TABLE "better_supabase"."option_set_items" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."option_set_items" TO "service_role";

GRANT SELECT ON TABLE "better_supabase"."option_sets" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."option_sets" TO "service_role";

GRANT SELECT ON TABLE "better_supabase"."reserved_slugs" TO "anon", "authenticated", "service_role";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."ssf_events" TO "service_role";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."ssf_received" TO "service_role";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."ssf_streams" TO "service_role";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."webhook_inbox" TO "service_role";

GRANT SELECT ON TABLE "better_supabase"."maintenance_jobs" TO "service_role";

ALTER TABLE "better_supabase"."hostnames"
  ADD CONSTRAINT "hostnames_created_by_fkey" FOREIGN KEY (created_by) REFERENCES auth.users(id) ON DELETE SET NULL;

CREATE INDEX hostnames_created_by_idx ON better_supabase.hostnames USING btree (created_by)
  WHERE (created_by IS NOT NULL);
