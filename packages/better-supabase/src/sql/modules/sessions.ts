import type { BlockSqlContext } from "../context.ts";
import type { BlockSqlLayout, BlockSqlDefinition } from "../module-types.ts";

import { fillTemplate } from "../../core/access-sql.ts";
import { AUTHZ_EVENT, AUTHZ_TOPIC } from "../../core/authz-topic.ts";
import { policy as makePolicy, renderPolicy } from "../policy.ts";
import { tableGlobs } from "../schema-scan.ts";
import { qualifiedTable } from "./grants.ts";
import { roleAuthzBumps } from "./sessions-authz.ts";
import { SESSIONS_OVERVIEW_SQL, SESSIONS_READS } from "./sessions-reads.ts";

/** The `schema.table` names `blocks['sessions'].options.policies` covers. */
export function sessionPolicyTables(
  ctx: BlockSqlContext,
  layout: BlockSqlLayout,
): readonly string[] {
  if (!ctx.flag("policies", false)) {
    return [];
  }

  const exclude = tableGlobs(ctx.list("exclude", []));

  return (layout.declaredTables ?? []).filter(
    (table) => !exclude.some((pattern) => pattern.test(table)),
  );
}

/**
 * `blocks['sessions'].options.policies`: a restrictive session policy on every
 * table the schema files create in `schemas`, except `exclude`.
 */
function sessionPolicies(ctx: BlockSqlContext, layout: BlockSqlLayout): string {
  const tables = sessionPolicyTables(ctx, layout);

  if (tables.length === 0) {
    return "";
  }

  const statements = tables.map((table) => {
    const target = qualifiedTable(table);

    return renderPolicy(
      makePolicy({
        table: target,
        name: "bsb_session_active",
        roles: ["authenticated"],
        permissive: false,
        using: "(select better_supabase.session_active())",
        check: "(select better_supabase.session_active())",
      }),
      { target },
    );
  });

  return `

-- blocks['sessions'].options.policies: every table in the schema files,
-- except blocks['sessions'].options.exclude. \`upgrade\` rewrites these.
${statements.join("\n")}`;
}

const WHERE = "blocks['sessions'].options.bootstrap";

const BOOTSTRAP_NAME = /^[a-z][a-z0-9_]*$/;

const FUNCTION_NAME = /^[a-z_][a-z0-9_]*\.[a-z_][a-z0-9_]*$/;

function isFunctionRef(
  value: unknown,
): value is {
  readonly function: string;
  readonly subject?: string | false;
  readonly permissions?: false;
} {
  return (
    typeof value === "object" &&
    value !== null &&
    "function" in value &&
    typeof value.function === "string"
  );
}

const TABLE_KEY = /^[A-Za-z_][A-Za-z0-9_]*$/;

/** The `tables` an entry declares: model keys, only checked here. */
function checkTables(name: string, entry: object): void {
  if (!("tables" in entry) || entry.tables === undefined) {
    return;
  }

  const { tables } = entry;

  if (
    !Array.isArray(tables) ||
    !tables.every((table) => typeof table === "string" && TABLE_KEY.test(table))
  ) {
    throw new TypeError(
      `${WHERE}.${name}.tables must list table names (letters, digits, _)`,
    );
  }
}

function isReadSetRef(
  value: unknown,
): value is {
  readonly readSet: string;
  readonly subject?: string | false;
  readonly permissions?: false;
} {
  return (
    typeof value === "object" &&
    value !== null &&
    "readSet" in value &&
    typeof value.readSet === "string"
  );
}

function isReadSetsRef(
  value: unknown,
): value is {
  readonly readSets: readonly string[];
  readonly shell?: string;
  readonly subject?: string | false;
  readonly permissions?: false;
} {
  return (
    typeof value === "object" &&
    value !== null &&
    "readSets" in value &&
    Array.isArray(value.readSets)
  );
}

interface BootstrapTarget {
  readonly name: string;
  /** The function whose result is `data`, or none. */
  readonly fn: string | undefined;
  /** The read sets the caller can pick from, as `public.rs_<name>`. */
  readonly readSets: readonly string[];
  /** A no-argument function whose jsonb result is the authorizer subject. */
  readonly subject?: string | undefined;
  /** The entry sets `permissions: false`. */
  readonly noPermissions?: boolean;
  /**
   * `authorization.functions.subjectForTenant` with the call's tenant filled
   * in, for a target that uses the provider's `subject`. `null` for an unknown
   * tenant, so the payload never names the user's other tenants.
   */
  readonly subjectForTenant?: string | undefined;
  /**
   * `authorization.functions.bootstrapPermissions` with the call's tenant
   * filled in; absent when the entry sets `permissions: false`.
   */
  readonly permissions?: string | undefined;
}

/**
 * `blocks['sessions'].options.bootstrap`: wrapper name to `schema.function`, to
 * a read set (the function `public.rs_<name>`), or to `{ readSets, shell? }`,
 * where the caller picks one of the read sets per call.
 */
function subjectOf(
  name: string,
  subject: unknown,
  fallback: string | undefined,
): string | undefined {
  if (subject === undefined) {
    return fallback;
  }

  if (subject === false) {
    return undefined;
  }

  if (typeof subject !== "string" || !FUNCTION_NAME.test(subject)) {
    throw new TypeError(
      `${WHERE}.${name}.subject must name a function as schema.function`,
    );
  }

  return subject;
}

function bootstrapFunctions(
  ctx: BlockSqlContext,
  layout: BlockSqlLayout,
): readonly BootstrapTarget[] {
  const template = layout.accessProvider?.functions.subjectForTenant;
  const provider = layout.accessProvider;

  const permissions = provider?.functions.bootstrapPermissions;

  return bootstrapTargets(ctx, layout).map((target) => ({
    ...target,
    ...(template !== undefined &&
    provider !== undefined &&
    target.subject !== undefined &&
    target.subject === provider.functions.subject
      ? {
          subjectForTenant: fillTemplate(
            "authorization.functions.subjectForTenant",
            template,
            { tenant: "(args ->> 'tenant')", scope: provider.scope },
          ),
        }
      : {}),
    ...(permissions !== undefined &&
    provider !== undefined &&
    !target.noPermissions
      ? {
          permissions: fillTemplate(
            "authorization.functions.bootstrapPermissions",
            permissions,
            { tenant: "nullif(args ->> 'tenant', '')", scope: provider.scope },
          ),
        }
      : {}),
  }));
}

function bootstrapTargets(
  ctx: BlockSqlContext,
  layout: BlockSqlLayout,
): readonly BootstrapTarget[] {
  const fallback = layout.accessProvider?.functions.subject;

  const raw = ctx.option("bootstrap");

  if (raw === undefined) {
    return [];
  }

  if (typeof raw !== "object" || raw === null || Array.isArray(raw)) {
    throw new TypeError(
      `${WHERE} must map names to functions, e.g. { home: "app.home_data" } or { home: { readSet: "home" } }`,
    );
  }

  return Object.entries(raw).map(([name, fn]) => {
    if (!BOOTSTRAP_NAME.test(name)) {
      throw new TypeError(
        `${WHERE}.${name} must be a lowercase name (letters, digits, _)`,
      );
    }

    const entry: unknown = fn;

    if (typeof entry === "object" && entry !== null) {
      checkTables(name, entry);
    }

    if (isFunctionRef(fn)) {
      if (!FUNCTION_NAME.test(fn.function)) {
        throw new TypeError(
          `${WHERE}.${name}.function must name a function as schema.function`,
        );
      }

      return {
        name,
        fn: fn.function,
        readSets: [],
        subject: subjectOf(name, fn.subject, fallback),
        ...(fn.permissions === false ? { noPermissions: true } : {}),
      };
    }

    if (isReadSetsRef(fn)) {
      for (const set of fn.readSets) {
        if (typeof set !== "string" || !BOOTSTRAP_NAME.test(set)) {
          throw new TypeError(
            `${WHERE}.${name}.readSets must list lowercase read set names (letters, digits, _)`,
          );
        }
      }

      if (
        fn.shell !== undefined &&
        (typeof fn.shell !== "string" || !FUNCTION_NAME.test(fn.shell))
      ) {
        throw new TypeError(
          `${WHERE}.${name}.shell must name a function as schema.function`,
        );
      }

      return {
        name,
        fn: fn.shell,
        readSets: fn.readSets,
        subject: subjectOf(name, fn.subject, fallback),
        ...(fn.permissions === false ? { noPermissions: true } : {}),
      };
    }

    if (isReadSetRef(fn)) {
      if (!BOOTSTRAP_NAME.test(fn.readSet)) {
        throw new TypeError(
          `${WHERE}.${name}.readSet must be a lowercase read set name (letters, digits, _)`,
        );
      }

      return {
        name,
        fn: `public.rs_${fn.readSet}`,
        readSets: [],
        subject: subjectOf(name, fn.subject, fallback),
        ...(fn.permissions === false ? { noPermissions: true } : {}),
      };
    }

    if (typeof fn !== "string" || !FUNCTION_NAME.test(fn)) {
      throw new TypeError(
        `${WHERE}.${name} must name a function as schema.function, e.g. "app.home_data"`,
      );
    }

    return { name, fn, readSets: [], subject: fallback };
  });
}

/**
 * Whether the database keeps a live authorization version: the module's own
 * table (`authzVersions`) or the provider's (`authorization.versions`).
 */
function hasVersionSource(
  ctx: BlockSqlContext,
  layout: BlockSqlLayout,
): boolean {
  return (
    layout.authzVersionsProvider !== undefined ||
    ctx.flag("authzVersions", false)
  );
}

/**
 * The `'subject'` pair of a wrapper. With `subjectForTenant` a call that names
 * a tenant gets the subject restricted to it, and a call without one the whole
 * subject.
 */
function subjectSql(
  subject: string | undefined,
  subjectForTenant: string | undefined,
): string {
  if (!subject) {
    return "";
  }

  return subjectForTenant === undefined
    ? `,\n    'subject', to_jsonb(${subject}())`
    : `,\n    'subject', case when nullif(args ->> 'tenant', '') is null then to_jsonb(${subject}()) else to_jsonb(${subjectForTenant}) end`;
}

/**
 * One wrapper per `bootstrap` entry: the session check, the authorization
 * version and the app function's data in one jsonb, so a page's first query
 * carries all three. It runs as the caller, so the app function's policies
 * apply. `authz_version` is the live version when the database keeps one, so a
 * seeded version cache never hides a role change the token predates;
 * `token_authz_version` is the token's.
 */
function bootstrapWrappers(
  ctx: BlockSqlContext,
  layout: BlockSqlLayout,
): string {
  const functions = bootstrapFunctions(ctx, layout);

  if (functions.length === 0) {
    return "";
  }

  const live = hasVersionSource(ctx, layout)
    ? "to_jsonb(better_supabase.caller_authz_version())"
    : "auth.jwt() -> 'authz_ver'";

  const wrappers = functions.map(
    ({ name, fn, readSets, subject, subjectForTenant, permissions }) => {
      const wrapper = `better_supabase.bootstrap_${name}`;
      const picks = readSets.length > 0;
      const dataSql = fn === undefined ? "null" : `to_jsonb(${fn}(args))`;

      const signature = picks
        ? `args jsonb default '{}'::jsonb, read_set text default null, read_params jsonb default null`
        : `args jsonb default '{}'::jsonb`;

      const argTypes = picks ? "jsonb, text, jsonb" : "jsonb";

      // A static case: the set is one of the listed functions, never a name the
      // caller builds. Each runs as the caller, so its policies apply.
      const readsSql = picks
        ? `,
    'reads', case read_set
${readSets
  .map(
    (set) =>
      `      when '${set}' then to_jsonb(public.rs_${set}(coalesce(read_params, '{}'::jsonb)))`,
  )
  .join("\n")}
      else null
    end`
        : "";

      const guard = picks
        ? `
  if read_set is not null and read_set not in (${readSets.map((set) => `'${set}'`).join(", ")}) then
    raise exception 'unknown read set %', read_set using errcode = '22023';
  end if;`
        : "";

      // The earlier one-argument wrapper would make a named call ambiguous.
      const dropOld = picks
        ? `drop function if exists ${wrapper}(jsonb);\n\n`
        : "";

      return `${dropOld}create or replace function ${wrapper}(${signature})
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
begin${guard}
  if not (select better_supabase.session_active()) then
    return jsonb_build_object(
      'session_active', false,
      'end_reason', better_supabase.session_end_reason(),
      'authz_version', auth.jwt() -> 'authz_ver',
      'token_authz_version', auth.jwt() -> 'authz_ver',
      'tenant', args ->> 'tenant',
      'data', null
    );
  end if;
  return jsonb_build_object(
    'session_active', true,
    'authz_version', ${live},
    'token_authz_version', auth.jwt() -> 'authz_ver',
    'tenant', args ->> 'tenant',
    'data', ${dataSql}${readsSql}${subjectSql(subject, subjectForTenant)}${permissions === undefined ? "" : `,\n    'permissions', to_jsonb(${permissions})`}
  );
end;
$$;

revoke execute on function ${wrapper}(${argTypes}) from public, anon;
grant execute on function ${wrapper}(${argTypes}) to authenticated;`;
    },
  );

  return `

-- blocks['sessions'].options.bootstrap: bsb.bootstrap({ rpc }) calls these.
-- Each checks the session and returns the caller's authorization version
-- (the live one when the database keeps it, and the token's) with the app
-- function's data, so a cache miss is one query.
${wrappers.join("\n\n")}`;
}

/**
 * `blocks['sessions'].options.hook`: `better_supabase.hook_plan(event)`, which
 * tells the app's access token hook how much to read.
 *
 * - `slim`: the token has a `client_id` claim (the OAuth server issues those) and
 *   `oauth` is `'slim'`. The hook leaves out memberships, permissions,
 *   `team_ids` and `authz_ver`, and reads nothing.
 * - `reuse`: a `token_refresh` whose incoming `authz_ver` equals the user's
 *   current version, with a `memberships` array and no truncation flag. The
 *   hook returns the event unchanged.
 * - `full`: everything else.
 *
 * Supabase Auth builds refresh claims itself, so `reuse` applies only where the
 * event carries the previous token's `authz_ver`; any doubt reads again.
 */
function hookPlan(ctx: BlockSqlContext, layout: BlockSqlLayout): string {
  const raw = ctx.option("hook");

  if (raw === undefined || raw === false) {
    return "";
  }

  const options: Readonly<Record<string, unknown>> | undefined =
    typeof raw === "object" && raw !== null && !Array.isArray(raw)
      ? Object.fromEntries(Object.entries(raw))
      : raw === true
        ? {}
        : undefined;

  if (options === undefined) {
    throw new TypeError(
      "blocks['sessions'].options.hook must be true or { refresh, oauth, truncatedClaim }",
    );
  }

  const choose = (key: string, allowed: readonly string[]): string => {
    const value = options[key];

    if (value === undefined) {
      return allowed[0]!;
    }

    if (typeof value !== "string" || !allowed.includes(value)) {
      throw new TypeError(
        `blocks['sessions'].options.hook.${key} must be ${allowed.map((entry) => `'${entry}'`).join(" or ")}`,
      );
    }

    return value;
  };

  const refresh = choose("refresh", ["reuse", "full"]);
  const oauth = choose("oauth", ["full", "slim"]);
  const flag = options["truncatedClaim"];
  const teamFlag = options["teamIdsTruncatedClaim"];

  const teamClaim =
    teamFlag === undefined
      ? (layout.accessProvider?.teamIdsTruncatedClaim ?? "team_ids_truncated")
      : typeof teamFlag === "string" && /^[a-z_][a-z0-9_]*$/.test(teamFlag)
        ? teamFlag
        : undefined;

  if (teamClaim === undefined) {
    throw new TypeError(
      "blocks['sessions'].options.hook.teamIdsTruncatedClaim must be a claim name (letters, digits, _)",
    );
  }

  const truncated =
    flag === undefined
      ? (layout.accessProvider?.truncatedClaim ?? "permissions_truncated")
      : typeof flag === "string" && /^[a-z_][a-z0-9_]*$/.test(flag)
        ? flag
        : undefined;

  if (truncated === undefined) {
    throw new TypeError(
      "blocks['sessions'].options.hook.truncatedClaim must be a claim name (letters, digits, _)",
    );
  }

  if (refresh === "reuse" && !hasVersionSource(ctx, layout)) {
    throw new TypeError(
      "blocks['sessions'].options.hook.refresh 'reuse' needs authorization versions: set options.authzVersions or give the authorization provider `versions`, or set refresh to 'full'",
    );
  }

  const provider = layout.authzVersionsProvider;

  const current = provider
    ? `${provider.function}(v_user)`
    : "better_supabase.authz_version(v_user)";

  const slim =
    oauth === "slim"
      ? `
  if coalesce(v_claims ->> 'client_id', '') <> '' then
    return 'slim';
  end if;
`
      : "";

  const tenantSwitch = `
  -- A refresh whose permission claim was built for another tenant than
  -- app_metadata.tenant_id must read again. reuse would keep the old keys.
  if coalesce(v_claims -> 'app_metadata' ->> 'tenant_id', '') <> ''
    and jsonb_typeof(v_claims -> 'permissions') = 'object'
    and v_claims -> 'permissions' <> '{}'::jsonb
    and not (v_claims -> 'permissions' ? (v_claims -> 'app_metadata' ->> 'tenant_id'))
  then
    return 'full';
  end if;
`;

  const reuse =
    refresh === "reuse"
      ? `
  if event ->> 'authentication_method' = 'token_refresh'
    and jsonb_typeof(v_claims -> 'authz_ver') = 'number'
    and jsonb_typeof(v_claims -> 'memberships') = 'array'
    and coalesce(v_claims ->> '${truncated}', 'false') <> 'true'
    and coalesce(v_claims ->> '${teamClaim}', 'false') <> 'true'
    and (v_claims ->> 'authz_ver')::bigint = ${current}
  then
    return 'reuse';
  end if;
`
      : "";

  return `

-- blocks['sessions'].options.hook: how much the access token hook reads for
-- this event, as 'slim' (an OAuth client token: leave out memberships,
-- permissions, team_ids and authz_ver), 'reuse' (a refresh whose authz_ver is
-- still current: return the event unchanged, no membership reads) or 'full'.
-- Call it first in the hook:
--   plan := better_supabase.hook_plan(event);
create or replace function better_supabase.hook_plan(event jsonb)
returns text
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_claims jsonb := coalesce(event -> 'claims', '{}'::jsonb);
  v_user uuid := nullif(event ->> 'user_id', '')::uuid;
begin${slim}${tenantSwitch}${reuse}
  return 'full';
end;
$$;

revoke execute on function better_supabase.hook_plan(jsonb) from public, anon, authenticated;
grant execute on function better_supabase.hook_plan(jsonb) to supabase_auth_admin, service_role;`;
}

/**
 * `better_supabase.caller_authz_version()`: the caller's own live version, for
 * the bootstrap wrappers and for clients that catch up after a missed
 * broadcast. Reads the provider's function when it keeps the versions.
 */
function callerAuthzVersion(
  ctx: BlockSqlContext,
  layout: BlockSqlLayout,
): string {
  if (!hasVersionSource(ctx, layout)) {
    return "";
  }

  const provider = layout.authzVersionsProvider;

  const source = provider
    ? `${provider.function}(auth.uid())`
    : "better_supabase.authz_version(auth.uid())";

  return `

-- The caller's own authorization version, null without a signed-in user.
-- Clients compare it with the token's authz_ver to catch up on a broadcast
-- they missed.${provider ? `\n-- ${provider.name} keeps the versions in ${provider.function}.` : ""}
create or replace function better_supabase.caller_authz_version()
returns bigint
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    return null;
  end if;
  return ${source};
end;
$$;

revoke execute on function better_supabase.caller_authz_version() from public, anon;
grant execute on function better_supabase.caller_authz_version() to authenticated;`;
}

/**
 * `blocks['sessions'].options.authzVersions`: a version per user that a trigger
 * bumps, the access token hook copies into `authz_ver`, and Realtime broadcasts
 * on the shared server topic and on the user's own `authz:<uid>`. A provider
 * that keeps the versions (`authorization.versions`) owns all of that, so the
 * module writes none of it.
 */
function authzVersions(ctx: BlockSqlContext, layout: BlockSqlLayout): string {
  if (
    !ctx.flag("authzVersions", false) ||
    layout.authzVersionsProvider !== undefined
  ) {
    return "";
  }

  const payload =
    "jsonb_build_object('user_id', new.user_id, 'version', new.version)";

  return `

-- blocks['sessions'].options.authzVersions: one authorization version per
-- user. Attach better_supabase.bump_authz_version() to the tables a user's
-- access comes from; the access token hook reads better_supabase.authz_version().
create table if not exists better_supabase.user_authz_versions (
  user_id uuid primary key references auth.users on delete cascade,
  version bigint not null default 1,
  updated_at timestamptz not null default now()
);

alter table better_supabase.user_authz_versions enable row level security;

revoke all on better_supabase.user_authz_versions from public, anon, authenticated;
grant select on better_supabase.user_authz_versions to supabase_auth_admin;
grant all on better_supabase.user_authz_versions to service_role;

${renderPolicy(
  makePolicy({
    table: "better_supabase.user_authz_versions",
    name: "bsb_authz_versions_auth_admin",
    command: "select",
    roles: ["supabase_auth_admin"],
    using: "true",
  }),
  { target: "better_supabase.user_authz_versions" },
)}

-- The version the access token hook copies into authz_ver; 0 before the
-- first bump.
create or replace function better_supabase.authz_version(p_user uuid)
returns bigint
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
    (select v.version from better_supabase.user_authz_versions v where v.user_id = p_user),
    0
  )
$$;

revoke execute on function better_supabase.authz_version(uuid) from public, anon, authenticated;
grant execute on function better_supabase.authz_version(uuid) to supabase_auth_admin, service_role;

-- Bumps the versions of many users at once, for changes no trigger sees.
create or replace function better_supabase.bump_authz_versions(p_users uuid[])
returns void
language sql
volatile
security definer
set search_path = ''
as $$
  insert into better_supabase.user_authz_versions as v (user_id)
  select distinct u from unnest(p_users) u
  where u is not null and exists (select 1 from auth.users x where x.id = u)
  on conflict (user_id) do update
    set version = v.version + 1, updated_at = now()
$$;

revoke execute on function better_supabase.bump_authz_versions(uuid[]) from public, anon, authenticated;
grant execute on function better_supabase.bump_authz_versions(uuid[]) to service_role;

-- A row trigger: bumps the user in the row's user_id column, or in the column
-- named by the trigger's first argument, before and after an update.
create or replace function better_supabase.bump_authz_version()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  col text := coalesce(tg_argv[0], 'user_id');
begin
  perform better_supabase.bump_authz_versions(array[
    (to_jsonb(new) ->> col)::uuid,
    (to_jsonb(old) ->> col)::uuid
  ]);
  return null;
end;
$$;

revoke execute on function better_supabase.bump_authz_version() from public, anon, authenticated;

-- Sends { user_id, version } as the changed event on the server topic, which
-- no user may join, and on the user's own authz:<uid> topic.
create or replace function better_supabase.broadcast_authz_version()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  ${ctx.broadcast(`'${AUTHZ_TOPIC}'`, `'${AUTHZ_EVENT}'`, payload, { indent: "  " })}
  ${ctx.broadcast("'authz:' || new.user_id::text", `'${AUTHZ_EVENT}'`, payload, { indent: "  " })}
  return null;
end;
$$;

revoke execute on function better_supabase.broadcast_authz_version() from public, anon, authenticated;

drop trigger if exists bsb_authz_versions_broadcast on better_supabase.user_authz_versions;
create trigger bsb_authz_versions_broadcast
  after insert or update on better_supabase.user_authz_versions
  for each row execute function better_supabase.broadcast_authz_version();

do $$
begin
  if to_regclass('realtime.messages') is not null then
    ${renderPolicy(
      makePolicy({
        table: "realtime.messages",
        name: "bsb_authz_versions_receive",
        command: "select",
        roles: ["authenticated"],
        using: `realtime.messages.extension = 'broadcast' and (select realtime.topic()) = 'authz:' || (select auth.uid())::text`,
      }),
      { target: "realtime.messages" },
    )}
  end if;
end;
$$;${roleAuthzBumps(ctx)}`;
}

export const SESSIONS: BlockSqlDefinition = {
  internal: ["session_active", "session_end_reason"],
  name: "sessions",
  names: {
    reads: SESSIONS_READS,
    tables: {},
    options: ["authzVersions", "bootstrap", "exclude", "hook", "policies"],
  },
  title: "Session revocation",
  description:
    "session_active() for restrictive policies: false once the caller's session was signed out or expired, or the user was banned or deleted, so revoked access tokens stop working before they expire. options.policies writes the policy on every table.",
  requires: [],
  integrates: ["permissions", "memberships"],
  target: "schema",
  build: (ctx, layout) => `
-- An access token stays valid until it expires, even after its session is
-- signed out or its user is deleted. This checks the session behind it.
-- Tokens without a session_id claim (signed by the app) and support tokens
-- (with an act claim, whose session the support module ends) pass.
-- authenticated can't read auth.sessions, so the check runs as the owner.
create or replace function better_supabase.session_active()
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  claims jsonb := auth.jwt();
  session text := claims ->> 'session_id';
begin
  if claims -> 'act' is not null or session is null then
    return true;
  end if;
  if session !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    return false;
  end if;
  return exists (
    select 1
    from auth.sessions s
    join auth.users u on u.id = s.user_id
    where s.id = session::uuid
      and s.user_id = auth.uid()
      and (s.not_after is null or s.not_after > now())
      and (u.banned_until is null or u.banned_until <= now())
      and u.deleted_at is null
  );
end;
$$;

revoke execute on function better_supabase.session_active() from public, anon;
grant execute on function better_supabase.session_active() to authenticated;

-- Why session_active() is false: user_banned while the caller's user is banned,
-- else session_not_found. The bootstrap wrappers return it as end_reason.
create or replace function better_supabase.session_end_reason()
returns text
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if exists (
    select 1 from auth.users u
    where u.id = auth.uid() and u.banned_until is not null and u.banned_until > now()
  ) then
    return 'user_banned';
  end if;
  return 'session_not_found';
end;
$$;

revoke execute on function better_supabase.session_end_reason() from public, anon;
grant execute on function better_supabase.session_end_reason() to authenticated;

-- The last sign-in of many users in one query, for admin lists. auth.users
-- isn't readable through the Data API, so only the service role calls this.
create or replace function better_supabase.last_sign_ins(p_users uuid[])
returns table (user_id uuid, last_sign_in_at timestamptz)
language sql
stable
security definer
set search_path = ''
as $$
  select u.id, u.last_sign_in_at
  from auth.users u
  where u.id = any(p_users)
$$;

revoke execute on function better_supabase.last_sign_ins(uuid[]) from public, anon, authenticated;
grant execute on function better_supabase.last_sign_ins(uuid[]) to service_role;

-- Deletes every session and refresh token of a user and returns how many
-- sessions went. Only the service role calls this, over SQL or the Data API.
create or replace function better_supabase.end_sessions(p_user uuid)
returns int
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  ended int;
begin
  with gone as (
    delete from auth.sessions s where s.user_id = end_sessions.p_user returning s.id
  )
  select count(*)::int into ended from gone;
  delete from auth.refresh_tokens t where t.user_id = end_sessions.p_user::text;
  return ended;
end;
$$;

revoke execute on function better_supabase.end_sessions(uuid) from public, anon, authenticated;
grant execute on function better_supabase.end_sessions(uuid) to service_role;

-- The caller's own unexpired sessions, most recently active first, with the
-- one behind the current token marked.
create or replace function better_supabase.list_my_sessions()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', s.id,
    'createdAt', s.created_at,
    'lastActiveAt', coalesce(s.updated_at, s.created_at),
    'userAgent', s.user_agent,
    'ip', host(s.ip),
    'aal', s.aal,
    'current', s.id::text = auth.jwt() ->> 'session_id'
  ) order by coalesce(s.updated_at, s.created_at) desc), '[]'::jsonb)
  from auth.sessions s
  where s.user_id = (select auth.uid())
    and (s.not_after is null or s.not_after > now())
$$;

revoke execute on function better_supabase.list_my_sessions() from public, anon;
grant execute on function better_supabase.list_my_sessions() to authenticated;

-- Ends one of the caller's sessions: its refresh tokens go with it, and
-- session_active() turns false for its access tokens.
create or replace function better_supabase.end_my_session(session uuid)
returns boolean
language plpgsql
volatile
security definer
set search_path = ''
as $$
begin
  delete from auth.sessions s
  where s.id = end_my_session.session
    and s.user_id = (select auth.uid());
  return found;
end;
$$;

revoke execute on function better_supabase.end_my_session(uuid) from public, anon;
grant execute on function better_supabase.end_my_session(uuid) to authenticated;
${SESSIONS_OVERVIEW_SQL}

-- Restrictive, so it applies on top of the table's other policies. Wrapped in
-- a select, it runs one indexed lookup per statement:
-- create policy session_required on public.invoices as restrictive
--   for all to authenticated
--   using ((select better_supabase.session_active()))
--   with check ((select better_supabase.session_active()));${sessionPolicies(ctx, layout)}${authzVersions(ctx, layout)}${hookPlan(ctx, layout)}${callerAuthzVersion(ctx, layout)}${bootstrapWrappers(ctx, layout)}`,
};
