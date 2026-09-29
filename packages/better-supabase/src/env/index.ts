import type { StandardSchemaV1 } from '@standard-schema/spec';
import type { SupabaseEnv } from '@supabase/server';

/** Validated Supabase settings. Only `publicEnv()` of it is safe to ship to a browser. */
export interface BetterSupabaseEnv {
  readonly url: string;
  readonly publishableKey: string;
  readonly secretKey?: string;
  /** Named secret keys from `SUPABASE_SECRET_KEYS`, including `default` when `secretKey` is set. */
  readonly secretKeys?: Readonly<Record<string, string>>;
  /** `SUPABASE_JWKS_URL`, or `<url>/auth/v1/.well-known/jwks.json`. */
  readonly jwksUrl: URL;
  /** Direct Postgres connection string (`SUPABASE_DB_URL` / `DATABASE_URL`). */
  readonly dbUrl?: string;
  /** Project ref for hosted projects (`<ref>.supabase.co`). */
  readonly projectRef?: string;
  /** `SUPABASE_READ_URL`: a read replica or the `<ref>-all` load balancer, for reads. */
  readonly readUrl?: string;
}

export interface PublicEnv {
  readonly url: string;
  readonly publishableKey: string;
}

export type EnvSource = Readonly<Record<string, string | undefined>>;

export interface EnvIssue {
  /** The variable names that were checked, first one preferred. */
  readonly variables: readonly string[];
  readonly message: string;
}

export interface EnvOptions {
  /** Settings that must be present. `url` and `publishableKey` always are. */
  readonly require?: readonly ('secretKey' | 'dbUrl')[];
}

export type EnvResult =
  | {
      readonly ok: true;
      readonly env: BetterSupabaseEnv;
      readonly issues?: undefined;
    }
  | {
      readonly ok: false;
      readonly env?: undefined;
      readonly issues: readonly EnvIssue[];
    };

const PREFIXES = [
  '',
  'NEXT_PUBLIC_',
  'VITE_',
  'PUBLIC_',
  'EXPO_PUBLIC_',
  'NUXT_PUBLIC_',
] as const;

export const ENV_VARIABLES: {
  readonly url: readonly string[];
  readonly publishableKey: readonly string[];
  readonly secretKey: readonly string[];
  readonly dbUrl: readonly string[];
  readonly jwksUrl: readonly string[];
  readonly readUrl: readonly string[];
} = {
  url: PREFIXES.map((prefix) => `${prefix}SUPABASE_URL`),
  publishableKey: PREFIXES.flatMap((prefix) => [
    `${prefix}SUPABASE_PUBLISHABLE_KEY`,
    `${prefix}SUPABASE_PUBLISHABLE_DEFAULT_KEY`,
  ]),
  secretKey: ['SUPABASE_SECRET_KEY'],
  dbUrl: ['SUPABASE_DB_URL', 'DATABASE_URL'],
  jwksUrl: ['SUPABASE_JWKS_URL'],
  readUrl: ['SUPABASE_READ_URL'],
};

const LOOPBACK = /^(localhost|127(?:\.\d{1,3}){3}|\[::1\])$/;
const HOSTED = /^([a-z0-9]{20})\.supabase\.co$/;

export class EnvValidationError extends Error {
  override readonly name = 'EnvValidationError';
  readonly issues: readonly EnvIssue[];

  constructor(issues: readonly EnvIssue[]) {
    super(
      `Invalid Supabase environment:\n${issues.map((issue) => `  - ${issue.variables[0] ?? 'env'}: ${issue.message}`).join('\n')}`,
    );
    this.issues = issues;
  }
}

function first(
  source: EnvSource,
  names: readonly string[],
): string | undefined {
  for (const name of names) {
    const value = source[name]?.trim();
    if (value) return value;
  }
  return undefined;
}

/** `SUPABASE_*_KEYS` JSON objects, as `@supabase/server` reads them. */
function keySet(
  source: EnvSource,
  name: string,
  kind: 'publishable' | 'secret',
  issues: EnvIssue[],
): Readonly<Record<string, string>> | undefined {
  const raw = source[name];
  if (!raw) return undefined;
  let parsed: unknown;
  try {
    parsed = JSON.parse(raw);
  } catch {
    parsed = undefined;
  }
  const entries =
    typeof parsed === 'object' && parsed !== null && !Array.isArray(parsed)
      ? Object.entries(parsed)
      : [];
  if (
    entries.length === 0 ||
    entries.some(([, value]) => typeof value !== 'string')
  ) {
    issues.push({
      variables: [name],
      message: 'must be a JSON object of key names to keys',
    });
    return undefined;
  }
  const keys: Record<string, string> = {};
  for (const [key, value] of entries as [string, string][]) {
    if (checkKey(value, kind, [name], issues)) keys[key] = value;
  }
  return keys;
}

function preferred(
  keys: Readonly<Record<string, string>> | undefined,
): string | undefined {
  if (!keys) return undefined;
  return keys['default'] ?? Object.values(keys)[0];
}

function checkUrl(
  value: string,
  variables: readonly string[],
  issues: EnvIssue[],
): URL | undefined {
  let url: URL;
  try {
    url = new URL(value);
  } catch {
    issues.push({ variables, message: 'is not a valid URL' });
    return undefined;
  }
  if (url.protocol === 'https:') return url;
  if (url.protocol === 'http:' && LOOPBACK.test(url.hostname)) return url;
  issues.push({
    variables,
    message:
      'must use https (http is only allowed for localhost / 127.0.0.1 / [::1])',
  });
  return undefined;
}

function checkKey(
  value: string,
  kind: 'publishable' | 'secret',
  variables: readonly string[],
  issues: EnvIssue[],
): boolean {
  if (value.startsWith(`sb_${kind}_`)) return true;
  if (value.startsWith('eyJ')) {
    issues.push({
      variables,
      message: `is a legacy JWT key; use the new sb_${kind}_ key (Project Settings > API Keys)`,
    });
  } else if (
    value.startsWith(kind === 'publishable' ? 'sb_secret_' : 'sb_publishable_')
  ) {
    issues.push({
      variables,
      message:
        kind === 'publishable'
          ? 'holds a secret key; never expose sb_secret_ keys as publishable'
          : 'holds a publishable key, not a secret key',
    });
  } else {
    issues.push({ variables, message: `must start with sb_${kind}_` });
  }
  return false;
}

/**
 * Reads and validates Supabase settings. Accepts the `SUPABASE_`,
 * `NEXT_PUBLIC_`, `VITE_`, `PUBLIC_`, `EXPO_PUBLIC_` and `NUXT_PUBLIC_`
 * spellings. Issues name variables, never values.
 */
export function parseEnv(
  source: EnvSource,
  options: EnvOptions = {},
): EnvResult {
  const issues: EnvIssue[] = [];
  const required = new Set(options.require ?? []);

  const rawUrl = first(source, ENV_VARIABLES.url);
  const url = rawUrl ? checkUrl(rawUrl, ENV_VARIABLES.url, issues) : undefined;
  if (!rawUrl)
    issues.push({ variables: ENV_VARIABLES.url, message: 'is not set' });

  const publishableKeys = keySet(
    source,
    'SUPABASE_PUBLISHABLE_KEYS',
    'publishable',
    issues,
  );
  const singlePublishable = first(source, ENV_VARIABLES.publishableKey);
  const publishableKey = singlePublishable ?? preferred(publishableKeys);
  if (!publishableKey) {
    issues.push({
      variables: ENV_VARIABLES.publishableKey,
      message: 'is not set',
    });
  } else if (singlePublishable) {
    checkKey(
      publishableKey,
      'publishable',
      ENV_VARIABLES.publishableKey,
      issues,
    );
  }

  const namedSecrets = keySet(source, 'SUPABASE_SECRET_KEYS', 'secret', issues);
  const singleSecret = first(source, ENV_VARIABLES.secretKey);
  const secretKey = singleSecret ?? preferred(namedSecrets);
  if (singleSecret)
    checkKey(singleSecret, 'secret', ENV_VARIABLES.secretKey, issues);
  else if (!secretKey && required.has('secretKey'))
    issues.push({ variables: ENV_VARIABLES.secretKey, message: 'is not set' });

  const dbUrl = first(source, ENV_VARIABLES.dbUrl);
  if (dbUrl && !/^postgres(ql)?:\/\//.test(dbUrl)) {
    issues.push({
      variables: ENV_VARIABLES.dbUrl,
      message: 'must be a postgres:// connection string',
    });
  } else if (!dbUrl && required.has('dbUrl')) {
    issues.push({ variables: ENV_VARIABLES.dbUrl, message: 'is not set' });
  }

  const rawJwks = first(source, ENV_VARIABLES.jwksUrl);
  const jwksOverride = rawJwks
    ? checkUrl(rawJwks, ENV_VARIABLES.jwksUrl, issues)
    : undefined;

  const rawRead = first(source, ENV_VARIABLES.readUrl);
  const readUrl = rawRead
    ? checkUrl(rawRead, ENV_VARIABLES.readUrl, issues)
    : undefined;

  if (issues.length > 0 || !url || !publishableKey)
    return { ok: false, issues };

  const base = url.href.replace(/\/+$/, '');
  const projectRef = HOSTED.exec(url.hostname)?.[1];
  return {
    ok: true,
    env: {
      url: base,
      publishableKey,
      jwksUrl: jwksOverride ?? new URL(`${base}/auth/v1/.well-known/jwks.json`),
      ...(secretKey
        ? {
            secretKey,
            secretKeys: { ...namedSecrets, default: secretKey },
          }
        : {}),
      ...(dbUrl ? { dbUrl } : {}),
      ...(projectRef ? { projectRef } : {}),
      ...(readUrl ? { readUrl: readUrl.href.replace(/\/+$/, '') } : {}),
    },
  };
}

function processEnv(): EnvSource {
  const runtime = globalThis as { process?: { env?: EnvSource } };
  return runtime.process?.env ?? {};
}

/** Like `parseEnv`, but throws `EnvValidationError`. Reads `process.env` by default. */
export function loadEnv(
  source: EnvSource = processEnv(),
  options: EnvOptions = {},
): BetterSupabaseEnv {
  const result = parseEnv(source, options);
  if (!result.ok) throw new EnvValidationError(result.issues);
  return result.env;
}

/** The env validator as a Standard Schema, for t3-env, framework config or any validator slot. */
export function envSchema(
  options: EnvOptions = {},
): StandardSchemaV1<EnvSource, BetterSupabaseEnv> {
  return {
    '~standard': {
      version: 1,
      vendor: 'better-supabase',
      validate(value) {
        if (typeof value !== 'object' || value === null) {
          return { issues: [{ message: 'Expected an environment object' }] };
        }
        const result = parseEnv(value as EnvSource, options);
        if (result.ok) return { value: result.env };
        return {
          issues: result.issues.map((issue) => ({
            message: `${issue.variables[0] ?? 'env'} ${issue.message}`,
            path: issue.variables.slice(0, 1),
          })),
        };
      },
    },
  };
}

/** The parts that are safe in client bundles. */
export function publicEnv(env: BetterSupabaseEnv): PublicEnv {
  return { url: env.url, publishableKey: env.publishableKey };
}

/** Converts to `@supabase/server`'s `SupabaseEnv` (the `env` option of `withSupabase`). */
export function toServerEnv(env: BetterSupabaseEnv): SupabaseEnv {
  return {
    url: env.url,
    publishableKeys: { default: env.publishableKey },
    secretKeys:
      env.secretKeys ?? (env.secretKey ? { default: env.secretKey } : {}),
    jwks: env.jwksUrl,
  };
}
