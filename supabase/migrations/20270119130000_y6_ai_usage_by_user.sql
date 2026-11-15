SET local check_function_bodies = off;

CREATE OR REPLACE FUNCTION api.ai_usage_by_user (
  tenant uuid,
  since  timestamp with time zone DEFAULT NULL::timestamp WITH time zone,
  until  timestamp with time zone DEFAULT NULL::timestamp WITH time zone,
  size   integer                  DEFAULT 50
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."ai_usage_by_user"($1, $2, $3, $4) $function$;

CREATE OR REPLACE FUNCTION better_supabase.ai_usage_by_user (
  tenant uuid,
  since  timestamp with time zone DEFAULT NULL::timestamp WITH time zone,
  until  timestamp with time zone DEFAULT NULL::timestamp WITH time zone,
  size   integer                  DEFAULT 50
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', ai_usage_by_user.tenant, 'ai_chat.manage'), false)) then
    raise exception 'You may not read usage here' using errcode = '42501', hint = 'AI_CHAT_FORBIDDEN';
  end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object(
      'user_id', u.user_id,
      'runs', u.runs,
      'failed', u.failed,
      'input_tokens', u.input_tokens,
      'output_tokens', u.output_tokens,
      'cached_input_tokens', u.cached_input_tokens,
      'cost_micro_usd', u.cost_micro_usd,
      'last_run_at', u.last_run_at
    ) order by u.cost_micro_usd desc, u.runs desc, u.user_id), '[]'::jsonb)
    from (
      select
        x."owner_id" as user_id,
        count(*) as runs,
        count(*) filter (where x."status" = 'failed') as failed,
        coalesce(sum(case when jsonb_typeof(x."usage" -> 'inputTokens') = 'number' then (x."usage" ->> 'inputTokens')::numeric end), 0)::bigint as input_tokens,
        coalesce(sum(case when jsonb_typeof(x."usage" -> 'outputTokens') = 'number' then (x."usage" ->> 'outputTokens')::numeric end), 0)::bigint as output_tokens,
        coalesce(sum(case when jsonb_typeof(x."usage" -> 'cachedInputTokens') = 'number' then (x."usage" ->> 'cachedInputTokens')::numeric end), 0)::bigint as cached_input_tokens,
        coalesce(sum(x."cost_micro_usd"), 0)::bigint as cost_micro_usd,
        max(x."started_at") as last_run_at
      from "better_supabase"."ai_runs" x
      join "better_supabase"."ai_chats" c on c."id" = x."chat_id"
      where c."tenant_id" = ai_usage_by_user.tenant
        and (ai_usage_by_user.since is null or x."started_at" >= ai_usage_by_user.since)
        and (ai_usage_by_user.until is null or x."started_at" < ai_usage_by_user.until)
      group by x."owner_id"
      order by cost_micro_usd desc, runs desc, user_id
      limit least(greatest(coalesce(ai_usage_by_user.size, 50), 1), 500)
    ) u
  );
end;
$function$;

REVOKE ALL ON FUNCTION "api"."ai_usage_by_user"(uuid, timestamp WITH time zone, timestamp WITH time zone, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."ai_usage_by_user"(uuid, timestamp WITH time zone, timestamp WITH time zone, integer) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."ai_usage_by_user"(uuid, timestamp WITH time zone, timestamp WITH time zone, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."ai_usage_by_user"(uuid, timestamp WITH time zone, timestamp WITH time zone, integer) TO "authenticated", "service_role";
