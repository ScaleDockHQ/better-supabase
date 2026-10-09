SET local check_function_bodies = off;

CREATE TABLE "better_supabase"."ai_batch_items" (
  "batch_id"        uuid                     NOT NULL,
  "request_id"      text                     NOT NULL,
  "organization_id" uuid                     NOT NULL,
  "status"          text                     NOT NULL,
  "output"          jsonb,
  "usage"           jsonb,
  "error"           text,
  "created_at"      timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "ai_batch_items_error_check" CHECK ((length(error) <= 4000)),
  CONSTRAINT "ai_batch_items_pkey" PRIMARY KEY (batch_id, request_id),
  CONSTRAINT "ai_batch_items_request_id_check" CHECK (((length(request_id) >= 1) AND (length(request_id) <= 200))),
  CONSTRAINT "ai_batch_items_status_check" CHECK ((status = ANY (ARRAY['succeeded'::text, 'failed'::text, 'cancelled'::text, 'expired'::text])))
);

ALTER TABLE "better_supabase"."ai_batch_items"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."ai_batches" (
  "id"              uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "organization_id" uuid                     NOT NULL,
  "user_id"         uuid,
  "provider"        text                     NOT NULL,
  "reference"       jsonb                    NOT NULL,
  "status"          text                     NOT NULL DEFAULT 'pending'::text,
  "raw_status"      text,
  "item_count"      integer                  NOT NULL DEFAULT 0,
  "counts"          jsonb                    NOT NULL DEFAULT '{}'::jsonb,
  "error"           text,
  "metadata"        jsonb                    NOT NULL DEFAULT '{}'::jsonb,
  "results_saved"   boolean                  NOT NULL DEFAULT false,
  "polls"           integer                  NOT NULL DEFAULT 0,
  "next_poll_at"    timestamp with time zone DEFAULT now(),
  "expires_at"      timestamp with time zone,
  "completed_at"    timestamp with time zone,
  "created_at"      timestamp with time zone NOT NULL DEFAULT now(),
  "updated_at"      timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "ai_batches_counts_check" CHECK ((jsonb_typeof(counts) = 'object'::text)),
  CONSTRAINT "ai_batches_error_check" CHECK ((length(error) <= 4000)),
  CONSTRAINT "ai_batches_item_count_check" CHECK ((item_count >= 0)),
  CONSTRAINT "ai_batches_metadata_check" CHECK ((jsonb_typeof(metadata) = 'object'::text)),
  CONSTRAINT "ai_batches_pkey" PRIMARY KEY (id),
  CONSTRAINT "ai_batches_provider_check" CHECK (((length(provider) >= 1) AND (length(provider) <= 100))),
  CONSTRAINT "ai_batches_raw_status_check" CHECK ((length(raw_status) <= 100)),
  CONSTRAINT "ai_batches_reference_check" CHECK ((jsonb_typeof(reference) = 'object'::text)),
  CONSTRAINT "ai_batches_status_check" CHECK ((status = ANY (ARRAY['pending'::text, 'completed'::text, 'failed'::text, 'cancelled'::text])))
);

ALTER TABLE "better_supabase"."ai_batches"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."ai_cache_entries" (
  "key"             text                     NOT NULL,
  "organization_id" uuid,
  "kind"            text                     NOT NULL DEFAULT 'generate'::text,
  "model"           text,
  "value"           jsonb                    NOT NULL,
  "hits"            integer                  NOT NULL DEFAULT 0,
  "created_at"      timestamp with time zone NOT NULL DEFAULT now(),
  "last_hit_at"     timestamp with time zone,
  "expires_at"      timestamp with time zone NOT NULL,
  CONSTRAINT "ai_cache_entries_key_check" CHECK (((length(key) >= 1) AND (length(key) <= 256))),
  CONSTRAINT "ai_cache_entries_kind_check" CHECK ((kind = ANY (ARRAY['generate'::text, 'stream'::text, 'embed'::text, 'other'::text]))),
  CONSTRAINT "ai_cache_entries_model_check" CHECK ((length(model) <= 200)),
  CONSTRAINT "ai_cache_entries_pkey" PRIMARY KEY (key),
  CONSTRAINT "ai_cache_entries_value_check" CHECK ((octet_length((value)::text) <= 1048576))
);

ALTER TABLE "better_supabase"."ai_cache_entries"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."ai_provider_keys" (
  "id"              uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "organization_id" uuid                     NOT NULL,
  "provider"        text                     NOT NULL,
  "name"            text                     NOT NULL DEFAULT 'default'::text,
  "credential_ref"  jsonb                    NOT NULL,
  "settings"        jsonb                    NOT NULL DEFAULT '{}'::jsonb,
  "enabled"         boolean                  NOT NULL DEFAULT true,
  "created_by"      uuid,
  "created_at"      timestamp with time zone NOT NULL DEFAULT now(),
  "updated_at"      timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "ai_provider_keys_credential_ref_check" CHECK (((jsonb_typeof(credential_ref) = 'object'::text) AND (credential_ref ? 'provider'::text))),
  CONSTRAINT "ai_provider_keys_name_check" CHECK (((length(name) >= 1) AND (length(name) <= 100))),
  CONSTRAINT "ai_provider_keys_organization_id_provider_name_key" UNIQUE (organization_id, PROVIDER, name),
  CONSTRAINT "ai_provider_keys_pkey" PRIMARY KEY (id),
  CONSTRAINT "ai_provider_keys_provider_check" CHECK ((provider ~ '^[a-z0-9][a-z0-9._-]{0,63}$'::text)),
  CONSTRAINT "ai_provider_keys_settings_check" CHECK ((jsonb_typeof(settings) = 'object'::text))
);

ALTER TABLE "better_supabase"."ai_provider_keys"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."ai_sandboxes" (
  "id"              uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "organization_id" uuid                     NOT NULL,
  "user_id"         uuid,
  "chat_id"         uuid,
  "provider"        text                     NOT NULL,
  "sandbox_id"      text                     NOT NULL,
  "container_id"    text,
  "status"          text                     NOT NULL DEFAULT 'running'::text,
  "metadata"        jsonb                    NOT NULL DEFAULT '{}'::jsonb,
  "idle_seconds"    integer                  NOT NULL DEFAULT 600,
  "error"           text,
  "last_used_at"    timestamp with time zone NOT NULL DEFAULT now(),
  "expires_at"      timestamp with time zone,
  "stopped_at"      timestamp with time zone,
  "created_at"      timestamp with time zone NOT NULL DEFAULT now(),
  "updated_at"      timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "ai_sandboxes_container_id_check" CHECK ((length(container_id) <= 200)),
  CONSTRAINT "ai_sandboxes_error_check" CHECK ((length(error) <= 4000)),
  CONSTRAINT "ai_sandboxes_idle_seconds_check" CHECK ((idle_seconds > 0)),
  CONSTRAINT "ai_sandboxes_metadata_check" CHECK ((jsonb_typeof(metadata) = 'object'::text)),
  CONSTRAINT "ai_sandboxes_pkey" PRIMARY KEY (id),
  CONSTRAINT "ai_sandboxes_provider_check" CHECK ((provider ~ '^[a-z0-9][a-z0-9._-]{0,63}$'::text)),
  CONSTRAINT "ai_sandboxes_provider_sandbox_id_key" UNIQUE (PROVIDER, sandbox_id),
  CONSTRAINT "ai_sandboxes_sandbox_id_check" CHECK (((length(sandbox_id) >= 1) AND (length(sandbox_id) <= 200))),
  CONSTRAINT "ai_sandboxes_status_check" CHECK ((status = ANY (ARRAY['running'::text, 'stopping'::text, 'stopped'::text])))
);

ALTER TABLE "better_supabase"."ai_sandboxes"
  ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION api.ai_cache_delete (
  key    text DEFAULT NULL::text,
  tenant uuid DEFAULT NULL::uuid,
  model  text DEFAULT NULL::text
)
  RETURNS integer
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."ai_cache_delete"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.ai_cache_get (
  key text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."ai_cache_get"($1) $function$;

CREATE OR REPLACE FUNCTION api.ai_cache_set (
  key    text,
  value  jsonb,
  ttl    integer,
  tenant uuid    DEFAULT NULL::uuid,
  kind   text    DEFAULT 'generate'::text,
  model  text    DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."ai_cache_set"($1, $2, $3, $4, $5, $6) $function$;

CREATE OR REPLACE FUNCTION api.ai_provider_keys_for (
  tenant    uuid,
  providers text[] DEFAULT NULL::text[]
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."ai_provider_keys_for"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.ai_sandbox_for (
  chat_id  uuid,
  provider text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."ai_sandbox_for"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.delete_ai_provider_key (
  id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."delete_ai_provider_key"($1) $function$;

CREATE OR REPLACE FUNCTION api.delete_ai_provider_keys (
  tenant uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."delete_ai_provider_keys"($1) $function$;

CREATE OR REPLACE FUNCTION api.due_ai_batches (
  batch         integer DEFAULT 20,
  lease_seconds integer DEFAULT 300
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."due_ai_batches"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.finish_ai_sandbox_stop (
  id      uuid,
  stopped boolean,
  error   text    DEFAULT NULL::text
)
  RETURNS boolean
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."finish_ai_sandbox_stop"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.get_ai_batch (
  id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."get_ai_batch"($1) $function$;

CREATE OR REPLACE FUNCTION api.idle_ai_sandboxes (
  batch         integer DEFAULT 50,
  lease_seconds integer DEFAULT 300
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."idle_ai_sandboxes"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.list_ai_batch_items (
  id       uuid,
  after    text    DEFAULT NULL::text,
  max_rows integer DEFAULT 100
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_ai_batch_items"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.list_ai_batches (
  tenant   uuid,
  status   text    DEFAULT NULL::text,
  max_rows integer DEFAULT 50
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_ai_batches"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.list_ai_provider_keys (
  tenant uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_ai_provider_keys"($1) $function$;

CREATE OR REPLACE FUNCTION api.list_ai_sandboxes (
  tenant  uuid,
  chat_id uuid DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_ai_sandboxes"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.purge_ai_cache (
  batch integer DEFAULT 5000
)
  RETURNS integer
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."purge_ai_cache"($1) $function$;

CREATE OR REPLACE FUNCTION api.record_ai_batch (
  tenant    uuid,
  provider  text,
  reference jsonb,
  fields    jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."record_ai_batch"($1, $2, $3, $4) $function$;

CREATE OR REPLACE FUNCTION api.register_ai_sandbox (
  tenant     uuid,
  provider   text,
  sandbox_id text,
  fields     jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."register_ai_sandbox"($1, $2, $3, $4) $function$;

CREATE OR REPLACE FUNCTION api.save_ai_batch_items (
  id    uuid,
  items jsonb
)
  RETURNS integer
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."save_ai_batch_items"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.save_ai_provider_key (
  tenant         uuid,
  provider       text,
  credential_ref jsonb,
  name           text    DEFAULT 'default'::text,
  settings       jsonb   DEFAULT '{}'::jsonb,
  enabled        boolean DEFAULT true
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."save_ai_provider_key"($1, $2, $3, $4, $5, $6) $function$;

CREATE OR REPLACE FUNCTION api.touch_ai_sandbox (
  id uuid
)
  RETURNS boolean
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."touch_ai_sandbox"($1) $function$;

CREATE OR REPLACE FUNCTION api.update_ai_batch (
  id     uuid,
  fields jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."update_ai_batch"($1, $2) $function$;

CREATE OR REPLACE FUNCTION better_supabase.ai_cache_delete (
  key    text DEFAULT NULL::text,
  tenant uuid DEFAULT NULL::uuid,
  model  text DEFAULT NULL::text
)
  RETURNS integer
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_count integer;
begin
  if ai_cache_delete.key is null and ai_cache_delete.tenant is null and ai_cache_delete.model is null then
    raise exception 'name a key, a tenant or a model' using errcode = '22023', hint = 'AI_CACHE_INVALID';
  end if;
  delete from "better_supabase"."ai_cache_entries" x
  where (ai_cache_delete.key is null or x."key" = ai_cache_delete.key)
    and (ai_cache_delete.tenant is null or x."organization_id" = ai_cache_delete.tenant)
    and (ai_cache_delete.model is null or x."model" = ai_cache_delete.model);
  get diagnostics v_count = row_count;
  return v_count;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.ai_cache_get (
  key text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."ai_cache_entries"%rowtype;
begin
  update "better_supabase"."ai_cache_entries" x set "hits" = x."hits" + 1, "last_hit_at" = now()
  where x."key" = ai_cache_get.key and x."expires_at" > now()
  returning * into v_row;
  if not found then
    return null;
  end if;
  return jsonb_build_object('key', v_row."key", 'organization_id', v_row."organization_id", 'kind', v_row."kind", 'model', v_row."model", 'value', v_row."value", 'hits', v_row."hits", 'created_at', v_row."created_at", 'last_hit_at', v_row."last_hit_at", 'expires_at', v_row."expires_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.ai_cache_set (
  key    text,
  value  jsonb,
  ttl    integer,
  tenant uuid    DEFAULT NULL::uuid,
  kind   text    DEFAULT 'generate'::text,
  model  text    DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_row "better_supabase"."ai_cache_entries"%rowtype;
begin
  if ai_cache_set.ttl is null or ai_cache_set.ttl < 1 then
    raise exception 'ttl must be at least one second' using errcode = '22023', hint = 'AI_CACHE_INVALID';
  end if;
  insert into "better_supabase"."ai_cache_entries" ("key", "organization_id", "kind", "model", "value", "expires_at")
  values (ai_cache_set.key, ai_cache_set.tenant, coalesce(ai_cache_set.kind, 'generate'), ai_cache_set.model, ai_cache_set.value,
    now() + make_interval(secs => least(ai_cache_set.ttl, 604800)))
  on conflict ("key") do update set
    "organization_id" = excluded."organization_id",
    "kind" = excluded."kind",
    "model" = excluded."model",
    "value" = excluded."value",
    "hits" = 0,
    "created_at" = now(),
    "last_hit_at" = null,
    "expires_at" = excluded."expires_at"
  returning * into v_row;
  return jsonb_build_object('key', v_row."key", 'organization_id', v_row."organization_id", 'kind', v_row."kind", 'model', v_row."model", 'value', v_row."value", 'hits', v_row."hits", 'created_at', v_row."created_at", 'last_hit_at', v_row."last_hit_at", 'expires_at', v_row."expires_at") - 'value';
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.ai_provider_keys_for (
  tenant    uuid,
  providers text[] DEFAULT NULL::text[]
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organization_id', x."organization_id", 'provider', x."provider", 'name', x."name", 'credential_ref', x."credential_ref", 'settings', x."settings", 'enabled', x."enabled", 'created_by', x."created_by", 'created_at', x."created_at", 'updated_at', x."updated_at") order by x."provider", x."name"), '[]')
  from "better_supabase"."ai_provider_keys" x
  where x."organization_id" = ai_provider_keys_for.tenant and x."enabled"
    and (ai_provider_keys_for.providers is null or x."provider" = any (ai_provider_keys_for.providers))
$function$;

CREATE OR REPLACE FUNCTION better_supabase.ai_sandbox_for (
  chat_id  uuid,
  provider text
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select jsonb_build_object('id', x."id", 'organization_id', x."organization_id", 'user_id', x."user_id", 'chat_id', x."chat_id", 'provider', x."provider", 'sandbox_id', x."sandbox_id", 'container_id', x."container_id", 'status', x."status", 'metadata', x."metadata", 'idle_seconds', x."idle_seconds", 'error', x."error", 'last_used_at', x."last_used_at", 'expires_at', x."expires_at", 'stopped_at', x."stopped_at", 'created_at', x."created_at", 'updated_at', x."updated_at") from "better_supabase"."ai_sandboxes" x
  where x."chat_id" = ai_sandbox_for.chat_id and x."provider" = ai_sandbox_for.provider and x."status" = 'running'
    and (x."expires_at" is null or x."expires_at" > now())
  order by x."last_used_at" desc
  limit 1
$function$;

CREATE OR REPLACE FUNCTION better_supabase.delete_ai_provider_key (
  id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."ai_provider_keys"%rowtype;
begin
  select * into v_row from "better_supabase"."ai_provider_keys" x where x."id" = delete_ai_provider_key.id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."organization_id", 'ai_chat.admin'), false)) then
    return null;
  end if;
  delete from "better_supabase"."ai_provider_keys" x where x."id" = v_row."id";
  return jsonb_build_object('id', v_row."id", 'organization_id', v_row."organization_id", 'provider', v_row."provider", 'name', v_row."name", 'credential_ref', v_row."credential_ref", 'settings', v_row."settings", 'enabled', v_row."enabled", 'created_by', v_row."created_by", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.delete_ai_provider_keys (
  tenant uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  with gone as (
    delete from "better_supabase"."ai_provider_keys" x where x."organization_id" = delete_ai_provider_keys.tenant returning x.*
  )
  select coalesce(jsonb_agg(jsonb_build_object('id', gone."id", 'organization_id', gone."organization_id", 'provider', gone."provider", 'name', gone."name", 'credential_ref', gone."credential_ref", 'settings', gone."settings", 'enabled', gone."enabled", 'created_by', gone."created_by", 'created_at', gone."created_at", 'updated_at', gone."updated_at")), '[]') from gone
$function$;

CREATE OR REPLACE FUNCTION better_supabase.due_ai_batches (
  batch         integer DEFAULT 20,
  lease_seconds integer DEFAULT 300
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_rows jsonb;
begin
  with due as (
    select y."id" from "better_supabase"."ai_batches" y
    where (y."status" = 'pending' or not y."results_saved") and y."next_poll_at" <= now()
    order by y."next_poll_at"
    limit least(greatest(due_ai_batches.batch, 1), 200)
    for update skip locked
  ), claimed as (
    update "better_supabase"."ai_batches" x set
      "polls" = x."polls" + 1,
      "next_poll_at" = now() + make_interval(secs => greatest(due_ai_batches.lease_seconds, 1)),
      "updated_at" = now()
    from due where x."id" = due."id"
    returning x.*
  )
  select coalesce(jsonb_agg(jsonb_build_object('id', claimed."id", 'organization_id', claimed."organization_id", 'user_id', claimed."user_id", 'provider', claimed."provider", 'reference', claimed."reference", 'status', claimed."status", 'raw_status', claimed."raw_status", 'item_count', claimed."item_count", 'counts', claimed."counts", 'error', claimed."error", 'metadata', claimed."metadata", 'results_saved', claimed."results_saved", 'polls', claimed."polls", 'next_poll_at', claimed."next_poll_at", 'expires_at', claimed."expires_at", 'completed_at', claimed."completed_at", 'created_at', claimed."created_at", 'updated_at', claimed."updated_at")), '[]') into v_rows from claimed;
  return v_rows;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.finish_ai_sandbox_stop (
  id      uuid,
  stopped boolean,
  error   text    DEFAULT NULL::text
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  update "better_supabase"."ai_sandboxes" x set
    "status" = case when finish_ai_sandbox_stop.stopped then 'stopped' else 'running' end,
    "stopped_at" = case when finish_ai_sandbox_stop.stopped then now() else null end,
    "error" = left(finish_ai_sandbox_stop.error, 4000),
    "updated_at" = now()
  where x."id" = finish_ai_sandbox_stop.id and x."status" <> 'stopped';
  return found;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.get_ai_batch (
  id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select jsonb_build_object('id', x."id", 'organization_id', x."organization_id", 'user_id', x."user_id", 'provider', x."provider", 'reference', x."reference", 'status', x."status", 'raw_status', x."raw_status", 'item_count', x."item_count", 'counts', x."counts", 'error', x."error", 'metadata', x."metadata", 'results_saved', x."results_saved", 'polls', x."polls", 'next_poll_at', x."next_poll_at", 'expires_at', x."expires_at", 'completed_at', x."completed_at", 'created_at', x."created_at", 'updated_at', x."updated_at") from "better_supabase"."ai_batches" x where x."id" = get_ai_batch.id
$function$;

CREATE OR REPLACE FUNCTION better_supabase.idle_ai_sandboxes (
  batch         integer DEFAULT 50,
  lease_seconds integer DEFAULT 300
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_rows jsonb;
begin
  with due as (
    select y."id" from "better_supabase"."ai_sandboxes" y
    where (y."status" = 'running' and (y."last_used_at" + make_interval(secs => y."idle_seconds") <= now() or y."expires_at" <= now()))
       or (y."status" = 'stopping' and y."updated_at" <= now() - make_interval(secs => greatest(idle_ai_sandboxes.lease_seconds, 1)))
    order by y."last_used_at"
    limit least(greatest(idle_ai_sandboxes.batch, 1), 500)
    for update skip locked
  ), claimed as (
    update "better_supabase"."ai_sandboxes" x set "status" = 'stopping', "updated_at" = now()
    from due where x."id" = due."id"
    returning x.*
  )
  select coalesce(jsonb_agg(jsonb_build_object('id', claimed."id", 'organization_id', claimed."organization_id", 'user_id', claimed."user_id", 'chat_id', claimed."chat_id", 'provider', claimed."provider", 'sandbox_id', claimed."sandbox_id", 'container_id', claimed."container_id", 'status', claimed."status", 'metadata', claimed."metadata", 'idle_seconds', claimed."idle_seconds", 'error', claimed."error", 'last_used_at', claimed."last_used_at", 'expires_at', claimed."expires_at", 'stopped_at', claimed."stopped_at", 'created_at', claimed."created_at", 'updated_at', claimed."updated_at")), '[]') into v_rows from claimed;
  return v_rows;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_ai_batch_items (
  id       uuid,
  after    text    DEFAULT NULL::text,
  max_rows integer DEFAULT 100
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select coalesce(jsonb_agg(jsonb_build_object('batch_id', x."batch_id", 'request_id', x."request_id", 'organization_id', x."organization_id", 'status', x."status", 'output', x."output", 'usage', x."usage", 'error', x."error", 'created_at', x."created_at") order by x."request_id"), '[]')
  from (
    select * from "better_supabase"."ai_batch_items" y
    where y."batch_id" = list_ai_batch_items.id and (list_ai_batch_items.after is null or y."request_id" > list_ai_batch_items.after)
    order by y."request_id"
    limit least(greatest(list_ai_batch_items.max_rows, 1), 1000)
  ) x
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_ai_batches (
  tenant   uuid,
  status   text    DEFAULT NULL::text,
  max_rows integer DEFAULT 50
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organization_id', x."organization_id", 'user_id', x."user_id", 'provider', x."provider", 'reference', x."reference", 'status', x."status", 'raw_status', x."raw_status", 'item_count', x."item_count", 'counts', x."counts", 'error', x."error", 'metadata', x."metadata", 'results_saved', x."results_saved", 'polls', x."polls", 'next_poll_at', x."next_poll_at", 'expires_at', x."expires_at", 'completed_at', x."completed_at", 'created_at', x."created_at", 'updated_at', x."updated_at") order by x."created_at" desc), '[]')
  from (
    select * from "better_supabase"."ai_batches" y
    where y."organization_id" = list_ai_batches.tenant and (list_ai_batches.status is null or y."status" = list_ai_batches.status)
    order by y."created_at" desc
    limit least(greatest(list_ai_batches.max_rows, 1), 200)
  ) x
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_ai_provider_keys (
  tenant uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organization_id', x."organization_id", 'provider', x."provider", 'name', x."name", 'credential_ref', x."credential_ref", 'settings', x."settings", 'enabled', x."enabled", 'created_by', x."created_by", 'created_at', x."created_at", 'updated_at', x."updated_at") order by x."provider", x."name"), '[]')
  from "better_supabase"."ai_provider_keys" x where x."organization_id" = list_ai_provider_keys.tenant
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_ai_sandboxes (
  tenant  uuid,
  chat_id uuid DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organization_id', x."organization_id", 'user_id', x."user_id", 'chat_id', x."chat_id", 'provider', x."provider", 'sandbox_id', x."sandbox_id", 'container_id', x."container_id", 'status', x."status", 'metadata', x."metadata", 'idle_seconds', x."idle_seconds", 'error', x."error", 'last_used_at', x."last_used_at", 'expires_at', x."expires_at", 'stopped_at', x."stopped_at", 'created_at', x."created_at", 'updated_at', x."updated_at") order by x."created_at" desc), '[]')
  from "better_supabase"."ai_sandboxes" x
  where x."organization_id" = list_ai_sandboxes.tenant and (list_ai_sandboxes.chat_id is null or x."chat_id" = list_ai_sandboxes.chat_id)
$function$;

CREATE OR REPLACE FUNCTION better_supabase.purge_ai_cache (
  batch integer DEFAULT 5000
)
  RETURNS integer
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_count integer;
begin
  delete from "better_supabase"."ai_cache_entries" x
  where x."key" in (
    select y."key" from "better_supabase"."ai_cache_entries" y
    where y."expires_at" <= now()
    order by y."expires_at"
    limit least(greatest(purge_ai_cache.batch, 1), 50000)
    for update skip locked
  );
  get diagnostics v_count = row_count;
  return v_count;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.record_ai_batch (
  tenant    uuid,
  provider  text,
  reference jsonb,
  fields    jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_row "better_supabase"."ai_batches"%rowtype;
  v_fields jsonb := coalesce(record_ai_batch.fields, '{}');
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (auth.uid() is not null and coalesce(better_supabase.can('tenant', record_ai_batch.tenant, 'ai_chat.create'), false))) then
    raise exception 'you may not start batches here' using errcode = '42501', hint = 'AI_BATCH_FORBIDDEN';
  end if;
  insert into "better_supabase"."ai_batches" ("organization_id", "user_id", "provider", "reference", "status", "raw_status", "item_count", "counts", "metadata", "expires_at", "next_poll_at")
  values (
    record_ai_batch.tenant,
    case when coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then (v_fields ->> 'user_id')::uuid else auth.uid() end,
    record_ai_batch.provider,
    record_ai_batch.reference,
    coalesce(v_fields ->> 'status', 'pending'),
    v_fields ->> 'raw_status',
    coalesce((v_fields ->> 'item_count')::integer, 0),
    coalesce(v_fields -> 'counts', '{}'),
    coalesce(v_fields -> 'metadata', '{}'),
    (v_fields ->> 'expires_at')::timestamptz,
    now() + interval '60 seconds'
  )
  returning * into v_row;
  return jsonb_build_object('id', v_row."id", 'organization_id', v_row."organization_id", 'user_id', v_row."user_id", 'provider', v_row."provider", 'reference', v_row."reference", 'status', v_row."status", 'raw_status', v_row."raw_status", 'item_count', v_row."item_count", 'counts', v_row."counts", 'error', v_row."error", 'metadata', v_row."metadata", 'results_saved', v_row."results_saved", 'polls', v_row."polls", 'next_poll_at', v_row."next_poll_at", 'expires_at', v_row."expires_at", 'completed_at', v_row."completed_at", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.register_ai_sandbox (
  tenant     uuid,
  provider   text,
  sandbox_id text,
  fields     jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_row "better_supabase"."ai_sandboxes"%rowtype;
  v_fields jsonb := coalesce(register_ai_sandbox.fields, '{}');
begin
  insert into "better_supabase"."ai_sandboxes" as cur ("organization_id", "user_id", "chat_id", "provider", "sandbox_id", "container_id", "metadata", "idle_seconds", "expires_at")
  values (
    register_ai_sandbox.tenant,
    (v_fields ->> 'user_id')::uuid,
    (v_fields ->> 'chat_id')::uuid,
    register_ai_sandbox.provider,
    register_ai_sandbox.sandbox_id,
    v_fields ->> 'container_id',
    coalesce(v_fields -> 'metadata', '{}'),
    coalesce((v_fields ->> 'idle_seconds')::integer, 600),
    (v_fields ->> 'expires_at')::timestamptz
  )
  on conflict ("provider", "sandbox_id") do update set
    "container_id" = coalesce(excluded."container_id", cur."container_id"),
    "chat_id" = coalesce(excluded."chat_id", cur."chat_id"),
    "metadata" = cur."metadata" || excluded."metadata",
    "idle_seconds" = excluded."idle_seconds",
    "expires_at" = coalesce(excluded."expires_at", cur."expires_at"),
    "status" = 'running',
    "error" = null,
    "stopped_at" = null,
    "last_used_at" = now(),
    "updated_at" = now()
  where cur."organization_id" = excluded."organization_id"
  returning * into v_row;
  if not found then
    raise exception 'sandbox % belongs to another tenant', register_ai_sandbox.sandbox_id using errcode = '42501', hint = 'AI_SANDBOX_FORBIDDEN';
  end if;
  return jsonb_build_object('id', v_row."id", 'organization_id', v_row."organization_id", 'user_id', v_row."user_id", 'chat_id', v_row."chat_id", 'provider', v_row."provider", 'sandbox_id', v_row."sandbox_id", 'container_id', v_row."container_id", 'status', v_row."status", 'metadata', v_row."metadata", 'idle_seconds', v_row."idle_seconds", 'error', v_row."error", 'last_used_at', v_row."last_used_at", 'expires_at', v_row."expires_at", 'stopped_at', v_row."stopped_at", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.save_ai_batch_items (
  id    uuid,
  items jsonb
)
  RETURNS integer
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_tenant uuid;
  v_items jsonb := case when jsonb_typeof(save_ai_batch_items.items) = 'object' then save_ai_batch_items.items -> 'items' else save_ai_batch_items.items end;
  v_count integer;
begin
  select x."organization_id" into v_tenant from "better_supabase"."ai_batches" x where x."id" = save_ai_batch_items.id;
  if not found then
    raise exception 'batch % not found', save_ai_batch_items.id using errcode = 'P0002', hint = 'AI_BATCH_NOT_FOUND';
  end if;
  insert into "better_supabase"."ai_batch_items" ("batch_id", "request_id", "organization_id", "status", "output", "usage", "error")
  select save_ai_batch_items.id, item ->> 'request_id', v_tenant, item ->> 'status', item -> 'output', item -> 'usage', left(item ->> 'error', 4000)
  from jsonb_array_elements(case when jsonb_typeof(v_items) = 'array' then v_items else '[]' end) item
  on conflict ("batch_id", "request_id") do update set
    "status" = excluded."status",
    "output" = excluded."output",
    "usage" = excluded."usage",
    "error" = excluded."error";
  get diagnostics v_count = row_count;
  return v_count;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.save_ai_provider_key (
  tenant         uuid,
  provider       text,
  credential_ref jsonb,
  name           text    DEFAULT 'default'::text,
  settings       jsonb   DEFAULT '{}'::jsonb,
  enabled        boolean DEFAULT true
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_old jsonb;
  v_row "better_supabase"."ai_provider_keys"%rowtype;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', save_ai_provider_key.tenant, 'ai_chat.admin'), false)) then
    raise exception 'you may not manage provider keys here' using errcode = '42501', hint = 'AI_PROVIDER_KEY_FORBIDDEN';
  end if;
  select x."credential_ref" into v_old from "better_supabase"."ai_provider_keys" x
  where x."organization_id" = save_ai_provider_key.tenant and x."provider" = save_ai_provider_key.provider and x."name" = coalesce(save_ai_provider_key.name, 'default')
  for update;
  insert into "better_supabase"."ai_provider_keys" ("organization_id", "provider", "name", "credential_ref", "settings", "enabled", "created_by")
  values (save_ai_provider_key.tenant, save_ai_provider_key.provider, coalesce(save_ai_provider_key.name, 'default'), save_ai_provider_key.credential_ref, coalesce(save_ai_provider_key.settings, '{}'), coalesce(save_ai_provider_key.enabled, true), auth.uid())
  on conflict ("organization_id", "provider", "name") do update set
    "credential_ref" = excluded."credential_ref",
    "settings" = excluded."settings",
    "enabled" = excluded."enabled",
    "updated_at" = now()
  returning * into v_row;
  return jsonb_build_object('key', jsonb_build_object('id', v_row."id", 'organization_id', v_row."organization_id", 'provider', v_row."provider", 'name', v_row."name", 'credential_ref', v_row."credential_ref", 'settings', v_row."settings", 'enabled', v_row."enabled", 'created_by', v_row."created_by", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at"), 'replaced', v_old);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.touch_ai_sandbox (
  id uuid
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  update "better_supabase"."ai_sandboxes" x set "last_used_at" = now(), "updated_at" = now()
  where x."id" = touch_ai_sandbox.id and x."status" = 'running';
  return found;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.update_ai_batch (
  id     uuid,
  fields jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."ai_batches"%rowtype;
  v_fields jsonb := coalesce(update_ai_batch.fields, '{}');
begin
  update "better_supabase"."ai_batches" x set
    "status" = coalesce(v_fields ->> 'status', x."status"),
    "raw_status" = coalesce(v_fields ->> 'raw_status', x."raw_status"),
    "counts" = coalesce(v_fields -> 'counts', x."counts"),
    "error" = case when v_fields ? 'error' then left(v_fields ->> 'error', 4000) else x."error" end,
    "expires_at" = coalesce((v_fields ->> 'expires_at')::timestamptz, x."expires_at"),
    "results_saved" = coalesce((v_fields ->> 'results_saved')::boolean, x."results_saved"),
    "next_poll_at" = case when v_fields ? 'next_poll_at' then (v_fields ->> 'next_poll_at')::timestamptz else x."next_poll_at" end,
    "completed_at" = case when coalesce(v_fields ->> 'status', x."status") <> 'pending' then coalesce(x."completed_at", now()) else null end,
    "updated_at" = now()
  where x."id" = update_ai_batch.id
  returning * into v_row;
  if not found then
    raise exception 'batch % not found', update_ai_batch.id using errcode = 'P0002', hint = 'AI_BATCH_NOT_FOUND';
  end if;
  return jsonb_build_object('id', v_row."id", 'organization_id', v_row."organization_id", 'user_id', v_row."user_id", 'provider', v_row."provider", 'reference', v_row."reference", 'status', v_row."status", 'raw_status', v_row."raw_status", 'item_count', v_row."item_count", 'counts', v_row."counts", 'error', v_row."error", 'metadata', v_row."metadata", 'results_saved', v_row."results_saved", 'polls', v_row."polls", 'next_poll_at', v_row."next_poll_at", 'expires_at', v_row."expires_at", 'completed_at', v_row."completed_at", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at");
end;
$function$;

ALTER TABLE "better_supabase"."ai_batch_items"
  ADD CONSTRAINT "ai_batch_items_batch_id_fkey" FOREIGN KEY (batch_id) REFERENCES better_supabase.ai_batches(id) ON DELETE CASCADE;

ALTER TABLE "better_supabase"."ai_batches"
  ADD CONSTRAINT "ai_batches_user_id_fkey" FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;

ALTER TABLE "better_supabase"."ai_provider_keys"
  ADD CONSTRAINT "ai_provider_keys_created_by_fkey" FOREIGN KEY (created_by) REFERENCES auth.users(id) ON DELETE SET NULL;

ALTER TABLE "better_supabase"."ai_sandboxes"
  ADD CONSTRAINT "ai_sandboxes_user_id_fkey" FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;

CREATE INDEX ai_batch_items_tenant_idx ON better_supabase.ai_batch_items USING btree (organization_id);

CREATE INDEX ai_batches_due_idx ON better_supabase.ai_batches USING btree (next_poll_at)
  WHERE ((status = 'pending'::text) OR (NOT results_saved));

CREATE INDEX ai_batches_tenant_idx ON better_supabase.ai_batches USING btree (organization_id, created_at DESC);

CREATE INDEX ai_batches_user_idx ON better_supabase.ai_batches USING btree (user_id);

CREATE INDEX ai_cache_entries_expires_idx ON better_supabase.ai_cache_entries USING btree (expires_at);

CREATE INDEX ai_cache_entries_tenant_idx ON better_supabase.ai_cache_entries USING btree (organization_id);

CREATE INDEX ai_provider_keys_created_by_idx ON better_supabase.ai_provider_keys USING btree (created_by);

CREATE INDEX ai_sandboxes_chat_idx ON better_supabase.ai_sandboxes USING btree (chat_id);

CREATE INDEX ai_sandboxes_open_idx ON better_supabase.ai_sandboxes USING btree (last_used_at)
  WHERE (status <> 'stopped'::text);

CREATE INDEX ai_sandboxes_tenant_idx ON better_supabase.ai_sandboxes USING btree (organization_id);

CREATE INDEX ai_sandboxes_user_idx ON better_supabase.ai_sandboxes USING btree (user_id);

CREATE POLICY "ai_batch_items_read" ON "better_supabase"."ai_batch_items"
  FOR SELECT
  TO "authenticated"
  USING ((EXISTS ( SELECT 1
   FROM better_supabase.ai_batches y
  WHERE (y.id = ai_batch_items.batch_id))));

CREATE POLICY "ai_batches_read" ON "better_supabase"."ai_batches"
  FOR SELECT
  TO "authenticated"
  USING (((user_id = ( SELECT auth.uid() AS uid)) OR (organization_id IN ( SELECT better_supabase.tenant_ids_with('ai_chat.admin'::text) AS tenant_ids_with))));

CREATE POLICY "ai_provider_keys_read" ON "better_supabase"."ai_provider_keys"
  FOR SELECT
  TO "authenticated"
  USING ((organization_id IN ( SELECT better_supabase.tenant_ids_with('ai_chat.admin'::text) AS tenant_ids_with)));

CREATE POLICY "ai_sandboxes_read" ON "better_supabase"."ai_sandboxes"
  FOR SELECT
  TO "authenticated"
  USING (((user_id = ( SELECT auth.uid() AS uid)) OR (organization_id IN ( SELECT better_supabase.tenant_ids_with('ai_chat.admin'::text) AS tenant_ids_with))));

REVOKE ALL ON FUNCTION "api"."ai_cache_delete"(text, uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."ai_cache_delete"(text, uuid, text) TO "service_role";

REVOKE ALL ON FUNCTION "api"."ai_cache_get"(text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."ai_cache_get"(text) TO "service_role";

REVOKE ALL ON FUNCTION "api"."ai_cache_set"(text, jsonb, integer, uuid, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."ai_cache_set"(text, jsonb, integer, uuid, text, text) TO "service_role";

REVOKE ALL ON FUNCTION "api"."ai_provider_keys_for"(uuid, text[]) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."ai_provider_keys_for"(uuid, text[]) TO "service_role";

REVOKE ALL ON FUNCTION "api"."ai_sandbox_for"(uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."ai_sandbox_for"(uuid, text) TO "service_role";

REVOKE ALL ON FUNCTION "api"."delete_ai_provider_key"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."delete_ai_provider_key"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."delete_ai_provider_keys"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."delete_ai_provider_keys"(uuid) TO "service_role";

REVOKE ALL ON FUNCTION "api"."due_ai_batches"(integer, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."due_ai_batches"(integer, integer) TO "service_role";

REVOKE ALL ON FUNCTION "api"."finish_ai_sandbox_stop"(uuid, boolean, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."finish_ai_sandbox_stop"(uuid, boolean, text) TO "service_role";

REVOKE ALL ON FUNCTION "api"."get_ai_batch"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."get_ai_batch"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."idle_ai_sandboxes"(integer, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."idle_ai_sandboxes"(integer, integer) TO "service_role";

REVOKE ALL ON FUNCTION "api"."list_ai_batch_items"(uuid, text, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."list_ai_batch_items"(uuid, text, integer) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."list_ai_batches"(uuid, text, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."list_ai_batches"(uuid, text, integer) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."list_ai_provider_keys"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."list_ai_provider_keys"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."list_ai_sandboxes"(uuid, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."list_ai_sandboxes"(uuid, uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."purge_ai_cache"(integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."purge_ai_cache"(integer) TO "service_role";

REVOKE ALL ON FUNCTION "api"."record_ai_batch"(uuid, text, jsonb, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."record_ai_batch"(uuid, text, jsonb, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."register_ai_sandbox"(uuid, text, text, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."register_ai_sandbox"(uuid, text, text, jsonb) TO "service_role";

REVOKE ALL ON FUNCTION "api"."save_ai_batch_items"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."save_ai_batch_items"(uuid, jsonb) TO "service_role";

REVOKE ALL ON FUNCTION "api"."save_ai_provider_key"(uuid, text, jsonb, text, jsonb, boolean) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."save_ai_provider_key"(uuid, text, jsonb, text, jsonb, boolean) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."touch_ai_sandbox"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."touch_ai_sandbox"(uuid) TO "service_role";

REVOKE ALL ON FUNCTION "api"."update_ai_batch"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."update_ai_batch"(uuid, jsonb) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."ai_cache_delete"(text, uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."ai_cache_delete"(text, uuid, text) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."ai_cache_get"(text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."ai_cache_get"(text) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."ai_cache_set"(text, jsonb, integer, uuid, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."ai_cache_set"(text, jsonb, integer, uuid, text, text) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."ai_provider_keys_for"(uuid, text[]) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."ai_provider_keys_for"(uuid, text[]) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."ai_sandbox_for"(uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."ai_sandbox_for"(uuid, text) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."delete_ai_provider_key"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."delete_ai_provider_key"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."delete_ai_provider_keys"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."delete_ai_provider_keys"(uuid) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."due_ai_batches"(integer, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."due_ai_batches"(integer, integer) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."finish_ai_sandbox_stop"(uuid, boolean, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."finish_ai_sandbox_stop"(uuid, boolean, text) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."get_ai_batch"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."get_ai_batch"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."idle_ai_sandboxes"(integer, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."idle_ai_sandboxes"(integer, integer) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."list_ai_batch_items"(uuid, text, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."list_ai_batch_items"(uuid, text, integer) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."list_ai_batches"(uuid, text, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."list_ai_batches"(uuid, text, integer) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."list_ai_provider_keys"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."list_ai_provider_keys"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."list_ai_sandboxes"(uuid, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."list_ai_sandboxes"(uuid, uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."purge_ai_cache"(integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."purge_ai_cache"(integer) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."record_ai_batch"(uuid, text, jsonb, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."record_ai_batch"(uuid, text, jsonb, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."register_ai_sandbox"(uuid, text, text, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."register_ai_sandbox"(uuid, text, text, jsonb) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."save_ai_batch_items"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."save_ai_batch_items"(uuid, jsonb) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."save_ai_provider_key"(uuid, text, jsonb, text, jsonb, boolean) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."save_ai_provider_key"(uuid, text, jsonb, text, jsonb, boolean) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."touch_ai_sandbox"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."touch_ai_sandbox"(uuid) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."update_ai_batch"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."update_ai_batch"(uuid, jsonb) TO "service_role";

GRANT SELECT ON TABLE "better_supabase"."ai_batch_items" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."ai_batch_items" TO "service_role";

GRANT SELECT ON TABLE "better_supabase"."ai_batches" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."ai_batches" TO "service_role";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."ai_cache_entries" TO "service_role";

GRANT SELECT ON TABLE "better_supabase"."ai_provider_keys" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."ai_provider_keys" TO "service_role";

GRANT SELECT ON TABLE "better_supabase"."ai_sandboxes" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."ai_sandboxes" TO "service_role";
