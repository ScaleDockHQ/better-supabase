import type { BlockSqlContext, BlockSqlNames } from "../context.ts";
import type { BlockSqlDefinition } from "../module-types.ts";

import { sqlIdent, sqlString } from "../../core/template.ts";
import { raise, schemaPreamble } from "../shared.ts";

const NAMES: BlockSqlNames = {
  options: ["maxLength", "minLength", "slugs"],
  tables: {
    slugs: {
      name: "reserved_slugs",
      app: { writes: false },
      columns: { slug: "slug", reason: "reason" },
      optional: ["reason"],
    },
  },
};

/**
 * `insert ... select <values>` of reserved words with `reason`, skipping words
 * already there. Without a reason column only the words go in.
 */
function insertSlugs(
  ctx: BlockSqlContext,
  values: string,
  reason: string,
): string {
  const slug = ctx.col("slugs", "slug");
  const withReason = ctx.has("slugs", "reason");

  return `insert into ${ctx.table("slugs")} (${slug}${withReason ? `, ${ctx.col("slugs", "reason")}` : ""})
select value${withReason ? `, ${reason}` : ""}
from unnest(array[${values}]) as value
on conflict (${slug}) do nothing;`;
}

const SYSTEM_SLUGS = `
  'about', 'account', 'admin', 'api', 'app', 'assets', 'auth', 'billing', 'blog',
  'callback', 'cdn', 'dashboard', 'docs', 'help', 'invite', 'login', 'logout',
  'mail', 'new', 'oauth', 'onboarding', 'pricing', 'privacy', 'root', 'settings',
  'signin', 'signout', 'signup', 'static', 'status', 'support', 'system', 'terms',
  'www'
`;

const SLUG_PATTERN = "^[a-z0-9](?:[a-z0-9-]*[a-z0-9])?$";

/** `minLength` and `maxLength` of `blocks["reserved-slugs"].options`. */
function slugLengths(ctx: BlockSqlContext): {
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
      "blocks.reserved-slugs.options.minLength and maxLength must be whole numbers with 1 <= minLength <= maxLength",
    );
  }

  return { min, max };
}

/**
 * `blocks["reserved-slugs"].options.slugs`: the app's own words, such as its
 * route names.
 */
function appSlugs(ctx: BlockSqlContext): string {
  const slugs = ctx.list("slugs", []);

  for (const slug of slugs) {
    if (!new RegExp(SLUG_PATTERN).test(slug) || slug.includes("--")) {
      throw new TypeError(
        `blocks.reserved-slugs.options.slugs: "${slug}" is not a slug (lowercase letters, digits and inner hyphens)`,
      );
    }
  }

  if (slugs.length === 0) {
    return "";
  }

  return `

-- blocks.reserved-slugs.options.slugs
${insertSlugs(ctx, slugs.map(sqlString).join(", "), "'app'")}`;
}

export const RESERVED_SLUGS: BlockSqlDefinition = {
  name: "reserved-slugs",
  names: NAMES,
  data: (ctx) =>
    `${insertSlugs(ctx, SYSTEM_SLUGS, "'system'")}${appSlugs(ctx)}`,
  title: "Reserved slugs",
  description:
    "A slug format and length check and a list of reserved words (admin, api, www, ...), enforced by a trigger.",
  requires: [],
  target: "schema",
  build: (ctx) => {
    const { min, max } = slugLengths(ctx);
    const slugs = ctx.table("slugs");
    const slug = ctx.col("slugs", "slug");
    const name = ctx.tableName("slugs").name;

    // Over the app's table the module's primary key isn't there.
    const unique = ctx.owns("slugs")
      ? ""
      : `\ncreate unique index if not exists ${sqlIdent(`bsb_${name}_slug_key`)} on ${slugs} (${slug});`;

    const read = sqlIdent(`bsb_${name}_read`);

    return `${schemaPreamble(ctx)}

create table if not exists ${slugs} (
  ${slug} text primary key${ctx.has("slugs", "reason") ? `,\n  ${ctx.col("slugs", "reason")} text` : ""}
);${unique}
alter table ${slugs} enable row level security;
-- enforce_slug runs as the writer, service_role included, and reads this list.
grant select on ${slugs} to anon, authenticated, service_role;
drop policy if exists ${read} on ${slugs};
create policy ${read} on ${slugs} for select to anon, authenticated, service_role using (true);

-- 'invalid' for a malformed slug or one outside ${String(min)} to ${String(max)} characters
-- (blocks.reserved-slugs.options.minLength and maxLength), 'reserved', or null.
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
    when exists (select 1 from ${slugs} r where r.${slug} = slug_problem.slug) then 'reserved'
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
    ${raise(`Invalid slug "%"`, "23514", "SLUG_INVALID", "value")}
  elsif problem = 'reserved' then
    ${raise(`The slug "%" is reserved`, "23514", "SLUG_RESERVED", "value")}
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
  execute format('drop trigger if exists bsb_slug on %s', target);
  execute format(
    'create trigger bsb_slug before insert or update of %I on %s for each row execute function better_supabase.enforce_slug(%L)',
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
