import type { ExtrasHook, ExtrasHookFunction } from "../introspect/types.ts";
import type { DoctorContext, FindingInput, Location, Rule } from "./rules.ts";

import { type PgFunctionHook, pgFunctionHooks } from "../supabase-toml.ts";
import { errorText, ident, literal, type LiveDatabase } from "./live.ts";
import { lineOf } from "./shared.ts";

/** Claims past this size make every request carry a large cookie and header. */
const HOOK_CLAIMS_LIMIT = 2048;
/** PermDock's default `supabase.hook.budget`, over `memberships` plus `attrs`. */
const PERMDOCK_CLAIMS_LIMIT = 1024;

/**
 * The BS405 limits. With PermDock, `doctor.claimsLimit` is its budget for
 * `memberships` plus `attrs` and the whole token keeps 2048; without it,
 * `doctor.claimsLimit` limits the whole token.
 */
function claimsLimits(context: DoctorContext): {
  readonly token: number;
  readonly budget: number | undefined;
} {
  const configured = context.config.doctor.claimsLimit;
  return context.permdock
    ? {
        token: HOOK_CLAIMS_LIMIT,
        budget: configured ?? PERMDOCK_CLAIMS_LIMIT,
      }
    : { token: configured ?? HOOK_CLAIMS_LIMIT, budget: undefined };
}

/** The kit function that fills PermDock's `memberships` claim. */
const KIT_MEMBERSHIPS = /better_supabase\s*\.\s*membership_claims\b/i;
const PERMDOCK_CALL = /\bpermdock\w*\s*\(|permdock\s*\./i;
/** Only PermDock's generated hook sets this claim, so it marks that hook's body. */
const PERMDOCK_HOOK = /'\{\s*(?:claims\s*,\s*)?memberships_truncated\s*\}'/i;

const escapeRegExp = (text: string): string =>
  text.replaceAll(/[.*+?^${}()|[\]\\]/g, "\\$&");

/** The claims PermDock's hook writes that a second writer would contradict. */
function ownedClaims(tenant: string): readonly string[] {
  return ["roles", "user_role", "memberships", tenant];
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

interface ConfiguredHook {
  readonly config: PgFunctionHook;
  /** Absent when the snapshot predates the hook (or `hooks` introspection). */
  readonly extras: ExtrasHook | undefined;
}

/** Hooks enabled in `config.toml`, matched with their introspected functions. */
function configuredHooks(context: DoctorContext): ConfiguredHook[] {
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

const signatureOf = (fn: ExtrasHookFunction): string =>
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

const emptySearchPath = (fn: ExtrasHookFunction): boolean => {
  const value = fn.settings["search_path"];
  return value === "" || value === '""' || value === "''";
};

/**
 * Runs the hook as Auth does for `userId` (as `supabase_auth_admin` when the
 * connecting role may switch to it), in a transaction that is rolled back.
 */
interface ClaimsSize {
  readonly bytes: number;
  readonly memberships: number;
  /** `memberships` plus `attrs`, measured as PermDock's hook measures its budget. */
  readonly budget: number;
  readonly truncated: boolean;
}

async function hookClaimsSize(
  db: LiveDatabase,
  fn: ExtrasHookFunction,
  userId: string,
): Promise<ClaimsSize | undefined> {
  const call = `${ident(fn.schema)}.${ident(fn.name)}`;
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
    const [row] = await db.query<{
      bytes: number | string | null;
      memberships: number | string | null;
      attrs: number | string | null;
      truncated: boolean | null;
    }>(
      `select octet_length(c::text) as bytes,
        octet_length((c -> 'memberships')::text) as memberships,
        octet_length((c -> 'attrs')::text) as attrs,
        c ->> 'memberships_truncated' = 'true' as truncated
      from (select ${call}(current_setting('better_supabase.hook_event')::jsonb) -> 'claims' as c) h`,
    );
    const memberships = Number(row?.memberships ?? 0);
    return {
      bytes: Number(row?.bytes ?? 0),
      memberships,
      budget: memberships + Number(row?.attrs ?? 0),
      truncated: row?.truncated === true,
    };
  } finally {
    await db.query("rollback");
  }
}

export const HOOK_RULES: readonly Rule[] = [
  {
    code: "BS404",
    severity: "error",
    title: "Auth hook function grants",
    description:
      "Auth calls Postgres hook functions as `supabase_auth_admin`, which needs usage on the schema and execute on the function. Nobody else should be able to call them: a client calling the custom access token hook through the API sees what it adds for any user id.",
    check: (context) =>
      configuredHooks(context).flatMap(({ config, extras }): FindingInput[] => {
        if (!extras) return [];
        const location = hookLocation(context, config.hook);
        const where = location ? { location } : {};
        if (extras.functions.length === 0) {
          return [
            {
              message: `[auth.hook.${config.hook}] calls ${config.schema}.${config.name}, which does not exist. Sign-ins fail until it does.`,
              target: `[auth.hook.${config.hook}]`,
              ...where,
            },
          ];
        }
        return extras.functions.flatMap((fn): FindingInput[] => {
          const { problems, fix } = grantProblems(fn);
          if (problems.length === 0) return [];
          return [
            {
              message: `${signatureOf(fn)} ([auth.hook.${config.hook}]): ${problems.join("; ")}. Run:\n${fix.join("\n")}`,
              target: signatureOf(fn),
              object: { kind: "function", schema: fn.schema, name: fn.name },
            },
          ];
        });
      }),
  },
  {
    code: "BS405",
    severity: "warning",
    title: "Custom access token hook shape",
    description: `Auth runs the custom access token hook on every sign-in and refresh. It should be \`stable\` with \`set search_path = ''\`, and the claims it returns end up in every request's cookie and Authorization header. With \`--as <user id>\` doctor calls it for that user in a transaction that is rolled back. It warns when the whole token's claims pass ${HOOK_CLAIMS_LIMIT} bytes (\`doctor.claimsLimit\` without PermDock). With a \`permdock.config.ts\` it also warns when \`memberships\` plus \`attrs\` pass PermDock's budget, ${PERMDOCK_CLAIMS_LIMIT} bytes or \`doctor.claimsLimit\`, measured with \`octet_length\` as PermDock's hook measures it.`,
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
          const shape: string[] = [];
          if (fn.volatility !== "stable") {
            shape.push(`it is ${fn.volatility}; declare it \`stable\``);
          }
          if (!emptySearchPath(fn)) {
            shape.push(
              "it has no `set search_path = ''`; add it and qualify every table",
            );
          }
          if (shape.length > 0) {
            findings.push({
              message: `${signatureOf(fn)}: ${shape.join("; ")}.`,
              target: signatureOf(fn),
              object,
            });
          }
          if (!context.hookUser) continue;
          const db = context.database;
          if (!db || "skipped" in db || !db.session) {
            findings.push({
              severity: "info",
              message: `Measuring the hook's claims needs a direct database connection (local stack or --db-url)${db && "skipped" in db ? `: ${db.skipped}` : "."}`,
              target: `${signatureOf(fn)}:claims`,
            });
            continue;
          }
          try {
            const size = await hookClaimsSize(db, fn, context.hookUser);
            if (size === undefined) {
              findings.push({
                severity: "info",
                message: `--as ${context.hookUser}: no such user in auth.users, so the hook was not called.`,
                target: `${signatureOf(fn)}:claims`,
              });
              continue;
            }
            if (limits.budget !== undefined && size.budget > limits.budget) {
              findings.push({
                message: `${signatureOf(fn)} returns ${size.budget} bytes of memberships and attrs for ${context.hookUser}, over PermDock's budget of ${limits.budget} (memberships ${size.memberships}). Raise \`supabase.hook.budget\` and \`doctor.claimsLimit\` together, or move attrs out of the token.`,
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
                message: `${signatureOf(fn)} sets memberships_truncated for ${context.hookUser}: the token lists only some memberships (${size.memberships} bytes). Server checks for this user need a database lookup (PermDock's claimsFirst falls back to one).`,
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
      "A `permdock.config.ts` (or a hook that calls PermDock's functions) means PermDock writes `user_role`, `roles`, `memberships` and the tenant claim (`claims.tenant`) into the token. A custom access token hook that also calls `better_supabase.membership_claims`, or writes one of those claims itself, gives them a second source that drifts from PermDock's. Generate the hook with `permdock supabase hook generate` and drop the extra writes. Other claims, such as the entitlements module's `features`, are not PermDock's and are not reported.",
    check: (context) =>
      configuredHooks(context).flatMap(({ config, extras }): FindingInput[] => {
        if (config.hook !== "custom_access_token" || !extras) return [];
        return extras.functions.flatMap((fn): FindingInput[] => {
          if (fn.source === undefined) return [];
          const kit = KIT_MEMBERSHIPS.test(fn.source);
          const written = PERMDOCK_HOOK.test(fn.source)
            ? []
            : writtenClaims(
                fn.source,
                ownedClaims(context.config.claims.tenant),
              );
          if (!kit && written.length === 0) return [];
          const permdock =
            context.permdock ??
            (PERMDOCK_CALL.test(fn.source) ? "the hook body" : undefined);
          if (!permdock) return [];
          const location = hookLocation(context, config.hook);
          const what = [
            ...(kit ? ["calls better_supabase.membership_claims"] : []),
            ...(written.length > 0 ? [`writes ${written.join(", ")}`] : []),
          ].join(" and ");
          return [
            {
              message: `${signatureOf(fn)} ${what}, and ${permdock} says PermDock owns those claims. Keep one source: run \`permdock supabase hook generate\` and remove these writes from your hook.`,
              target: signatureOf(fn),
              object: { kind: "function", schema: fn.schema, name: fn.name },
              ...(location ? { location } : {}),
            },
          ];
        });
      }),
  },
];
