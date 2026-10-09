import type { ModuleContext, ModuleNames } from "../context.ts";
import type { ModuleDefinition } from "../registry.ts";

import { sqlIdent, sqlString } from "../../core/template.ts";
import {
  EQUIVALENT_TRIGGERS,
  schemaPreamble,
  SERVICE_CALLER,
} from "../shared.ts";

const NAMES: ModuleNames = {
  options: [
    "columnGrants",
    "extraColumns",
    "metadata",
    "mirrorEmail",
    "readPolicy",
    "reservedUsernames",
    "serviceColumns",
    "splitName",
    "syncTrigger",
    "updatable",
    "username",
    "usernameFrom",
    "usernameMaxLength",
    "usernameMinLength",
  ],
  tables: {
    profiles: {
      name: "profiles",
      lifecycle: { user: "key" },
      columns: {
        key: "id",
        email: "email",
        username: "username",
        fullName: "full_name",
        firstName: "first_name",
        lastName: "last_name",
        avatar: "avatar_url",
        avatarPath: "avatar_path",
        activeTenant: "active_organization_id",
        activeTeam: "active_team_id",
        onboarding: "onboarding",
        disabledAt: "disabled_at",
        createdAt: "created_at",
        updatedAt: "updated_at",
      },
      optional: [
        "email",
        "username",
        "fullName",
        "firstName",
        "lastName",
        "avatar",
        "avatarPath",
        "activeTenant",
        "activeTeam",
        "onboarding",
        "disabledAt",
        "createdAt",
        "updatedAt",
      ],
    },
  },
  hooks: ["after_profile_sync"],
};

/** The metadata keys each column reads by default, first match wins. */
const DEFAULT_METADATA: readonly (readonly [string, readonly string[]])[] = [
  ["fullName", ["full_name", "name"]],
  ["firstName", ["first_name", "given_name"]],
  ["lastName", ["last_name", "family_name"]],
  ["avatar", ["avatar_url", "picture"]],
];

export function hasAvatarPath(ctx: ModuleContext): boolean {
  return (
    ctx.has("profiles", "avatarPath") &&
    (ctx.manages || ctx.config.columns["profiles"]?.["avatarPath"] != null)
  );
}

const USERNAME_SOURCES = ["user_name", "preferred_username", "username"];

const IDENT = /^[a-z_][a-z0-9_]*$/;
const SQL_TYPE = /^[a-z][a-z0-9_ (),.'[\]-]*$/i;

const fail = (code: string, message: string, errcode = "42501"): string =>
  `raise exception '${message}' using errcode = '${errcode}', hint = '${code}';`;

function column(where: string, name: string): string {
  if (!IDENT.test(name) || name.length > 63) {
    throw new TypeError(`${where}: "${name}" is not a valid column name`);
  }
  return sqlIdent(name);
}

function record(
  ctx: ModuleContext,
  name: string,
): Readonly<Record<string, unknown>> | undefined {
  const value = ctx.option(name);
  if (value === undefined) return undefined;
  if (typeof value !== "object" || value === null || Array.isArray(value)) {
    throw new TypeError(
      `sql.modules.profiles.options.${name} must be an object`,
    );
  }
  return Object.fromEntries(Object.entries(value));
}

/** `extraColumns`: column name to SQL type, created on a managed table. */
function extraColumns(
  ctx: ModuleContext,
): readonly (readonly [string, string])[] {
  return Object.entries(record(ctx, "extraColumns") ?? {}).map(
    ([name, type]) => {
      if (
        typeof type !== "string" ||
        !SQL_TYPE.test(type) ||
        type.includes("--")
      ) {
        throw new TypeError(
          `sql.modules.profiles.options.extraColumns.${name} must be a SQL type such as "text not null default 'en'"`,
        );
      }
      return [column("sql.modules.profiles.options.extraColumns", name), type];
    },
  );
}

/** Column to the metadata keys it reads: `options.metadata` or the defaults. */
function metadataColumns(ctx: ModuleContext): Map<string, string[]> {
  const map = new Map<string, string[]>();
  const configured = record(ctx, "metadata");
  if (configured) {
    for (const [key, target] of Object.entries(configured)) {
      if (typeof target !== "string") {
        throw new TypeError(
          `sql.modules.profiles.options.metadata.${key} must be a column name`,
        );
      }
      const name = column("sql.modules.profiles.options.metadata", target);
      if (hasAvatarPath(ctx) && name === ctx.col("profiles", "avatarPath")) {
        throw new TypeError(
          `sql.modules.profiles.options.metadata.${key}: ${target} holds a Storage object path the app sets, so auth metadata never writes it`,
        );
      }
      map.set(name, [...(map.get(name) ?? []), key]);
    }
    return map;
  }
  for (const [logical, keys] of DEFAULT_METADATA) {
    if (ctx.has("profiles", logical)) {
      map.set(ctx.col("profiles", logical), [...keys]);
    }
  }
  return map;
}

const fromMeta = (keys: readonly string[]): string =>
  keys.length === 0
    ? "null"
    : `nullif(btrim(coalesce(${keys.map((key) => `meta ->> ${sqlString(key)}`).join(", ")})), '')`;

/** Column to the SQL expression `sync_profile` inserts. */
function syncValues(ctx: ModuleContext): Map<string, string> {
  const values = new Map<string, string>();
  const has = (logical: string) => ctx.has("profiles", logical);
  const col = (logical: string) => ctx.col("profiles", logical);
  const meta = metadataColumns(ctx);
  for (const [name, keys] of meta) values.set(name, fromMeta(keys));
  if (has("fullName") && values.has(col("fullName"))) {
    const first = has("firstName") ? (meta.get(col("firstName")) ?? []) : [];
    const last = has("lastName") ? (meta.get(col("lastName")) ?? []) : [];
    values.set(
      col("fullName"),
      `coalesce(${values.get(col("fullName"))}, nullif(concat_ws(' ', ${fromMeta(first)}, ${fromMeta(last)}), ''))`,
    );
    if (ctx.flag("splitName", true)) {
      const full =
        "nullif(btrim(coalesce(meta ->> 'full_name', meta ->> 'name')), '')";
      if (has("firstName")) {
        values.set(
          col("firstName"),
          `coalesce(${values.get(col("firstName")) ?? "null"}, nullif(split_part(${full}, ' ', 1), ''))`,
        );
      }
      if (has("lastName")) {
        values.set(
          col("lastName"),
          `coalesce(${values.get(col("lastName")) ?? "null"}, nullif(btrim(substr(${full}, length(split_part(${full}, ' ', 1)) + 1)), ''))`,
        );
      }
    }
  }
  if (has("email")) values.set(col("email"), "u.email");
  if (has("username") && ctx.flag("username", true)) {
    values.set(
      col("username"),
      `${ctx.fn("allocate_username")}(coalesce(${usernameSource(ctx, values)}, split_part(u.email, '@', 1)), user_id)`,
    );
  }
  return values;
}

const SEPARATOR = /^[a-z0-9_.-]{0,3}$/;

interface UsernamePart {
  readonly keys: readonly string[];
  readonly kind: "names" | "columns";
  readonly separator: string;
}

/** The `{ names | columns, separator }` entries of `usernameFrom`; strings are single metadata keys. */
function usernameParts(ctx: ModuleContext): readonly (string | UsernamePart)[] {
  const configured = ctx.option("usernameFrom") ?? USERNAME_SOURCES;
  const where = "sql.modules.profiles.options.usernameFrom";
  if (!Array.isArray(configured)) {
    throw new TypeError(`${where} must be a list`);
  }
  return configured.map((entry: unknown): string | UsernamePart => {
    if (typeof entry === "string") return entry;
    const joined =
      typeof entry === "object" && entry !== null
        ? {
            names: "names" in entry ? entry.names : undefined,
            columns: "columns" in entry ? entry.columns : undefined,
            separator: "separator" in entry ? entry.separator : undefined,
          }
        : {};
    const kind = joined.columns === undefined ? "names" : "columns";
    const keys: unknown = joined[kind];
    if (
      !Array.isArray(keys) ||
      keys.length === 0 ||
      !keys.every((key: unknown) => typeof key === "string")
    ) {
      throw new TypeError(
        `${where} entries are metadata keys, { names: [keys], separator } or { columns: [profile columns], separator }`,
      );
    }
    const separator: unknown = joined.separator ?? "_";
    if (typeof separator !== "string" || !SEPARATOR.test(separator)) {
      throw new TypeError(
        `${where}: the separator must be up to 3 of a-z, 0-9, _, . or -`,
      );
    }
    return {
      keys: keys.filter((key: unknown) => typeof key === "string"),
      kind,
      separator,
    };
  });
}

/**
 * The characters a username keeps besides letters, digits and `_`: the `.`
 * and `-` of the `usernameFrom` separators, so `ada.lovelace` stays as it is.
 */
function usernameExtras(ctx: ModuleContext): string {
  const extras = new Set(
    usernameParts(ctx)
      .flatMap((part) =>
        typeof part === "string" ? [] : part.separator.split(""),
      )
      .filter((char) => char === "." || char === "-"),
  );
  return `${extras.has(".") ? "." : ""}${extras.has("-") ? "-" : ""}`;
}

/**
 * `usernameFrom`: metadata keys, first match wins, or entries that join
 * several values when all of them are set: `{ names, separator }` joins
 * metadata keys (`first_name` and `last_name` into `ada_lovelace`), and
 * `{ columns, separator }` joins the values `sync_profile` writes to those
 * profile columns, after `metadata` and `splitName`.
 */
function usernameSource(
  ctx: ModuleContext,
  values: ReadonlyMap<string, string>,
): string {
  const parts = usernameParts(ctx);
  if (parts.every((part) => typeof part === "string")) {
    return fromMeta(parts);
  }
  const where = "sql.modules.profiles.options.usernameFrom";
  const expressions = parts.map((part) => {
    if (typeof part === "string") return fromMeta([part]);
    const keys = part.keys.map((key) => {
      if (part.kind === "names") return fromMeta([key]);
      const value = values.get(column(`${where}.columns`, key));
      if (value === undefined) {
        throw new TypeError(
          `${where}: "${key}" is not a profile column sync_profile fills (the metadata columns and email)`,
        );
      }
      return `nullif(btrim((${value})::text), '')`;
    });
    return `case when ${keys.map((key) => `${key} is not null`).join(" and ")} then concat_ws(${sqlString(part.separator)}, ${keys.join(", ")}) end`;
  });
  return `coalesce(${expressions.join(", ")})`;
}

/** Columns only the profile's own user reads under `readPolicy: 'members'`. */
const PRIVATE_COLUMNS: ReadonlySet<string> = new Set([
  "email",
  "activeTenant",
  "activeTeam",
  "onboarding",
]);

/** Names no one gets as a username, from `sql.modules.profiles.options.reservedUsernames`. */
const RESERVED_USERNAMES = [
  "admin",
  "administrator",
  "api",
  "app",
  "auth",
  "billing",
  "help",
  "login",
  "logout",
  "me",
  "null",
  "root",
  "settings",
  "signup",
  "support",
  "system",
  "www",
];

function usernameRules(ctx: ModuleContext): {
  readonly min: number;
  readonly max: number;
  readonly reserved: string;
} {
  const min = ctx.number("usernameMinLength", 3);
  const max = ctx.number("usernameMaxLength", 32);
  if (
    !Number.isInteger(min) ||
    !Number.isInteger(max) ||
    min < 1 ||
    max < min + 4
  ) {
    throw new TypeError(
      "sql.modules.profiles.options.usernameMinLength and usernameMaxLength must be whole numbers, with room for a 4-digit suffix",
    );
  }
  const names = ctx
    .list("reservedUsernames", RESERVED_USERNAMES)
    .map((name) => {
      if (!/^[a-z0-9_]+$/.test(name)) {
        throw new TypeError(
          `sql.modules.profiles.options.reservedUsernames: "${name}" must be lowercase letters, digits or _`,
        );
      }
      return sqlString(name);
    });
  return {
    min,
    max,
    reserved:
      names.length === 0 ? "'{}'::text[]" : `array[${names.join(", ")}]`,
  };
}

/**
 * The username's length, characters and reserved names, as a check on the
 * managed table. Existing rows that break it leave the check unvalidated.
 * No `between`: Postgres expands it after flattening the `and` chain, so the
 * stored expression nests differently from the one pg-delta writes back, and
 * a declarative sync would drop and re-add the check every time.
 */
function usernameCheck(ctx: ModuleContext): string {
  const t = ctx.table("profiles");
  const u = ctx.col("profiles", "username");
  const { min, max, reserved } = usernameRules(ctx);
  return `alter table ${t} drop constraint if exists profiles_username_check;
alter table ${t} add constraint profiles_username_check check (
  ${u} is null or (
    length(${u}) >= ${String(min)}
    and length(${u}) <= ${String(max)}
    and ${u} ~* '^[a-z][a-z0-9_${usernameExtras(ctx)}]*$'
    and lower(${u}) <> all (${reserved})
  )
) not valid;
do $$
begin
  alter table ${t} validate constraint profiles_username_check;
exception when check_violation then
  raise warning '% has usernames that break profiles_username_check, so only new ones are checked', ${sqlString(t)};
end;
$$;`;
}

function table(ctx: ModuleContext): string {
  if (!ctx.manages) return "";
  const t = ctx.table("profiles");
  const c = (logical: string) => ctx.col("profiles", logical);
  const id = ctx.idType;
  const extra = extraColumns(ctx);
  const definitions: readonly (readonly [string, string])[] = [
    ["key", "uuid primary key references auth.users (id) on delete cascade"],
    ["email", "text"],
    ["username", "text"],
    ["fullName", "text"],
    ["firstName", "text"],
    ["lastName", "text"],
    ["avatar", "text"],
    ["avatarPath", "text"],
    ["activeTenant", id],
    ["activeTeam", id],
    ["onboarding", "jsonb not null default '{}'"],
    ["disabledAt", "timestamptz"],
    ["createdAt", "timestamptz not null default now()"],
    ["updatedAt", "timestamptz not null default now()"],
  ];
  const columns = definitions
    .filter(([logical]) => ctx.has("profiles", logical))
    .map(([logical, type]) => `${c(logical)} ${type}`);
  const username = ctx.has("profiles", "username")
    ? `\ncreate unique index if not exists profiles_username_idx on ${t} (lower(${c("username")}));
${usernameCheck(ctx)}`
    : "";
  const members = readPolicy(ctx).members;
  const read = members ? membersRead(ctx) : `${c("key")} = (select auth.uid())`;
  const visible = [
    ...definitions
      .map(([logical]) => logical)
      .filter(
        (logical) =>
          ctx.has("profiles", logical) && !PRIVATE_COLUMNS.has(logical),
      )
      .map(c),
    ...extra.map(([name]) => name),
  ];
  const selectGrant = members
    ? `-- Peers see the public columns; the caller reads the private ones
-- (${[...PRIVATE_COLUMNS]
        .filter((logical) => ctx.has("profiles", logical))
        .map(c)
        .join(", ")}) through ${ctx.fn("my_profile")}().
revoke select on ${t} from authenticated;
grant select (${visible.join(", ")}) on ${t} to authenticated;`
    : `grant select on ${t} to authenticated;`;
  return `
create table if not exists ${t} (
  ${columns.join(",\n  ")}
);${hasAvatarPath(ctx) ? `\nalter table ${t} add column if not exists ${c("avatarPath")} text;` : ""}${extra.map(([name, type]) => `\nalter table ${t} add column if not exists ${name} ${type};`).join("")}
${username}
alter table ${t} enable row level security;
drop policy if exists bs_profiles_read on ${t};
create policy bs_profiles_read on ${t} for select to authenticated
  using (${read});
drop policy if exists bs_profiles_update on ${t};
create policy bs_profiles_update on ${t} for update to authenticated
  using (${c("key")} = (select auth.uid()))
  with check (${c("key")} = (select auth.uid()));
${selectGrant}
grant all on ${t} to service_role;
`;
}

/**
 * `readPolicy`: `self`, `members`, or `{ members, platform }` where
 * `platform` is a key `is_platform()` checks, so platform staff read every
 * profile.
 */
function readPolicy(ctx: ModuleContext): {
  readonly members: boolean;
  readonly platform?: string;
} {
  const value = ctx.option("readPolicy") ?? "self";
  const where = "sql.modules.profiles.options.readPolicy";
  if (value === "self" || value === "members") {
    return { members: value === "members" };
  }
  if (typeof value === "object" && !Array.isArray(value)) {
    const members = "members" in value ? value.members : false;
    const platform = "platform" in value ? value.platform : undefined;
    if (
      typeof members === "boolean" &&
      (platform === undefined ||
        (typeof platform === "string" && platform.length > 0))
    ) {
      return platform === undefined ? { members } : { members, platform };
    }
  }
  throw new TypeError(
    `${where} must be "self", "members" or { members?: boolean, platform?: "<permission key>" }, not ${JSON.stringify(value)}`,
  );
}

/** Platform staff read every profile: a policy of its own, in either mode. */
function platformRead(ctx: ModuleContext): string {
  const platform = readPolicy(ctx).platform;
  if (platform === undefined) return "";
  const t = ctx.table("profiles");
  return `
-- Platform staff with ${platform} read every profile (readPolicy.platform).
-- Column grants still apply, so private columns stay behind them.
create or replace function ${ctx.fn("profiles_platform_readable")}()
returns boolean
language plpgsql
stable
set search_path = ''
as $$
begin
  return better_supabase.is_platform(${sqlString(platform)});
end;
$$;
revoke execute on function ${ctx.fn("profiles_platform_readable")}() from public, anon;
grant execute on function ${ctx.fn("profiles_platform_readable")}() to authenticated, service_role;
drop policy if exists bs_profiles_platform_read on ${t};
create policy bs_profiles_platform_read on ${t} for select to authenticated
  using ((select ${ctx.fn("profiles_platform_readable")}()));
`;
}

/** Profiles of the caller and of everyone who shares a tenant with them. */
function membersRead(ctx: ModuleContext): string {
  return `${ctx.col("profiles", "key")} in (select ${ctx.fn("profile_peer_ids")}())`;
}

/**
 * `profile_peer_ids()`: the caller and the users who share a tenant with
 * them. Security definer, so the memberships policies don't hide peers.
 */
function peers(ctx: ModuleContext): string {
  if (!readPolicy(ctx).members) return "";
  if (!ctx.installed("tenant")) {
    throw new TypeError(
      "sql.modules.profiles.options.readPolicy 'members' needs the tenant module",
    );
  }
  const tenant = ctx.of("tenant");
  const m = tenant.table("memberships");
  const mt = tenant.col("memberships", "tenant");
  const mu = tenant.col("memberships", "user");
  return `
create or replace function ${ctx.fn("profile_peer_ids")}()
returns setof uuid
language sql
stable
security definer
set search_path = ''
as $$
  select auth.uid()
  union
  select other.${mu} from ${m} mine
  join ${m} other on other.${mt} = mine.${mt}
  where mine.${mu} = auth.uid()
$$;
revoke execute on function ${ctx.fn("profile_peer_ids")}() from public, anon;
grant execute on function ${ctx.fn("profile_peer_ids")}() to authenticated, service_role;
`;
}

/** Column grants: users update only the columns in `options.updatable`. */
function grants(ctx: ModuleContext): string {
  if (!ctx.flag("columnGrants", ctx.manages)) return "";
  const defaults = [
    "fullName",
    "firstName",
    "lastName",
    "avatar",
    "avatarPath",
    "username",
    "onboarding",
  ]
    .filter((logical) =>
      logical === "avatarPath"
        ? hasAvatarPath(ctx)
        : ctx.has("profiles", logical),
    )
    .map((logical) => ctx.col("profiles", logical));
  const configured = ctx.option("updatable");
  const columns =
    configured === undefined
      ? [...defaults, ...extraColumns(ctx).map(([name]) => name)]
      : ctx
          .list("updatable", [])
          .map((name) =>
            column("sql.modules.profiles.options.updatable", name),
          );
  if (ctx.has("profiles", "updatedAt"))
    columns.push(ctx.col("profiles", "updatedAt"));
  const t = ctx.table("profiles");
  return `
-- Users update only these columns; the rest go through the module's functions.
revoke update on ${t} from authenticated;
${columns.length > 0 ? `grant update (${[...new Set(columns)].join(", ")}) on ${t} to authenticated;` : ""}`;
}

/** Rejects changes to service-owned columns from the API roles. */
function guard(ctx: ModuleContext): string {
  const defaults = [
    "email",
    "disabledAt",
    "activeTenant",
    "activeTeam",
    "createdAt",
  ]
    .filter((logical) => ctx.has("profiles", logical))
    .map((logical) => ctx.col("profiles", logical));
  const updatedAt = ctx.has("profiles", "updatedAt")
    ? ctx.col("profiles", "updatedAt")
    : undefined;
  // updated_at belongs to the table's own trigger (or the stamp below), so
  // the guard never rejects a change to it.
  const columns = (
    ctx.option("serviceColumns") === undefined
      ? defaults
      : ctx
          .list("serviceColumns", [])
          .map((name) =>
            column("sql.modules.profiles.options.serviceColumns", name),
          )
  ).filter((name) => name !== updatedAt);
  const t = ctx.table("profiles");
  const trigger = ctx.trigger("profile_guard");
  if (columns.length === 0) {
    return `drop trigger if exists ${trigger} on ${t};`;
  }
  const touched = [ctx.col("profiles", "key"), ...columns]
    .map((name) => `new.${name} is distinct from old.${name}`)
    .join("\n    or ");
  // A managed table has no other trigger for updated_at; an adopted one
  // keeps its own.
  const stamp =
    ctx.manages && updatedAt ? `\n  new.${updatedAt} := now();` : "";
  return `
-- The API roles can't change the key or ${columns.join(", ")}. Security
-- definer functions (switch_organization, the email mirror) run as their
-- owner and pass.
create or replace function ${ctx.fn("guard_profile")}()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if current_user in ('authenticated', 'anon') and not (${SERVICE_CALLER}) and (
    ${touched}
  ) then
    ${fail("PROFILE_COLUMN_READONLY", "These profile columns are managed by the service")}
  end if;${stamp}
  return new;
end;
$$;
drop trigger if exists ${trigger} on ${t};
create trigger ${trigger} before update on ${t}
  for each row execute function ${ctx.fn("guard_profile")}();`;
}

function functions(ctx: ModuleContext): string {
  const t = ctx.table("profiles");
  const key = ctx.col("profiles", "key");
  const values = syncValues(ctx);
  const columns = [key, ...values.keys()];
  const expressions = ["user_id", ...values.values()];
  const username = ctx.has("profiles", "username")
    ? ctx.col("profiles", "username")
    : undefined;
  const {
    min: minLength,
    max: maxLength,
    reserved,
  } = username ? usernameRules(ctx) : { min: 3, max: 32, reserved: "" };
  const allocate = username
    ? `
-- A free username from base: lowercased, stripped to [a-z0-9_], starting
-- with a letter, then suffixed with a number while it is reserved or
-- another profile has it.
create or replace function ${ctx.fn("allocate_username")}(base text, user_id uuid default null)
returns text
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  stem text := left(regexp_replace(lower(coalesce(base, '')), '[^a-z0-9_${username ? usernameExtras(ctx) : ""}]+', '', 'g'), ${String(maxLength - 4)});
  candidate text;
  n integer := 0;
begin
  if stem !~ '^[a-z]' then
    stem := left('u' || stem, ${String(maxLength - 4)});
  end if;
  if length(stem) < ${String(minLength)} then
    stem := 'user';
  end if;
  candidate := stem;
  while candidate = any(${reserved}) or exists (
    select 1 from ${t} p
    where lower(p.${username}) = candidate and p.${key} is distinct from user_id
  ) loop
    n := n + 1;
    candidate := stem || n::text;
  end loop;
  return candidate;
end;
$$;
revoke execute on function ${ctx.fn("allocate_username")}(text, uuid) from public, anon;
grant execute on function ${ctx.fn("allocate_username")}(text, uuid) to authenticated, service_role;`
    : "";
  return `${allocate}

-- Creates the user's profile from auth.users when it has none: metadata
-- keys (modules.profiles.options.metadata), the email and a username. The
-- after_profile_sync hook runs only for a profile it created.
create or replace function ${ctx.fn("sync_profile")}(user_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  u auth.users;
  meta jsonb;
  created boolean := false;
  attempt integer := 0;
begin
  select * into u from auth.users where id = user_id;
  if not found then
    return false;
  end if;
  meta := coalesce(u.raw_user_meta_data, '{}');
  if not exists (select 1 from ${t} p where p.${key} = user_id) then
    loop
      begin
        insert into ${t} (${columns.join(", ")})
        values (${expressions.join(", ")});
        created := true;
        exit;
      exception when unique_violation then
        -- Another sign-up took the username between allocation and insert.
        attempt := attempt + 1;
        if attempt >= 3 or exists (select 1 from ${t} p where p.${key} = user_id) then
          exit;
        end if;
      end;
    end loop;
  end if;
  if created then
    ${ctx.hook("after_profile_sync", [["uuid", "user_id"]]).replaceAll("\n", "\n  ")}
  end if;
  return created;
end;
$$;
revoke execute on function ${ctx.fn("sync_profile")}(uuid) from public, anon, authenticated;
grant execute on function ${ctx.fn("sync_profile")}(uuid) to service_role;

-- Profiles for users that have none, after installing on an existing project.
create or replace function ${ctx.fn("backfill_profiles")}()
returns integer
language sql
security definer
set search_path = ''
as $$
  select count(*)::integer from auth.users u where ${ctx.fn("sync_profile")}(u.id)
$$;
revoke execute on function ${ctx.fn("backfill_profiles")}() from public, anon, authenticated;
grant execute on function ${ctx.fn("backfill_profiles")}() to service_role;

drop function if exists ${ctx.fn("my_profile")}();
create or replace function ${ctx.fn("my_profile")}()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select to_jsonb(p) from ${t} p where p.${key} = (select auth.uid())
$$;
revoke execute on function ${ctx.fn("my_profile")}() from public, anon;
grant execute on function ${ctx.fn("my_profile")}() to authenticated, service_role;

create or replace function ${ctx.fn("update_my_profile")}(attrs jsonb)
returns boolean
language plpgsql
volatile
security invoker
set search_path = ''
as $$
declare
  updated integer;
begin
  update ${t} p
  set ${selfUpdates(ctx)}${ctx.has("profiles", "updatedAt") ? `,\n    ${ctx.col("profiles", "updatedAt")} = now()` : ""}
  where p.${key} = (select auth.uid());
  get diagnostics updated = row_count;
  return updated > 0;
end;
$$;
revoke execute on function ${ctx.fn("update_my_profile")}(jsonb) from public, anon;
grant execute on function ${ctx.fn("update_my_profile")}(jsonb) to authenticated, service_role;`;
}

function profilePhysical(ctx: ModuleContext, logical: string): string {
  const mapped = ctx.config.columns["profiles"]?.[logical];
  return typeof mapped === "string"
    ? mapped
    : NAMES.tables["profiles"]!.columns[logical]!;
}

function selfUpdates(ctx: ModuleContext): string {
  const columns = (
    [
      "fullName",
      "firstName",
      "lastName",
      "avatar",
      "avatarPath",
      "username",
      "onboarding",
    ] as const
  ).filter((logical) =>
    logical === "avatarPath"
      ? hasAvatarPath(ctx)
      : ctx.has("profiles", logical),
  );
  if (columns.length === 0) {
    return `${ctx.col("profiles", "key")} = p.${ctx.col("profiles", "key")}`;
  }
  return columns
    .map((logical) => {
      const quoted = ctx.col("profiles", logical);
      const key = sqlString(profilePhysical(ctx, logical));
      const extract = logical === "onboarding" ? "->" : "->>";
      return `${quoted} = case when update_my_profile.attrs ? ${key} then update_my_profile.attrs ${extract} ${key} else p.${quoted} end`;
    })
    .join(",\n    ");
}

/** The auth.users triggers: sync on sign-up and the email mirror. */
function authTriggers(ctx: ModuleContext): string {
  const t = ctx.table("profiles");
  const key = ctx.col("profiles", "key");
  const sync = ctx.trigger("profile_sync");
  const mirror = ctx.trigger("profile_email");
  const parts: string[] = [];
  if (ctx.flag("syncTrigger", true)) {
    parts.push(`${EQUIVALENT_TRIGGERS}

create or replace function ${ctx.fn("on_auth_user_created")}()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  -- A failure here would abort the sign-up. The user gets an account
  -- without a profile instead, and backfill_profiles() creates it later.
  begin
    perform ${ctx.fn("sync_profile")}(new.id);
  exception when others then
    raise warning 'No profile for user %: % (SQLSTATE %). Run backfill_profiles() once it is fixed.',
      new.id, sqlerrm, sqlstate;
  end;
  return new;
end;
$$;
drop trigger if exists ${sync} on auth.users;
create trigger ${sync} after insert on auth.users
  for each row execute function ${ctx.fn("on_auth_user_created")}();`);
  } else {
    parts.push(`drop trigger if exists ${sync} on auth.users;`);
  }
  if (ctx.has("profiles", "email") && ctx.flag("mirrorEmail", true)) {
    const email = ctx.col("profiles", "email");
    parts.push(`
-- Keeps the profile's email equal to the confirmed address in auth.users.
create or replace function ${ctx.fn("mirror_profile_email")}()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  update ${t} set ${email} = new.email where ${key} = new.id and ${email} is distinct from new.email;
  return new;
end;
$$;
drop trigger if exists ${mirror} on auth.users;
create trigger ${mirror} after update of email on auth.users
  for each row execute function ${ctx.fn("mirror_profile_email")}();`);
  } else {
    parts.push(`drop trigger if exists ${mirror} on auth.users;`);
  }
  return parts.join("\n");
}

function build(ctx: ModuleContext): string {
  if (ctx.mode === "custom") return "";
  readPolicy(ctx);
  return [
    `${schemaPreamble(ctx)}${peers(ctx)}${table(ctx)}${platformRead(ctx)}`,
    grants(ctx),
    guard(ctx),
    functions(ctx),
    authTriggers(ctx),
  ].join("\n");
}

export const PROFILES: ModuleDefinition = {
  name: "profiles",
  title: "Profiles",
  description:
    "A profile per user, created on sign-up from auth metadata with a unique username, an email mirror, column-level update grants and a guard on columns the service owns.",
  requires: [],
  integrates: ["tenant"],
  dependencies: (layout) => {
    const policy = layout.modules?.["profiles"]?.options?.["readPolicy"];
    return typeof policy === "object" && policy !== null && "platform" in policy
      ? ["access"]
      : [];
  },
  target: "schema",
  modes: ["managed", "adopt", "custom"],
  version: 2,
  upgrades: [
    {
      from: 1,
      description:
        "Managed profiles get an avatar_path column for an avatar stored in Storage; sync never writes it from auth metadata.",
      sql: () => "",
    },
  ],
  names: NAMES,
  contract: () => [
    { name: "sync_profile", args: ["uuid"], returns: "boolean" },
    { name: "backfill_profiles", args: [], returns: "integer" },
    { name: "my_profile", args: [], returns: "jsonb" },
    { name: "update_my_profile", args: ["jsonb"], returns: "boolean" },
  ],
  build,
  data: (ctx) =>
    ctx.flag("syncTrigger", true)
      ? `-- Warns about another trigger that also creates profiles (handle_new_user).
select better_supabase.replace_equivalent_triggers('auth.users', ${sqlString(ctx.trigger("profile_sync").slice(1, -1).replaceAll('""', '"'))}, '(handle_new_user|create_profile|new_user_profile)', false);`
      : "",
};
