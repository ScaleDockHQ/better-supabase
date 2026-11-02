import type { BlockSqlContext } from "../context.ts";

import { serviceGrant } from "../shared.ts";

/**
 * The semaphore functions of the workflows module: a key's slots, held until
 * released or expired.
 */
export function semaphoreSql(ctx: BlockSqlContext): string {
  const fn = (name: string): string => ctx.fn(name);
  const m = ctx.table("semaphores");
  const cm = (column: string): string => ctx.col("semaphores", column);

  return `-- Takes one of max slots of key for holder until it releases or ttl passes.
-- true when holder holds a slot (again, for a holder that already held one).
create or replace function ${fn("acquire_workflow_semaphore")}(key text, holder text, max integer, ttl interval default '5 minutes')
returns boolean
language plpgsql
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_held integer;
begin
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext('workflow_semaphore'), pg_catalog.hashtext(key));
  delete from ${m} x where x.${cm("key")} = key and x.${cm("expiresAt")} < now();
  update ${m} x set ${cm("expiresAt")} = now() + coalesce(ttl, interval '5 minutes')
  where x.${cm("key")} = key and x.${cm("holder")} = holder;
  if found then
    return true;
  end if;
  select count(*) into v_held from ${m} x where x.${cm("key")} = key;
  if v_held >= greatest(coalesce(max, 1), 1) then
    return false;
  end if;
  insert into ${m} (${cm("key")}, ${cm("holder")}, ${cm("expiresAt")})
  values (key, holder, now() + coalesce(ttl, interval '5 minutes'));
  return true;
end;
$$;
${serviceGrant(`${fn("acquire_workflow_semaphore")}(text, text, integer, interval)`)}

create or replace function ${fn("release_workflow_semaphore")}(key text, holder text)
returns boolean
language plpgsql
set search_path = ''
as $$
#variable_conflict use_variable
begin
  delete from ${m} x where x.${cm("key")} = key and x.${cm("holder")} = holder;
  return found;
end;
$$;
${serviceGrant(`${fn("release_workflow_semaphore")}(text, text)`)}`;
}
