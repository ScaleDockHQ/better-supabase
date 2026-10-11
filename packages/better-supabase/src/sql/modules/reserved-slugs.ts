import type { ModuleDefinition } from "../module-types.ts";

import { sqlString } from "../../core/template.ts";
import { type ModuleContext } from "../context.ts";
import { SCHEMA } from "../shared.ts";

const RESERVED_SLUGS_SEED = `insert into better_supabase.reserved_slugs (slug, reason)
select value, 'system'
from unnest(array[
  'about', 'account', 'admin', 'api', 'app', 'assets', 'auth', 'billing', 'blog',
  'callback', 'cdn', 'dashboard', 'docs', 'help', 'invite', 'login', 'logout',
  'mail', 'new', 'oauth', 'onboarding', 'pricing', 'privacy', 'root', 'settings',
  'signin', 'signout', 'signup', 'static', 'status', 'support', 'system', 'terms',
  'www'
]) as value
on conflict (slug) do nothing;`;

const SLUG_PATTERN = "^[a-z0-9](?:[a-z0-9-]*[a-z0-9])?$";

/** `minLength` and `maxLength` of `sql.modules["reserved-slugs"].options`. */
function slugLengths(ctx: ModuleContext): {
  readonly min: number;
  readonly max: number;
} {
  const min = ctx.number("minLength", 1);
  const max = ctx.number("maxLength", 63);
  if (
    !Number.isInteger(min) ||
    !Number.isInteger(max) ||
    min < 1 ||
    max < min
  ) {
    throw new TypeError(
      "sql.modules.reserved-slugs.options.minLength and maxLength must be whole numbers with 1 <= minLength <= maxLength",
    );
  }
  return { min, max };
}

/** `sql.modules["reserved-slugs"].options.slugs`: the app's own words, such as its route names. */
function appSlugs(ctx: ModuleContext): string {
  const slugs = ctx.list("slugs", []);
  for (const slug of slugs) {
    if (!new RegExp(SLUG_PATTERN).test(slug) || slug.includes("--")) {
      throw new TypeError(
        `sql.modules.reserved-slugs.options.slugs: "${slug}" is not a slug (lowercase letters, digits and inner hyphens)`,
      );
    }
  }
  if (slugs.length === 0) return "";
  return `

-- sql.modules.reserved-slugs.options.slugs
insert into better_supabase.reserved_slugs (slug, reason)
select value, 'app'
from unnest(array[${slugs.map(sqlString).join(", ")}]) as value
on conflict (slug) do nothing;`;
}

export const RESERVED_SLUGS: ModuleDefinition = {
  name: "reserved-slugs",
  names: { tables: {}, options: ["maxLength", "minLength", "slugs"] },
  data: (ctx) => `${RESERVED_SLUGS_SEED}${appSlugs(ctx)}`,
  title: "Reserved slugs",
  description:
    "A slug format and length check and a list of reserved words (admin, api, www, ...), enforced by a trigger.",
  requires: [],
  target: "schema",
  build: (ctx) => {
    const { min, max } = slugLengths(ctx);
    return `${SCHEMA}

create table if not exists better_supabase.reserved_slugs (
  slug text primary key,
  reason text
);
alter table better_supabase.reserved_slugs enable row level security;
-- enforce_slug runs as the writer, service_role included, and reads this list.
grant select on better_supabase.reserved_slugs to anon, authenticated, service_role;
drop policy if exists bs_reserved_slugs_read on better_supabase.reserved_slugs;
create policy bs_reserved_slugs_read on better_supabase.reserved_slugs for select using (true);

-- 'invalid' for a malformed slug or one outside ${String(min)} to ${String(max)} characters
-- (sql.modules.reserved-slugs.options.minLength and maxLength), 'reserved', or null.
create or replace function better_supabase.slug_problem(slug text)
returns text
language sql
stable
set search_path = ''
as $$
  select case
    when slug is null then null
    when slug !~ ${sqlString(SLUG_PATTERN)} then 'invalid'
    when slug ~ '--' then 'invalid'
    when length(slug) < ${String(min)} or length(slug) > ${String(max)} then 'invalid'
    when exists (select 1 from better_supabase.reserved_slugs r where r.slug = slug_problem.slug) then 'reserved'
  end
$$;

create or replace function better_supabase.enforce_slug()
returns trigger
language plpgsql
set search_path = ''
as $$
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
$$;

-- select better_supabase.track_slug('public.organizations');
create or replace function better_supabase.track_slug(target regclass, column_name text default 'slug')
returns void
language plpgsql
set search_path = ''
as $$
begin
  execute format('drop trigger if exists bs_slug on %s', target);
  execute format(
    'create trigger bs_slug before insert or update of %I on %s for each row execute function better_supabase.enforce_slug(%L)',
    column_name,
    target,
    column_name
  );
end;
$$;

-- enforce_slug runs as the writer, so the check stays callable by authenticated.
revoke execute on function better_supabase.slug_problem(text) from public, anon;
grant execute on function better_supabase.slug_problem(text) to authenticated, service_role;
revoke execute on function better_supabase.track_slug(regclass, text) from public, anon, authenticated;`;
  },
};
