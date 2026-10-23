-- better-supabase upgrade: steps that run before the schema diff.

-- employees: version 1 to 2. With time-tracking, time entries gain employee_id, backfilled and kept current by triggers.
alter table "better_supabase"."time_entries" add column if not exists employee_id uuid references "better_supabase"."employees" ("id") on delete set null;
alter table "better_supabase"."time_entries" disable trigger bsb_time_entry_guard;
update "better_supabase"."time_entries" t set employee_id = x."id"
from "better_supabase"."employees" x
where x."tenant_id" = t."tenant_id" and x."user_id" = t."user_id"
  and t.employee_id is distinct from x."id";
alter table "better_supabase"."time_entries" enable trigger bsb_time_entry_guard;
