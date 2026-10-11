import type { SqlModule } from "../module-types.ts";

import { EQUIVALENT_TRIGGERS, SCHEMA } from "../shared.ts";

export const UPDATED_AT: SqlModule = {
  name: "updated-at",
  title: "updated_at triggers",
  description: "Keeps an updated_at column current on every update.",
  requires: [],
  target: "schema",
  sql: `${SCHEMA}

create or replace function better_supabase.set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  -- The default column is assigned directly; jsonb_populate_record copies the
  -- whole row, so it only serves other column names.
  if tg_nargs = 0 or tg_argv[0] = 'updated_at' then
    new.updated_at := now();
  else
    new := jsonb_populate_record(new, jsonb_build_object(tg_argv[0], now()));
  end if;
  return new;
end;
$$;

${EQUIVALENT_TRIGGERS}

drop function if exists better_supabase.track_updated_at(regclass, text);

-- select better_supabase.track_updated_at('public.customers');
-- replace_trigger => true drops another trigger that sets updated_at (moddatetime, touch_*).
create or replace function better_supabase.track_updated_at(
  target regclass,
  column_name text default 'updated_at',
  replace_trigger boolean default false
)
returns void
language plpgsql
set search_path = ''
as $$
begin
  perform better_supabase.replace_equivalent_triggers(
    target, 'bs_updated_at', 'updated_at|moddatetime|touch', replace_trigger
  );
  execute format('drop trigger if exists bs_updated_at on %s', target);
  execute format(
    'create trigger bs_updated_at before update on %s for each row execute function better_supabase.set_updated_at(%L)',
    target,
    column_name
  );
end;
$$;

revoke execute on function better_supabase.track_updated_at(regclass, text, boolean) from public, anon, authenticated;`,
};
