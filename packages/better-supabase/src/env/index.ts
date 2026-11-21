import type { StandardSchemaV1 } from "@standard-schema/spec";
import type { SupabaseEnv } from "@supabase/server";

import type { EnvIssue } from "./public.ts";

import { EnvValidationError, checkKey, checkUrl } from "./public.ts";

export { EnvValidationError };

export type { EnvIssue };

/**
 * Validated Supabase settings. Only `publicEnv()` of it is safe to ship to a
 * browser.
 */
export interface BetterSupabaseEnv {
  readonly url: string;
  readonly publishableKey: string;
  readonly secretKey?: string;
  /**
   * Named secret keys from `SUPABASE_SECRET_KEYS`, including `default` when
   * `secretKey` is set.
   */
  readonly secretKeys?: Readonly<Record<string, string>>;
  /** `SUPABASE_JWKS_URL`, or `<url>/auth/v1/.well-known/jwks.json`. */
  readonly jwksUrl: URL;
  /** `SUPABASE_JWKS`: inline keys, used instead of fetching `jwksUrl`. */
  readonly jwks?: InlineJwks;
  /**
   * Postgres connection string: `SUPABASE_DB_URL`, `DATABASE_URL`, then the
   * Vercel integration's `POSTGRES_URL` (pooled) and
   * `POSTGRES_URL_NON_POOLING`.
   */
  readonly dbUrl?: string;
  /** Project ref for hosted projects (`<ref>.supabase.co`). */
  readonly projectRef?: string;
  /**
   * `SUPABASE_READ_URL`: a read replica or the `<ref>-all` load balancer, for
   * reads.
   */
  readonly readUrl?: string;
  /**
   * `SUPABASE_JWT_SECRET`: the shared HS256 secret Supabase Lite signs user
   * tokens with (`auth.jwt_secret`). Server-only; read with `backend: "lite"`.
   */
  readonly jwtSecret?: string;
}

/** A JSON Web Key Set, as `@supabase/server` verifies with it. */
export type InlineJwks = Exclude<SupabaseEnv["jwks"], URL | null>;

export interface PublicEnv {
  readonly url: string;
  readonly publishableKey: string;
}

export type EnvSource = Readonly<Record<string, string | undefined>>;

export interface EnvOptions {
  /** Settings that must be present. `url` and `publishableKey` always are. */
  readonly require?: readonly ("secretKey" | "dbUrl")[];
  /**
   * The custom prefix a Vercel Marketplace integration was connected with
   * (`DB1` reads `DB1_SUPABASE_URL`, `DB1_POSTGRES_URL` and so on). Prefixed
   * names win over the plain ones. Letters, digits and underscores, starting
   * with a letter; Vercel adds the underscore.
   */
  readonly prefix?: string;
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
  "",
  "NEXT_PUBLIC_",
  "VITE_",
  "PUBLIC_",
  "EXPO_PUBLIC_",
  "NUXT_PUBLIC_",
] as const;

export const ENV_VARIABLES: {
  readonly url: readonly string[];
  readonly publishableKey: readonly string[];
  readonly secretKey: readonly string[];
  readonly dbUrl: readonly string[];
  readonly jwksUrl: readonly string[];
  readonly jwks: readonly string[];
  readonly readUrl: readonly string[];
  readonly jwtSecret: readonly string[];
} = {
  url: PREFIXES.map((prefix) => `${prefix}SUPABASE_URL`),
  publishableKey: PREFIXES.flatMap((prefix) => [
    `${prefix}SUPABASE_PUBLISHABLE_KEY`,
    `${prefix}SUPABASE_PUBLISHABLE_DEFAULT_KEY`,
  ]),
  secretKey: ["SUPABASE_SECRET_KEY"],
  dbUrl: [
    "SUPABASE_DB_URL",
    "DATABASE_URL",
    "POSTGRES_URL",
    "POSTGRES_URL_NON_POOLING",
  ],
  jwksUrl: ["SUPABASE_JWKS_URL"],
  jwks: ["SUPABASE_JWKS"],
  readUrl: ["SUPABASE_READ_URL"],
  jwtSecret: ["SUPABASE_JWT_SECRET"],
};

const HOSTED = /^([a-z0-9]{20})\.supabase\.co$/;

const PREFIX_NAME = /^[A-Za-z][A-Za-z0-9_]*$/;

/**
 * The project ref of a hosted project URL (`https://<ref>.supabase.co`), or
 * `undefined` for a local, custom-domain or malformed URL.
 */
export function projectRefOf(url: string): string | undefined {
  try {
    return HOSTED.exec(new URL(url).hostname)?.[1];
  } catch {
    return undefined;
  }
}

/**
 * `source` with each `<prefix>_NAME` also set as `NAME`, the way Vercel names
 * the variables of an integration connected with a custom prefix. A prefixed
 * name replaces the plain one; empty values are skipped. The prefix may end
 * with the underscore Vercel adds.
 */
export function withEnvPrefix(source: EnvSource, prefix: string): EnvSource {
  const bare = prefix.replace(/_+$/, "");

  if (!PREFIX_NAME.test(bare)) {
    throw new TypeError(
      `better-supabase: the env prefix must start with a letter and hold only letters, digits and underscores, got "${prefix}"`,
    );
  }

  const start = `${bare}_`;
  const merged: Record<string, string | undefined> = { ...source };

  for (const [name, value] of Object.entries(source)) {
    if (name.startsWith(start) && name.length > start.length && value) {
      merged[name.slice(start.length)] = value;
    }
  }

  return merged;
}

const LEGACY_PUBLISHABLE = [
  "SUPABASE_ANON_KEY",
  "NEXT_PUBLIC_SUPABASE_ANON_KEY",
  "VITE_SUPABASE_ANON_KEY",
  "PUBLIC_SUPABASE_ANON_KEY",
  "EXPO_PUBLIC_SUPABASE_ANON_KEY",
  "NUXT_PUBLIC_SUPABASE_ANON_KEY",
] as const;

/** The legacy names in `names` that `source` sets, for a "not set" message. */
function legacyNote(
  source: EnvSource,
  names: readonly string[],
  replacement: string,
): string {
  const found = names.find((name) => source[name]?.trim());

  return found === undefined
    ? "is not set"
    : `is not set. ${found} is the legacy name and is not read; set ${replacement} to an sb_ key (Project Settings > API Keys)`;
}

function first(
  source: EnvSource,
  names: readonly string[],
): string | undefined {
  for (const name of names) {
    const value = source[name]?.trim();

    if (value) {
      return value;
    }
  }

  return undefined;
}

/** `SUPABASE_*_KEYS` JSON objects, as `@supabase/server` reads them. */
function keySet(
  source: EnvSource,
  name: string,
  kind: "publishable" | "secret",
  issues: EnvIssue[],
): Readonly<Record<string, string>> | undefined {
  const raw = source[name];

  if (!raw) {
    return undefined;
  }

  let parsed: unknown;

  try {
    parsed = JSON.parse(raw);
  } catch {
    parsed = undefined;
  }

  const entries =
    typeof parsed === "object" && parsed !== null && !Array.isArray(parsed)
      ? Object.entries(parsed)
      : [];

  if (
    entries.length === 0 ||
    entries.some(([, value]) => typeof value !== "string")
  ) {
    issues.push({
      variables: [name],
      message: "must be a JSON object of key names to keys",
    });

    return undefined;
  }

  const keys: Record<string, string> = {};

  // SAFETY: the filter above kept only entries with string values.
  for (const [key, value] of entries as [string, string][]) {
    if (checkKey(value, kind, [name], issues)) {
      keys[key] = value;
    }
  }

  return keys;
}

function preferred(
  keys: Readonly<Record<string, string>> | undefined,
): string | undefined {
  if (!keys) {
    return undefined;
  }

  return keys["default"] ?? Object.values(keys)[0];
}

function isJwk(value: unknown): boolean {
  return (
    typeof value === "object" &&
    value !== null &&
    "kty" in value &&
    typeof value.kty === "string"
  );
}

/**
 * At least one key, each an object with a string `kty`, the shape the verifier
 * reads.
 */
function isJwkList(value: unknown): value is InlineJwks["keys"] {
  return Array.isArray(value) && value.length > 0 && value.every(isJwk);
}

/** `SUPABASE_JWKS` as `@supabase/server` reads it: `{"keys":[...]}` or `[...]`. */
function checkJwks(raw: string, issues: EnvIssue[]): InlineJwks | undefined {
  let parsed: unknown;

  try {
    parsed = JSON.parse(raw);
  } catch {
    issues.push({
      variables: ENV_VARIABLES.jwks,
      message: 'must be JSON: {"keys":[...]} or [...]',
    });

    return undefined;
  }

  const keys: unknown =
    typeof parsed === "object" && parsed !== null && !Array.isArray(parsed)
      ? "keys" in parsed
        ? parsed.keys
        : undefined
      : parsed;

  if (!isJwkList(keys)) {
    issues.push({
      variables: ENV_VARIABLES.jwks,
      message: "must hold at least one JSON Web Key with a kty",
    });

    return undefined;
  }

  return { keys };
}

/**
 * Reads and validates Supabase settings. Accepts the `SUPABASE_`,
 * `NEXT_PUBLIC_`, `VITE_`, `PUBLIC_`, `EXPO_PUBLIC_` and `NUXT_PUBLIC_`
 * spellings. Issues name variables, never values.
 */
export function parseEnv(
  rawSource: EnvSource,
  options: EnvOptions = {},
): EnvResult {
  const source =
    options.prefix === undefined
      ? rawSource
      : withEnvPrefix(rawSource, options.prefix);

  const issues: EnvIssue[] = [];
  const required = new Set(options.require);

  const rawUrl = first(source, ENV_VARIABLES.url);
  const url = rawUrl ? checkUrl(rawUrl, ENV_VARIABLES.url, issues) : undefined;

  if (!rawUrl) {
    issues.push({ variables: ENV_VARIABLES.url, message: "is not set" });
  }

  const publishableKeys = keySet(
    source,
    "SUPABASE_PUBLISHABLE_KEYS",
    "publishable",
    issues,
  );

  const singlePublishable = first(source, ENV_VARIABLES.publishableKey);
  const publishableKey = singlePublishable ?? preferred(publishableKeys);

  if (!publishableKey) {
    issues.push({
      variables: ENV_VARIABLES.publishableKey,
      message: legacyNote(
        source,
        LEGACY_PUBLISHABLE,
        "SUPABASE_PUBLISHABLE_KEY",
      ),
    });
  } else if (singlePublishable) {
    checkKey(
      publishableKey,
      "publishable",
      ENV_VARIABLES.publishableKey,
      issues,
    );
  }

  const namedSecrets = keySet(source, "SUPABASE_SECRET_KEYS", "secret", issues);
  const singleSecret = first(source, ENV_VARIABLES.secretKey);
  const secretKey = singleSecret ?? preferred(namedSecrets);

  if (singleSecret) {
    checkKey(singleSecret, "secret", ENV_VARIABLES.secretKey, issues);
  } else if (!secretKey && required.has("secretKey")) {
    issues.push({
      variables: ENV_VARIABLES.secretKey,
      message: legacyNote(
        source,
        ["SUPABASE_SERVICE_ROLE_KEY"],
        "SUPABASE_SECRET_KEY",
      ),
    });
  }

  const dbUrl = first(source, ENV_VARIABLES.dbUrl);

  if (dbUrl && !/^postgres(ql)?:\/\//.test(dbUrl)) {
    issues.push({
      variables: ENV_VARIABLES.dbUrl,
      message: "must be a postgres:// connection string",
    });
  } else if (!dbUrl && required.has("dbUrl")) {
    issues.push({ variables: ENV_VARIABLES.dbUrl, message: "is not set" });
  }

  const rawJwks = first(source, ENV_VARIABLES.jwksUrl);

  const jwksOverride = rawJwks
    ? checkUrl(rawJwks, ENV_VARIABLES.jwksUrl, issues)
    : undefined;

  const rawInline = first(source, ENV_VARIABLES.jwks);
  const jwks = rawInline ? checkJwks(rawInline, issues) : undefined;

  const rawRead = first(source, ENV_VARIABLES.readUrl);

  const readUrl = rawRead
    ? checkUrl(rawRead, ENV_VARIABLES.readUrl, issues)
    : undefined;

  const jwtSecret = first(source, ENV_VARIABLES.jwtSecret);

  if (jwtSecret !== undefined && jwtSecret.length < 32) {
    issues.push({
      variables: ENV_VARIABLES.jwtSecret,
      message: "must be at least 32 characters",
    });
  }

  if (issues.length > 0 || !url || !publishableKey) {
    return { ok: false, issues };
  }

  const base = url.href.replace(/\/+$/, "");
  const projectRef = HOSTED.exec(url.hostname)?.[1];

  return {
    ok: true,
    env: {
      url: base,
      publishableKey,
      jwksUrl: jwksOverride ?? new URL(`${base}/auth/v1/.well-known/jwks.json`),
      ...(jwks ? { jwks } : {}),
      ...(secretKey
        ? { secretKey, secretKeys: { ...namedSecrets, default: secretKey } }
        : {}),
      ...(dbUrl ? { dbUrl } : {}),
      ...(projectRef ? { projectRef } : {}),
      ...(readUrl ? { readUrl: readUrl.href.replace(/\/+$/, "") } : {}),
      ...(jwtSecret ? { jwtSecret } : {}),
    },
  };
}

function processEnv(): EnvSource {
  // SAFETY: process is optional here; every property read is guarded.
  const runtime = globalThis as { process?: { env?: EnvSource } };

  return runtime.process?.env ?? {};
}

/**
 * Like `parseEnv`, but throws `EnvValidationError`. Reads `process.env` by
 * default.
 */
export function loadEnv(
  source: EnvSource = processEnv(),
  options: EnvOptions = {},
): BetterSupabaseEnv {
  const result = parseEnv(source, options);

  if (!result.ok) {
    throw new EnvValidationError(result.issues);
  }

  return result.env;
}

/**
 * The env validator as a Standard Schema, for t3-env, framework config or any
 * validator slot.
 */
export function envSchema(
  options: EnvOptions = {},
): StandardSchemaV1<EnvSource, BetterSupabaseEnv> {
  return {
    "~standard": {
      version: 1,
      vendor: "better-supabase",
      validate(value) {
        if (typeof value !== "object" || value === null) {
          return { issues: [{ message: "Expected an environment object" }] };
        }

        // SAFETY: the check above narrows value to an object, and parseEnv
        // checks each key.
        const result = parseEnv(value as EnvSource, options);

        if (result.ok) {
          return { value: result.env };
        }

        return {
          issues: result.issues.map((issue) => ({
            message: `${issue.variables[0] ?? "env"} ${issue.message}`,
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

/**
 * Converts to `@supabase/server`'s `SupabaseEnv` (the `env` option of
 * `withSupabase`).
 */
export function toServerEnv(env: BetterSupabaseEnv): SupabaseEnv {
  return {
    url: env.url,
    publishableKeys: { default: env.publishableKey },
    secretKeys:
      env.secretKeys ?? (env.secretKey ? { default: env.secretKey } : {}),
    jwks: env.jwks ?? env.jwksUrl,
  };
}
