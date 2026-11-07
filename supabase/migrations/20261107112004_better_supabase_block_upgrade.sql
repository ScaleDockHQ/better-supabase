-- better-supabase upgrade: steps that run before the schema diff.

-- deadlines: version 1 to 2. Rule set versions take groups, a counting block and meta, and rules move to the v2 grammar: each version 1 rule (anchor, offset) becomes a rule of its own group, and an approved version keeps its old hash in meta.previous_content_hash. Deadlines gain group_key (backfilled from rule_key), period, provisional, exception, review, basis, deadline and as_of; save_rule_version takes the content, and the per-rule unique constraint gives way to a unique index per group and period.
-- The SHA-256 content hash of a rule set version: its rules, groups,
-- counting block and meta.
create or replace function "better_supabase"."version_content_hash"(rules jsonb, groups jsonb, counting jsonb, meta jsonb)
returns text
language sql
immutable
set search_path = ''
as $$
  select encode(extensions.digest(convert_to(jsonb_build_object('rules', rules, 'groups', groups, 'counting', counting, 'meta', meta)::text, 'UTF8'), 'sha256'), 'hex')
$$;
revoke execute on function "better_supabase"."version_content_hash"(jsonb, jsonb, jsonb, jsonb) from public, anon, authenticated;

-- A rule of the version 1 shape (anchor, offset, requires) as a rule of
-- its own group: the offset counts from the anchor, or before it when it is
-- negative, and each required fact must be present.
create or replace function "better_supabase"."deadline_rule_from_v1"(rule jsonb)
returns jsonb
language sql
immutable
set search_path = ''
as $$
  select jsonb_build_object(
      'key', rule -> 'key',
      'group', rule -> 'key',
      'deadline', jsonb_build_object(
        'n', abs((rule #>> '{offset,amount}')::integer),
        'unit', rule #> '{offset,unit}',
        case when (rule #>> '{offset,amount}')::integer < 0 then 'before' else 'from' end, rule -> 'anchor'),
      'citation', rule -> 'citation')
    || case when rule ? 'title' then jsonb_build_object('title', rule -> 'title') else '{}'::jsonb end
    || case when rule ? 'adjust' then jsonb_build_object('adjust', rule -> 'adjust') else '{}'::jsonb end
    || coalesce((
      select jsonb_build_object('applies', jsonb_object_agg(r.name, 'present'))
      from jsonb_array_elements_text(case when jsonb_typeof(rule -> 'requires') = 'array' then rule -> 'requires' else '[]'::jsonb end) r(name)
      having count(*) > 0
    ), '{}'::jsonb)
$$;
revoke execute on function "better_supabase"."deadline_rule_from_v1"(jsonb) from public, anon, authenticated;

do $$
begin
  if to_regclass('"better_supabase"."deadline_rule_versions"') is null then
    return;
  end if;
  alter table "better_supabase"."deadline_rule_versions" add column if not exists "groups" jsonb not null default '[]'::jsonb;
  alter table "better_supabase"."deadline_rule_versions" add column if not exists "counting" jsonb;
  alter table "better_supabase"."deadline_rule_versions" add column if not exists "meta" jsonb;
  alter table "better_supabase"."deadlines" add column if not exists "group_key" text;
  alter table "better_supabase"."deadlines" add column if not exists "period" text check ("period" ~ '^[0-9]{4}-[0-9]{2}$');
  alter table "better_supabase"."deadlines" add column if not exists "provisional" boolean not null default false;
  alter table "better_supabase"."deadlines" add column if not exists "exception" jsonb;
  alter table "better_supabase"."deadlines" add column if not exists "review" jsonb not null default '[]'::jsonb;
  alter table "better_supabase"."deadlines" add column if not exists "basis" jsonb;
  alter table "better_supabase"."deadlines" add column if not exists "deadline" jsonb;
  alter table "better_supabase"."deadlines" add column if not exists "as_of" date not null default current_date;
  update "better_supabase"."deadlines" set "group_key" = "rule_key" where "group_key" is null;
  alter table "better_supabase"."deadlines" alter column "group_key" set not null;
  alter table "better_supabase"."deadlines" alter column "rule_key" drop not null;
  alter table "better_supabase"."deadlines" drop constraint if exists "deadlines_result_check";
  alter table "better_supabase"."deadlines" add constraint "deadlines_result_check" check ("result" in ('due', 'unknown', 'pending', 'undated', 'not_covered', 'not_applicable', 'not_required', 'barred'));
  alter table "better_supabase"."deadlines" drop constraint if exists "deadlines_period_due_check";
  alter table "better_supabase"."deadlines" add constraint "deadlines_period_due_check" check ("period" is null or "result" = 'due');
  alter table "better_supabase"."deadlines" drop constraint if exists "deadlines_subject_rule_key";

  alter table "better_supabase"."deadline_rule_versions" disable trigger bsb_deadlines_version_frozen;
  with converted as (
    select x."id" as id,
      (select jsonb_agg("better_supabase"."deadline_rule_from_v1"(r.value) order by r.ord) from jsonb_array_elements(x."rules") with ordinality r(value, ord)) as rules,
      (select jsonb_agg(jsonb_build_object('key', r.value -> 'key', 'citation', r.value -> 'citation') order by r.ord) from jsonb_array_elements(x."rules") with ordinality r(value, ord)) as groups,
      case when x."status" = 'approved'
        then coalesce(x."meta", '{}'::jsonb) || jsonb_build_object('previous_content_hash', x."content_hash")
        else x."meta" end as meta
    from "better_supabase"."deadline_rule_versions" x
    where exists (select 1 from jsonb_array_elements(x."rules") r(value) where r.value ? 'anchor')
  )
  update "better_supabase"."deadline_rule_versions" x set "rules" = c.rules, "groups" = c.groups, "meta" = c.meta,
    "content_hash" = case when x."status" = 'approved'
      then "better_supabase"."version_content_hash"(c.rules, c.groups, x."counting", c.meta) else x."content_hash" end
  from converted c where x."id" = c.id;
  alter table "better_supabase"."deadline_rule_versions" enable trigger bsb_deadlines_version_frozen;
end;
$$;

drop function if exists "better_supabase"."save_rule_version"(text, text, jsonb, date, text);
drop function if exists "better_supabase"."validate_deadline_rules"(jsonb);
