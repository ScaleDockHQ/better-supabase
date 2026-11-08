-- better-supabase upgrade: steps that run before the schema diff.

-- teams: version 2 to 3. The inbox's own team tables move into teams and team_members, and inbox conversations point at teams.
do $shared_teams$
declare
  legacy record;
begin
  if to_regclass('better_supabase.inbox_teams') is null then
    return;
  end if;
  insert into "better_supabase"."teams" ("id", "tenant_id", "name", "slug")
  select "id", "tenant_id", "name",
    trim(both '-' from regexp_replace(lower("name"), '[^a-z0-9]+', '-', 'g'))
  from "better_supabase"."inbox_teams"
  on conflict do nothing;
  insert into "better_supabase"."team_members" ("team_id", "user_id", "tenant_id")
  select m."team_id", m."user_id", t."tenant_id"
  from "better_supabase"."inbox_team_members" m
  join "better_supabase"."inbox_teams" t on t."id" = m."team_id"
  on conflict do nothing;
  for legacy in
    select con.conname as name, con.conrelid::regclass as rel
    from pg_catalog.pg_constraint con
    where con.confrelid = 'better_supabase.inbox_teams'::regclass
  loop
    execute format('alter table %s drop constraint %I', legacy.rel, legacy.name);
  end loop;
  drop table "better_supabase"."inbox_team_members";
  drop table "better_supabase"."inbox_teams";
end
$shared_teams$;
alter table "better_supabase"."inbox_conversations"
  drop constraint if exists conversations_team_fkey;
