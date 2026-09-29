import type { ExtrasHook, ExtrasHookFunction } from '../introspect/types.ts';
import type { DoctorContext, FindingInput, Location, Rule } from './rules.ts';

import { type PgFunctionHook, pgFunctionHooks } from '../supabase-toml.ts';
import { errorText, ident, literal, type LiveDatabase } from './live.ts';
import { lineOf } from './shared.ts';

/** Claims past this size make every request carry a large cookie and header. */
export const HOOK_CLAIMS_LIMIT = 2048;

const API_ROLES = ['authenticated', 'anon'] as const;

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
  if (!fn.schemaUsage.includes('supabase_auth_admin')) {
    problems.push(`supabase_auth_admin has no usage on schema ${fn.schema}`);
    fix.push(`grant usage on schema ${fn.schema} to supabase_auth_admin;`);
  }
  if (!fn.execute.includes('supabase_auth_admin')) {
    problems.push('supabase_auth_admin may not execute it');
    fix.push(
      `grant execute on function ${signatureOf(fn)} to supabase_auth_admin;`,
    );
  }
  const exposedTo = API_ROLES.filter((role) => fn.execute.includes(role));
  if (exposedTo.length > 0 || fn.publicExecute) {
    const roles = [...exposedTo, ...(fn.publicExecute ? ['public'] : [])];
    problems.push(
      `${roles.join(', ')} may execute it, so any client can call it through the API`,
    );
    fix.push(
      `revoke execute on function ${signatureOf(fn)} from authenticated, anon, public;`,
    );
  }
  return { problems, fix };
}

const emptySearchPath = (fn: ExtrasHookFunction): boolean => {
  const value = fn.settings['search_path'];
  return value === '' || value === '""' || value === "''";
};

/**
 * Runs the hook as Auth does for `userId` (as `supabase_auth_admin` when the
 * connecting role may switch to it), in a transaction that is rolled back.
 */
async function hookClaimsBytes(
  db: LiveDatabase,
  fn: ExtrasHookFunction,
  userId: string,
): Promise<number | undefined> {
  const call = `${ident(fn.schema)}.${ident(fn.name)}`;
  await db.query('begin');
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
    if (role?.member) await db.query('set local role supabase_auth_admin');
    const [row] = await db.query<{ bytes: number | string | null }>(
      `select octet_length((${call}(current_setting('better_supabase.hook_event')::jsonb) -> 'claims')::text) as bytes`,
    );
    return row?.bytes === null || row?.bytes === undefined
      ? 0
      : Number(row.bytes);
  } finally {
    await db.query('rollback');
  }
}

export const HOOK_RULES: readonly Rule[] = [
  {
    code: 'BS404',
    severity: 'error',
    title: 'Auth hook function grants',
    description:
      'Auth calls Postgres hook functions as `supabase_auth_admin`, which needs usage on the schema and execute on the function. Nobody else should be able to call them: a client calling the custom access token hook through the API sees what it adds for any user id.',
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
              message: `${signatureOf(fn)} ([auth.hook.${config.hook}]): ${problems.join('; ')}. Run:\n${fix.join('\n')}`,
              target: signatureOf(fn),
              object: { kind: 'function', schema: fn.schema, name: fn.name },
            },
          ];
        });
      }),
  },
  {
    code: 'BS405',
    severity: 'warning',
    title: 'Custom access token hook shape',
    description: `Auth runs the custom access token hook on every sign-in and refresh. It should be \`stable\` with \`set search_path = ''\`, and the claims it returns end up in every request's cookie and Authorization header. With \`--as <user id>\` doctor calls it for that user in a transaction that is rolled back and warns above ${HOOK_CLAIMS_LIMIT} bytes of claims.`,
    async check(context) {
      const findings: FindingInput[] = [];
      for (const { config, extras } of configuredHooks(context)) {
        if (config.hook !== 'custom_access_token' || !extras) continue;
        for (const fn of extras.functions) {
          const object = {
            kind: 'function' as const,
            schema: fn.schema,
            name: fn.name,
          };
          const shape: string[] = [];
          if (fn.volatility !== 'stable') {
            shape.push(`it is ${fn.volatility}; declare it \`stable\``);
          }
          if (!emptySearchPath(fn)) {
            shape.push(
              "it has no `set search_path = ''`; add it and qualify every table",
            );
          }
          if (shape.length > 0) {
            findings.push({
              message: `${signatureOf(fn)}: ${shape.join('; ')}.`,
              target: signatureOf(fn),
              object,
            });
          }
          if (!context.hookUser) continue;
          const db = context.database;
          if (!db || 'skipped' in db || !db.session) {
            findings.push({
              severity: 'info',
              message: `Measuring the hook's claims needs a direct database connection (local stack or --db-url)${db && 'skipped' in db ? `: ${db.skipped}` : '.'}`,
              target: `${signatureOf(fn)}:claims`,
            });
            continue;
          }
          try {
            const bytes = await hookClaimsBytes(db, fn, context.hookUser);
            if (bytes === undefined) {
              findings.push({
                severity: 'info',
                message: `--as ${context.hookUser}: no such user in auth.users, so the hook was not called.`,
                target: `${signatureOf(fn)}:claims`,
              });
            } else if (bytes > HOOK_CLAIMS_LIMIT) {
              findings.push({
                message: `${signatureOf(fn)} returns ${bytes} bytes of claims for ${context.hookUser} (limit ${HOOK_CLAIMS_LIMIT}). Every request carries them twice (cookie and header); keep ids and roles in the token and look up the rest.`,
                target: `${signatureOf(fn)}:claims`,
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
];
