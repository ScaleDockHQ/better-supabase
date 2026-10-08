import type { AuthorizationTokenHook } from "../../config/index.ts";
import type { ExtrasHook, ExtrasHookFunction } from "../introspect/types.ts";
import type {
  DoctorContext,
  FindingInput,
  Location,
  Rule,
  TextFile,
} from "./rules.ts";

import { providerLabel } from "../authorization.ts";
import {
  type DiffEngine,
  diffEngine,
  httpHooks,
  type PgFunctionHook,
  pgFunctionHooks,
} from "../supabase-toml.ts";
import { errorText, ident, literal, type LiveDatabase } from "./live.ts";
import { lineOf } from "./shared.ts";

/** Claims past this size make every request carry a large cookie and header. */
const HOOK_CLAIMS_LIMIT = 2048;

interface ClaimsLimits {
  readonly token: number;
  /** The provider's hook budget, over `claims`. */
  readonly budget?: {
    readonly bytes: number;
    readonly claims: readonly string[];
    readonly truncatedClaim?: string;
  };
}

/**
 * The BS405 limits. With a provider hook budget, `doctor.claimsLimit` (else
 * the budget's bytes) limits its claims and the whole token keeps 2048;
 * without one, `doctor.claimsLimit` limits the whole token.
 */
function claimsLimits(context: DoctorContext): ClaimsLimits {
  const configured = context.config.doctor.claimsLimit;
  const budget = providerHook(context)?.budget;
  return budget
    ? {
        token: HOOK_CLAIMS_LIMIT,
        budget: {
          bytes: configured ?? budget.bytes,
          claims: budget.claims,
          ...(budget.truncatedClaim
            ? { truncatedClaim: budget.truncatedClaim }
            : {}),
        },
      }
    : { token: configured ?? HOOK_CLAIMS_LIMIT };
}

/** The module function that fills the `memberships` claim. */
const MODULE_MEMBERSHIPS = /better_supabase\s*\.\s*membership_claims\b/i;

const providerHook = (
  context: DoctorContext,
): AuthorizationTokenHook | undefined =>
  context.config.authorization?.tokenHook;

const splitName = (
  qualified: string,
): { readonly schema: string; readonly name: string } => {
  const dot = qualified.indexOf(".");
  return { schema: qualified.slice(0, dot), name: qualified.slice(dot + 1) };
};

const escapeRegExp = (text: string): string =>
  text.replaceAll(/[.*+?^${}()|[\]\\]/g, "\\$&");

/**
 * The claims the provider's hook writes that a second writer would
 * contradict, with the tenant claim it writes to.
 */
function ownedClaims(hook: AuthorizationTokenHook): readonly string[] {
  return [
    ...new Set([
      ...hook.ownedClaims,
      ...(hook.tenantClaim ? [hook.tenantClaim] : []),
    ]),
  ];
}

const quotedName = (schema: string, name: string): string =>
  `(?:"?${escapeRegExp(schema)}"?\\s*\\.\\s*)?"?${escapeRegExp(name)}"?`;

const createsFunction = (
  fn: Pick<ExtrasHookFunction, "schema" | "name">,
): RegExp =>
  new RegExp(
    `create\\s+(?:or\\s+replace\\s+)?function\\s+${quotedName(fn.schema, fn.name)}\\s*\\(`,
    "i",
  );

/** The SQL file that has the provider's hook marker and creates `fn`. */
function markerFileFor(
  context: DoctorContext,
  fn: Pick<ExtrasHookFunction, "schema" | "name">,
): TextFile | undefined {
  const marker = providerHook(context)?.markers?.hook;
  if (marker === undefined) return undefined;
  const creates = createsFunction(fn);
  return (context.sqlFiles ?? []).find(
    (file) => file.text.includes(marker) && creates.test(file.text),
  );
}

/** Whether `fn` is the provider's hook: by its name or its marker file. */
function isProviderHook(
  context: DoctorContext,
  fn: Pick<ExtrasHookFunction, "schema" | "name">,
): boolean {
  const hook = providerHook(context);
  if (!hook) return false;
  if (hook.function === `${fn.schema}.${fn.name}`) return true;
  return markerFileFor(context, fn) !== undefined;
}

/** Whether the hook body calls the provider's hook (a wrapper around it). */
function wrapsProviderHook(
  hook: AuthorizationTokenHook,
  source: string,
): boolean {
  const { schema, name } = splitName(hook.function);
  return new RegExp(`${quotedName(schema, name)}\\s*\\(`, "i").test(source);
}

/** Which of `claims` the hook body writes through `jsonb_set` or `jsonb_build_object`. */
function writtenClaims(source: string, claims: readonly string[]): string[] {
  return claims.filter((claim) => {
    const name = escapeRegExp(claim);
    return (
      new RegExp(
        `jsonb_set\\s*\\([^;]*?'\\{\\s*(?:claims\\s*,\\s*)?${name}\\s*\\}'`,
        "i",
      ).test(source) ||
      new RegExp(`jsonb_build_object\\s*\\([^;]*?'${name}'\\s*,`, "i").test(
        source,
      )
    );
  });
}

const API_ROLES = ["authenticated", "anon"] as const;

export interface ConfiguredHook {
  readonly config: PgFunctionHook;
  /** Absent when the snapshot predates the hook (or `hooks` introspection). */
  readonly extras: ExtrasHook | undefined;
}

/** Hooks enabled in `config.toml`, matched with their introspected functions. */
export function configuredHooks(context: DoctorContext): ConfiguredHook[] {
  if (!context.configToml) return [];
  const introspected = context.snapshot.extras.hooks ?? [];
  return pgFunctionHooks(context.configToml.document).map((config) => ({
    config,
    extras: introspected.find(
      (hook) =>
        hook.hook === config.hook &&
        hook.schema === config.schema &&
        hook.name === config.name,
    ),
  }));
}

function hookLocation(
  context: DoctorContext,
  hook: string,
): Location | undefined {
  if (!context.configToml) return undefined;
  const line = lineOf(
    context.configToml.text,
    new RegExp(`^\\s*\\[auth\\.hook\\.${hook}\\]`),
  );
  return line ? { file: context.configToml.path, line } : undefined;
}

export const signatureOf = (fn: ExtrasHookFunction): string =>
  `${fn.schema}.${fn.name}(${fn.signature})`;

/** What is wrong with who may call a hook function, and the SQL that fixes it. */
function grantProblems(fn: ExtrasHookFunction): {
  problems: string[];
  fix: string[];
} {
  const problems: string[] = [];
  const fix: string[] = [];
  if (!fn.schemaUsage.includes("supabase_auth_admin")) {
    problems.push(`supabase_auth_admin has no usage on schema ${fn.schema}`);
    fix.push(`grant usage on schema ${fn.schema} to supabase_auth_admin;`);
  }
  if (!fn.execute.includes("supabase_auth_admin")) {
    problems.push("supabase_auth_admin may not execute it");
    fix.push(
      `grant execute on function ${signatureOf(fn)} to supabase_auth_admin;`,
    );
  }
  const exposedTo = API_ROLES.filter((role) => fn.execute.includes(role));
  if (exposedTo.length > 0 || fn.publicExecute) {
    const roles = [...exposedTo, ...(fn.publicExecute ? ["public"] : [])];
    problems.push(
      `${roles.join(", ")} may execute it, so any client can call it through the API`,
    );
    fix.push(
      `revoke execute on function ${signatureOf(fn)} from authenticated, anon, public;`,
    );
  }
  return { problems, fix };
}

/**
 * What fixes a hook function's grants: SQL to add, the provider's own
 * command (it is the provider's hook), or applying the file that already
 * grants it.
 */
type HookGrantFix =
  | { readonly kind: "sql"; readonly sql: readonly string[] }
  | {
      readonly kind: "provider";
      readonly name: string;
      readonly command?: string;
    }
  | { readonly kind: "migration"; readonly file: string };

export interface HookGrantProblem {
  readonly hook: string;
  readonly fn: ExtrasHookFunction;
  readonly problems: readonly string[];
  readonly fix: HookGrantFix;
}

const MIGRATIONS = /(?:^|\/)supabase\/migrations\//;

/**
 * The file that grants `fn` to `supabase_auth_admin`: a migration with the
 * provider's grants marker, or under pg-delta, which carries grants, the declarative
 * schema file that defines `fn`. `supabase db diff` drops grants, so the
 * legacy engine only counts the migration.
 */
function grantsSourceFor(
  context: DoctorContext,
  fn: ExtrasHookFunction,
  engine: DiffEngine,
): string | undefined {
  const grants = new RegExp(
    `grant\\s+execute\\s+on\\s+function\\s+${quotedName(fn.schema, fn.name)}\\s*\\([^)]*\\)\\s*to\\s+[^;]*\\bsupabase_auth_admin\\b`,
    "i",
  );
  const creates = createsFunction(fn);
  const marker = providerHook(context)?.markers?.grants;
  return (context.sqlFiles ?? []).find(
    (file) =>
      grants.test(file.text) &&
      ((marker !== undefined && file.text.includes(marker)) ||
        (engine === "pg-delta" &&
          !MIGRATIONS.test(file.path) &&
          creates.test(file.text))),
  )?.path;
}

/** Configured hook functions whose grants are wrong (BS404, `doctor --fix-grants`). */
export function hookGrantProblems(context: DoctorContext): HookGrantProblem[] {
  const engine = diffEngine(context.configToml);
  return configuredHooks(context).flatMap(({ config, extras }) =>
    (extras?.functions ?? []).flatMap((fn): HookGrantProblem[] => {
      const { problems, fix } = grantProblems(fn);
      if (problems.length === 0) return [];
      const file = grantsSourceFor(context, fn, engine);
      const provider = context.config.authorization;
      const command = provider?.tokenHook?.grantsCommand;
      return [
        {
          hook: config.hook,
          fn,
          problems,
          fix: file
            ? { kind: "migration", file }
            : provider && isProviderHook(context, fn)
              ? {
                  kind: "provider",
                  name: providerLabel(provider),
                  ...(command ? { command } : {}),
                }
              : { kind: "sql", sql: fix },
        },
      ];
    }),
  );
}

/** The sentence that tells the reader how to apply `fix`. */
function grantFixText(fix: HookGrantFix, engine: DiffEngine): string {
  switch (fix.kind) {
    case "sql":
      return engine === "pg-delta"
        ? `Add to the schema file that defines the function, then run \`supabase db schema declarative sync\` (\`doctor --fix-grants\` prints every block):\n${fix.sql.join("\n")}`
        : `Append to the migration \`supabase db diff\` wrote (\`doctor --fix-grants\` prints every block):\n${fix.sql.join("\n")}`;
    case "provider":
      return fix.command
        ? `It is the hook of ${fix.name}, so let the provider write the grants: \`${fix.command}\`.`
        : `It is the hook of ${fix.name}, so let the provider write the grants.`;
    case "migration":
      return engine === "pg-delta"
        ? `${fix.file} grants it, so the database is behind: run \`supabase db schema declarative sync\`, then apply the migrations (\`supabase migration up\`).`
        : `${fix.file} grants it, so the database is behind the migrations: apply them (\`supabase migration up\`).`;
    default: {
      const unreachable: never = fix;
      return unreachable;
    }
  }
}

/** `doctor --fix-grants`: the SQL block for every BS404 problem, as one migration snippet. */
export function hookGrantBlock(
  problems: readonly HookGrantProblem[],
  engine: DiffEngine = "pg-delta",
): string {
  if (problems.length === 0)
    return "-- Every configured Auth hook function has its grants.";
  const lines = [
    "-- Auth hook grants (better-supabase doctor --fix-grants).",
    engine === "pg-delta"
      ? "-- Add this to the schema file that defines the function, then run `supabase db schema declarative sync`."
      : "-- `supabase db diff` does not carry function grants; append this to its migration.",
  ];
  for (const { fn, hook, fix } of problems) {
    const name = `${signatureOf(fn)} ([auth.hook.${hook}])`;
    switch (fix.kind) {
      case "sql":
        lines.push("", `-- ${name}`, ...fix.sql);
        break;
      case "provider":
        lines.push(
          "",
          `-- ${name} is the hook of ${fix.name}${fix.command ? `: ${fix.command}` : ""}`,
        );
        break;
      case "migration":
        lines.push(
          "",
          engine === "pg-delta"
            ? `-- ${name}: ${fix.file} grants it; run \`supabase db schema declarative sync\`, then \`supabase migration up\`.`
            : `-- ${name}: ${fix.file} grants it; run \`supabase migration up\`.`,
        );
        break;
      default: {
        const unreachable: never = fix;
        return unreachable;
      }
    }
  }
  return lines.join("\n");
}

const emptySearchPath = (fn: ExtrasHookFunction): boolean => {
  const value = fn.settings["search_path"];
  return value === "" || value === '""' || value === "''";
};

interface ClaimsSize {
  readonly bytes: number;
  readonly memberships: number;
  /** The budget's claims, summed with `octet_length` of each. */
  readonly budget: number;
  readonly truncated: boolean;
}

/** Auth's issuer shape (`{url}/auth/v1`); doctor has no project URL to put in it. */
const DOCTOR_ISSUER = "https://doctor.invalid/auth/v1";

/**
 * Runs the hook as Auth does for `userId` (as `supabase_auth_admin` when the
 * connecting role may switch to it), in a transaction that is rolled back.
 * Undefined when `auth.users` has no such user.
 */
async function withHookEvent<T>(
  db: LiveDatabase,
  userId: string,
  run: () => Promise<T>,
): Promise<T | undefined> {
  await db.query("begin");
  try {
    await db.query(`set local statement_timeout = '10s'`);
    const [user] = await db.query<{ event: string | null }>(
      `select set_config('better_supabase.hook_event', jsonb_build_object(
        'user_id', u.id,
        'authentication_method', 'password',
        'claims', jsonb_build_object(
          'aud', 'authenticated', 'role', 'authenticated', 'sub', u.id,
          'email', coalesce(u.email, ''), 'phone', coalesce(u.phone, ''),
          'app_metadata', coalesce(u.raw_app_meta_data, '{}'::jsonb),
          'user_metadata', coalesce(u.raw_user_meta_data, '{}'::jsonb),
          'aal', 'aal1', 'session_id', gen_random_uuid(),
          'is_anonymous', coalesce(u.is_anonymous, false),
          'amr', jsonb_build_array(jsonb_build_object(
            'method', 'password', 'timestamp', extract(epoch from now())::int8
          )),
          'iss', ${literal(DOCTOR_ISSUER)},
          'iat', extract(epoch from now())::int8,
          'exp', extract(epoch from now())::int8 + 3600
        )
      )::text, true) as event
      from auth.users u where u.id = ${literal(userId)}::uuid`,
    );
    if (!user?.event) return undefined;
    // Supabase's `postgres` may not become supabase_auth_admin; BS404 checks its grants.
    const [role] = await db.query<{ member: boolean }>(
      `select case when exists(select 1 from pg_roles where rolname = 'supabase_auth_admin')
        then pg_has_role('supabase_auth_admin', 'member') else false end as member`,
    );
    if (role?.member) await db.query("set local role supabase_auth_admin");
    return await run();
  } finally {
    await db.query("rollback");
  }
}

export const isRecord = (
  value: unknown,
): value is Readonly<Record<string, unknown>> =>
  typeof value === "object" && value !== null && !Array.isArray(value);

const hookCall = (fn: ExtrasHookFunction): string =>
  `${ident(fn.schema)}.${ident(fn.name)}(current_setting('better_supabase.hook_event')::jsonb) -> 'claims'`;

/** The claims the hook returns for `userId`, or undefined without that user. */
export async function hookClaims(
  db: LiveDatabase,
  fn: ExtrasHookFunction,
  userId: string,
): Promise<Readonly<Record<string, unknown>> | undefined> {
  return withHookEvent(db, userId, async () => {
    const [row] = await db.query<{ claims: unknown }>(
      `select ${hookCall(fn)} as claims`,
    );
    const claims: unknown =
      typeof row?.claims === "string" ? JSON.parse(row.claims) : row?.claims;
    return isRecord(claims) ? claims : {};
  });
}

async function hookClaimsSize(
  db: LiveDatabase,
  fn: ExtrasHookFunction,
  userId: string,
  budget: ClaimsLimits["budget"],
): Promise<ClaimsSize | undefined> {
  const budgetSql =
    budget && budget.claims.length > 0
      ? budget.claims
          .map(
            (claim) =>
              `coalesce(octet_length((c -> ${literal(claim)})::text), 0)`,
          )
          .join(" + ")
      : "0";
  const truncatedSql = budget?.truncatedClaim
    ? `c ->> ${literal(budget.truncatedClaim)} = 'true'`
    : "false";
  return withHookEvent(db, userId, async () => {
    const [row] = await db.query<{
      bytes: number | string | null;
      memberships: number | string | null;
      budget: number | string | null;
      truncated: boolean | null;
    }>(
      `select octet_length(c::text) as bytes,
        octet_length((c -> 'memberships')::text) as memberships,
        ${budgetSql} as budget,
        ${truncatedSql} as truncated
      from (select ${hookCall(fn)} as c) h`,
    );
    return {
      bytes: Number(row?.bytes ?? 0),
      memberships: Number(row?.memberships ?? 0),
      budget: Number(row?.budget ?? 0),
      truncated: row?.truncated === true,
    };
  });
}

const LOCAL_HOSTS = new Set([
  "localhost",
  "127.0.0.1",
  "[::1]",
  "host.docker.internal",
]);

/** The `secrets = ...` line of `[auth.hook.<hook>]` reads an `env()` value. */
function secretsFromEnv(text: string, hook: string): boolean {
  const start = text.search(
    new RegExp(`^\\s*\\[auth\\.hook\\.${hook}\\]`, "m"),
  );
  if (start < 0) return false;
  const rest = text.slice(start).split("\n").slice(1);
  const end = rest.findIndex((line) => /^\s*\[/.test(line));
  const section = (end < 0 ? rest : rest.slice(0, end)).join("\n");
  return /^\s*secrets\s*=\s*["']env\(/m.test(section);
}

/**
 * What is wrong with one Standard Webhooks secret (`v1,whsec_<base64>`), the
 * format Auth signs HTTP hook requests with. Never quotes the secret.
 */
function secretProblem(secret: string): string | undefined {
  const match = /^v1,whsec_([A-Za-z0-9+/]+={0,2})$/.exec(secret.trim());
  if (!match) return "is not in the `v1,whsec_<base64>` format";
  const bytes = atob(match[1]!).length;
  return bytes < 24 || bytes > 64
    ? `decodes to ${bytes} bytes; Standard Webhooks secrets are 24 to 64`
    : undefined;
}

export const HOOK_RULES: readonly Rule[] = [
  {
    code: "BS404",
    severity: "error",
    title: "Auth hook function grants",
    description:
      "Auth calls Postgres hook functions as `supabase_auth_admin`, which needs usage on the schema and execute on the function. Nobody else should be able to call them: a client calling the custom access token hook through the API sees what it adds for any user id.",
    check: (context) => [
      ...configuredHooks(context).flatMap(
        ({ config, extras }): FindingInput[] => {
          if (!extras || extras.functions.length > 0) return [];
          const location = hookLocation(context, config.hook);
          return [
            {
              message: `[auth.hook.${config.hook}] calls ${config.schema}.${config.name}, which does not exist. Sign-ins fail until it does.`,
              target: `[auth.hook.${config.hook}]`,
              ...(location ? { location } : {}),
            },
          ];
        },
      ),
      ...hookGrantProblems(context).map(
        ({ hook, fn, problems, fix }): FindingInput => ({
          message: `${signatureOf(fn)} ([auth.hook.${hook}]): ${problems.join("; ")}. ${grantFixText(fix, diffEngine(context.configToml))}`,
          target: signatureOf(fn),
          object: { kind: "function", schema: fn.schema, name: fn.name },
        }),
      ),
    ],
  },
  {
    code: "BS405",
    severity: "warning",
    title: "Custom access token hook shape",
    description: `Auth runs the custom access token hook on every sign-in and refresh. It should be \`stable\` with \`set search_path = ''\`, and the claims it returns end up in every request's cookie and Authorization header. With \`--as <user id>\` doctor calls it for that user in a transaction that is rolled back. It warns when the whole token's claims pass ${HOOK_CLAIMS_LIMIT} bytes (\`doctor.claimsLimit\` without a provider budget). When the authorization provider's hook has a \`budget\`, it also warns when the budget's claims pass its bytes (or \`doctor.claimsLimit\`), measured with \`octet_length\` of each claim.`,
    async check(context) {
      const findings: FindingInput[] = [];
      const limits = claimsLimits(context);
      for (const { config, extras } of configuredHooks(context)) {
        if (config.hook !== "custom_access_token" || !extras) continue;
        for (const fn of extras.functions) {
          const object = {
            kind: "function" as const,
            schema: fn.schema,
            name: fn.name,
          };
          const problems: string[] = [];
          if (fn.volatility !== "stable") {
            problems.push(`it is ${fn.volatility}; declare it \`stable\``);
          }
          if (!emptySearchPath(fn)) {
            problems.push(
              "it has no `set search_path = ''`; add it and qualify every table",
            );
          }
          if (problems.length > 0) {
            findings.push({
              message: `${signatureOf(fn)}: ${problems.join("; ")}.`,
              target: signatureOf(fn),
              object,
            });
          }
          if (!context.hookUser) continue;
          const db = context.database;
          if (!db || "skipped" in db || !db.session) {
            findings.push({
              severity: "info",
              message: `Measuring the hook's claims needs a direct database connection (local stack, $DATABASE_URL or --db-url-stdin)${db && "skipped" in db ? `: ${db.skipped}` : "."}`,
              target: `${signatureOf(fn)}:claims`,
            });
            continue;
          }
          try {
            const size = await hookClaimsSize(
              db,
              fn,
              context.hookUser,
              limits.budget,
            );
            if (size === undefined) {
              findings.push({
                severity: "info",
                message: `--as ${context.hookUser}: no such user in auth.users, so the hook was not called.`,
                target: `${signatureOf(fn)}:claims`,
              });
              continue;
            }
            if (
              limits.budget !== undefined &&
              size.budget > limits.budget.bytes
            ) {
              findings.push({
                message: `${signatureOf(fn)} returns ${size.budget} bytes of ${limits.budget.claims.join(" and ")} for ${context.hookUser}, over the hook's budget of ${limits.budget.bytes}. Raise the provider's budget and \`doctor.claimsLimit\` together, or move claims out of the token.`,
                target: `${signatureOf(fn)}:budget`,
                object,
              });
            }
            if (size.bytes > limits.token) {
              findings.push({
                message: `${signatureOf(fn)} returns ${size.bytes} bytes of claims for ${context.hookUser} (limit ${limits.token}, memberships ${size.memberships}). Every request carries them twice (cookie and header); keep ids and roles in the token and look up the rest.`,
                target: `${signatureOf(fn)}:claims`,
                object,
              });
            }
            if (size.truncated) {
              findings.push({
                severity: "info",
                message: `${signatureOf(fn)} sets ${limits.budget?.truncatedClaim ?? "its truncated claim"} for ${context.hookUser}: the token lists only some entries (memberships ${size.memberships} bytes). Server checks for this user need a database lookup.`,
                target: `${signatureOf(fn)}:truncated`,
                object,
              });
            }
          } catch (cause) {
            findings.push({
              message: `Calling ${signatureOf(fn)} for ${context.hookUser} failed: ${errorText(cause)}`,
              target: `${signatureOf(fn)}:claims`,
              object,
            });
          }
        }
      }
      return findings;
    },
  },
  {
    code: "BS407",
    severity: "error",
    title: "Two authorization hooks",
    description:
      "When the authorization provider's hook (`authorization.tokenHook`) owns claims such as `memberships`, `roles` or the tenant claim, a custom access token hook that also calls `better_supabase.membership_claims`, or writes one of those claims itself, gives them a second source that drifts from the provider's. Use the provider's hook and drop the extra writes. Claims the provider's hook fills from other functions (`registeredClaims`, such as `features` from `better_supabase.feature_claims`) are not reported; a hook that wraps the provider's and writes one of those claims again is.",
    check: (context) => {
      const provider = context.config.authorization;
      const hook = provider?.tokenHook;
      if (!provider || !hook) return [];
      const label = providerLabel(provider);
      const registered = new Map(
        (hook.registeredClaims ?? []).map((claim) => [
          claim.name,
          claim.function,
        ]),
      );
      const owned = ownedClaims(hook);
      const findings: FindingInput[] = [];
      for (const { config, extras } of configuredHooks(context)) {
        if (config.hook !== "custom_access_token" || !extras) continue;
        for (const fn of extras.functions) {
          if (fn.source === undefined || isProviderHook(context, fn)) continue;
          const module =
            owned.includes("memberships") && MODULE_MEMBERSHIPS.test(fn.source);
          const wrapper = wrapsProviderHook(hook, fn.source);
          const written = writtenClaims(fn.source, [
            ...owned,
            ...(wrapper ? registered.keys() : []),
          ]);
          if (!module && written.length === 0) continue;
          const location = hookLocation(context, config.hook);
          const what = [
            ...(module ? ["calls better_supabase.membership_claims"] : []),
            ...(written.length > 0 ? [`writes ${written.join(", ")}`] : []),
          ].join(" and ");
          const extra = written.filter((claim) => registered.has(claim));
          const sources = extra
            .map((claim) => `${claim} from ${registered.get(claim)!}`)
            .join(", ");
          findings.push({
            message: `${signatureOf(fn)} ${what}, but the hook of ${label} (${hook.function}) owns those claims${extra.length > 0 ? ` (it already writes ${sources})` : ""}. Keep one source: use the provider's hook and remove these writes from yours.`,
            target: signatureOf(fn),
            object: { kind: "function", schema: fn.schema, name: fn.name },
            ...(location ? { location } : {}),
          });
        }
      }
      return findings;
    },
  },
  {
    code: "BS410",
    severity: "warning",
    title: "HTTP auth hooks",
    description:
      "Auth calls an `http://` or `https://` hook with a request signed by the Standard Webhooks secret in `secrets` (`v1,whsec_<base64>`, several joined with `|`). Doctor can't read the endpoint's code, so it reports each HTTP hook and checks what it can: the secret's format, that it comes from `env()` rather than the committed file, and that a non-local endpoint uses https. Verify the request in the endpoint with `authHook` from `better-supabase/blocks/webhooks`.",
    check: (context) => {
      const toml = context.configToml;
      if (!toml) return [];
      return httpHooks(toml.document).flatMap(({ hook, uri, secrets }) => {
        const location = hookLocation(context, hook);
        const at = location ? { location } : {};
        const target = `[auth.hook.${hook}]`;
        const findings: FindingInput[] = [
          {
            severity: "info",
            message: `${target} calls ${uri.origin}${uri.pathname} over HTTP. Doctor can't check its code; verify the signature there with authHook from better-supabase/blocks/webhooks.`,
            target,
            ...at,
          },
        ];
        if (uri.protocol === "http:" && !LOCAL_HOSTS.has(uri.hostname)) {
          findings.push({
            message: `${target} sends claims and its signature to ${uri.host} over plain http. Use https.`,
            target,
            ...at,
          });
        }
        const fromEnv = secretsFromEnv(toml.text, hook);
        if (secrets === undefined || secrets.trim() === "") {
          findings.push({
            severity: "error",
            message: `${target} has no \`secrets\`, so Auth can't sign its requests. Set \`secrets = "env(AUTH_HOOK_SECRET)"\` with a \`v1,whsec_<base64>\` value.`,
            target,
            ...at,
          });
          return findings;
        }
        if (!fromEnv) {
          findings.push({
            message: `${target} has its secret written in ${toml.path}, which is committed. Move it to an env file and read it with \`secrets = "env(AUTH_HOOK_SECRET)"\`.`,
            target,
            ...at,
          });
        }
        if (fromEnv && secrets.trim().startsWith("env(")) return findings;
        const problems = secrets.split("|").flatMap((secret, index) => {
          const problem = secretProblem(secret);
          return problem ? [`secret ${index + 1} ${problem}`] : [];
        });
        if (problems.length > 0) {
          findings.push({
            severity: "error",
            message: `${target}: ${problems.join("; ")}. Auth rejects the config; generate one with \`openssl rand -base64 32\` and prefix it with \`v1,whsec_\`.`,
            target,
            ...at,
          });
        }
        return findings;
      });
    },
  },
];
