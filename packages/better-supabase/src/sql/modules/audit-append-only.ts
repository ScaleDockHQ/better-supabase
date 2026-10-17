import type { ModuleContext } from "../context.ts";

import { sqlString } from "../../core/template.ts";

/** The triggers that keep audit log entries append-only, or drops them when `appendOnly` is off. */
export function appendOnly(ctx: ModuleContext): string {
  const log = ctx.table("log");
  const trigger = ctx.trigger("audit_append_only");
  const truncate = ctx.trigger("audit_no_truncate");

  if (!ctx.flag("appendOnly", ctx.manages)) {
    return `drop trigger if exists ${trigger} on ${log};
drop trigger if exists ${truncate} on ${log};`;
  }

  const purge = sqlString(
    `better_supabase.purge_audit_log(interval, integer, ${ctx.idType}, boolean)`,
  );

  return `-- Entries are append-only. purge_audit_log deletes old ones: it runs as its
-- owner and sets better_supabase.audit_purge, and a role that only sets the
-- setting is not the owner.
create or replace function better_supabase.audit_append_only()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  -- The setting first: the owner lookup runs only for a purge.
  if tg_op = 'DELETE' and current_setting('better_supabase.audit_purge', true) = 'on' then
    if current_user = (
      select r.rolname from pg_catalog.pg_proc p
      join pg_catalog.pg_roles r on r.oid = p.proowner
      where p.oid = to_regprocedure(${purge})
    ) then
      return old;
    end if;
  end if;
  raise exception 'audit log entries are append-only'
    using errcode = '42501', hint = 'Delete old entries with better_supabase.purge_audit_log()';
end;
$$;
revoke execute on function better_supabase.audit_append_only() from public, anon, authenticated;
drop trigger if exists ${trigger} on ${log};
create trigger ${trigger} before update or delete on ${log}
  for each row execute function better_supabase.audit_append_only();
drop trigger if exists ${truncate} on ${log};
create trigger ${truncate} before truncate on ${log}
  for each statement execute function better_supabase.audit_append_only();`;
}
