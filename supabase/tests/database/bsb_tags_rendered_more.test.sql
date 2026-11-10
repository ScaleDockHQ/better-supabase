-- The SQL that the @bsb rpc, copy and rollup tags render for a table (ADR 0661), applied and called.
-- tests/sql/tag-statements.test.ts renders the same blocks and compares them with this file's
-- text, so the two cannot drift.
begin;
select plan(9);
create table public.scale_projects (id uuid primary key default gen_random_uuid(), tenant_id uuid not null, task_count integer not null default 0);
create table public.scale_tasks (id uuid primary key default gen_random_uuid(), tenant_id uuid not null, project_id uuid not null references public.scale_projects (id), title text not null, hours numeric not null default 0);
-- @bsb-tag rpc begin
-- The rows of public.scale_tasks for up to 500 ids, in the order of the ids; row security decides the rows.
create or replace function "public"."get_scale_tasks"(ids uuid[])
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'title', x."title") order by i.n), '[]'::jsonb)
  from unnest(get_scale_tasks.ids[1:500]) with ordinality as i(id, n)
  join "public"."scale_tasks" x on x."id" = i.id
$$;
revoke execute on function "public"."get_scale_tasks"(uuid[]) from public;
grant execute on function "public"."get_scale_tasks"(uuid[]) to authenticated, service_role;
-- @bsb-tag rpc end
-- @bsb-tag copy begin
-- A copy of one row of public.scale_tasks; row security decides what is read and what may be inserted.
create or replace function "public"."copy_scale_tasks"(source uuid)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "public"."scale_tasks";
begin
  insert into "public"."scale_tasks" ("tenant_id", "project_id", "title", "hours")
  select x."tenant_id", x."project_id", x."title" || ' (copy)', x."hours"
  from "public"."scale_tasks" x
  where x."id" = copy_scale_tasks.source
  returning * into v_row;
  if not found then
    raise exception 'scale_tasks not found' using errcode = 'P0002';
  end if;
  return to_jsonb(v_row);
end;
$$;
revoke execute on function "public"."copy_scale_tasks"(uuid) from public;
grant execute on function "public"."copy_scale_tasks"(uuid) to authenticated, service_role;
-- @bsb-tag copy end
-- @bsb-tag rollup begin
-- Keeps public.scale_projects.task_count equal to the number of rows of public.scale_tasks by project_id. Backfill the column once when you turn this on.
create or replace function "public"."bsb_rollup_scale_tasks_task_count"()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    update "public"."scale_projects" set "task_count" = "task_count" + 1 where "id" = new."project_id";
    return new;
  elsif tg_op = 'DELETE' then
    update "public"."scale_projects" set "task_count" = "task_count" - 1 where "id" = old."project_id";
    return old;
  end if;
  if old."project_id" is distinct from new."project_id" then
    update "public"."scale_projects" set "task_count" = "task_count" - 1 where "id" = old."project_id";
    update "public"."scale_projects" set "task_count" = "task_count" + 1 where "id" = new."project_id";
  end if;
  return new;
end;
$$;
revoke execute on function "public"."bsb_rollup_scale_tasks_task_count"() from public, anon, authenticated;
create trigger "bsb_rollup_scale_tasks_task_count"
  after insert or update or delete on "public"."scale_tasks"
  for each row execute function "public"."bsb_rollup_scale_tasks_task_count"();
-- @bsb-tag rollup end
insert into public.scale_projects (id, tenant_id) values
  ('00000000-0000-4000-8000-0000000000a1', '00000000-0000-4000-8000-000000000001'),
  ('00000000-0000-4000-8000-0000000000a2', '00000000-0000-4000-8000-000000000001');
insert into public.scale_tasks (id, tenant_id, project_id, title, hours) values
  ('00000000-0000-4000-8000-0000000000b1', '00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-0000000000a1', 'One', 1),
  ('00000000-0000-4000-8000-0000000000b2', '00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-0000000000a1', 'Two', 2),
  ('00000000-0000-4000-8000-0000000000b3', '00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-0000000000a1', 'Three', 3);
select is((select task_count from public.scale_projects where id = '00000000-0000-4000-8000-0000000000a1'), 3, 'the rollup counts inserted rows');
update public.scale_tasks set project_id = '00000000-0000-4000-8000-0000000000a2' where id = '00000000-0000-4000-8000-0000000000b3';
select is((select task_count from public.scale_projects where id = '00000000-0000-4000-8000-0000000000a1'), 2, 'a moved row leaves its old parent');
select is((select task_count from public.scale_projects where id = '00000000-0000-4000-8000-0000000000a2'), 1, 'a moved row joins its new parent');
delete from public.scale_tasks where id = '00000000-0000-4000-8000-0000000000b2';
select is((select task_count from public.scale_projects where id = '00000000-0000-4000-8000-0000000000a1'), 1, 'a deleted row is subtracted');
select is(public.get_scale_tasks(array['00000000-0000-4000-8000-0000000000b3', '00000000-0000-4000-8000-0000000000b1']::uuid[]) -> 0 ->> 'title', 'Three', 'rpc returns rows in the order of the ids');
select is(jsonb_array_length(public.get_scale_tasks(array['00000000-0000-4000-8000-0000000000b1', '00000000-0000-4000-8000-0000000000ff']::uuid[])), 1, 'rpc skips ids that match no row');
select is(public.get_scale_tasks(array['00000000-0000-4000-8000-0000000000b1']::uuid[]) -> 0 ->> 'hours', null, 'rpc returns only the listed columns');
select is(public.copy_scale_tasks('00000000-0000-4000-8000-0000000000b1') ->> 'title', 'One (copy)', 'copy writes the row with the suffix');
select is((select task_count from public.scale_projects where id = '00000000-0000-4000-8000-0000000000a1'), 2, 'a copied row is counted');
select * from finish();
rollback;
