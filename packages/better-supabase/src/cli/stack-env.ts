import { createHash } from "node:crypto";

import type { StackStatus } from "./stack-status.ts";

/** Framework names `--prefix` accepts, with the prefix each one exposes to the browser. */
export const PREFIX_NAMES: Readonly<Record<string, string>> = {
  next: "NEXT_PUBLIC_",
  vite: "VITE_",
  expo: "EXPO_PUBLIC_",
  nuxt: "NUXT_PUBLIC_",
  astro: "PUBLIC_",
  sveltekit: "PUBLIC_",
  none: "",
};

/** A `--prefix` value as a variable prefix: a framework name, `none`, or the prefix itself. */
export function prefixFromFlag(flag: string): string {
  return PREFIX_NAMES[flag.toLowerCase()] ?? flag;
}

const text = (status: StackStatus, ...keys: string[]): string | undefined => {
  for (const key of keys) {
    const value = status[key];

    if (typeof value === "string" && value.length > 0) {
      return value;
    }
  }

  return undefined;
};

/** The JWKS endpoint Supabase Auth serves under an API URL. */
export function jwksUrlOf(apiUrl: string): string {
  return `${apiUrl.replace(/\/+$/, "")}/auth/v1/.well-known/jwks.json`;
}

/**
 * The variables `env` writes and `run` sets, from `supabase status`. The
 * browser prefix only ever gets the URL and the publishable key; the secret
 * key, database URL and JWT secret stay server-only. `undefined` when the
 * status has no API URL or publishable key.
 */
export function stackEnvValues(
  status: StackStatus,
  prefix: string,
): Record<string, string> | undefined {
  const url = text(status, "API_URL");
  const publishableKey = text(status, "PUBLISHABLE_KEY", "ANON_KEY");

  if (!url || !publishableKey) {
    return undefined;
  }

  const values: Record<string, string> = {
    SUPABASE_URL: url,
    SUPABASE_PUBLISHABLE_KEY: publishableKey,
  };

  const secretKey = text(status, "SECRET_KEY", "SERVICE_ROLE_KEY");

  if (secretKey) {
    values["SUPABASE_SECRET_KEY"] = secretKey;
  }

  values["SUPABASE_JWKS_URL"] = jwksUrlOf(url);

  const dbUrl = text(status, "DB_URL");

  if (dbUrl) {
    values["SUPABASE_DB_URL"] = dbUrl;
  }

  const jwtSecret = text(status, "JWT_SECRET");

  if (jwtSecret) {
    values["SUPABASE_JWT_SECRET"] = jwtSecret;
  }

  if (prefix.length > 0) {
    values[`${prefix}SUPABASE_URL`] = url;
    values[`${prefix}SUPABASE_PUBLISHABLE_KEY`] = publishableKey;
  }

  return values;
}

/**
 * A value safe to print: a URL shows its host and port (and a database URL
 * its database name), anything else a SHA-256 fingerprint. Never the value
 * itself, so keys and passwords stay out of logs.
 */
export function redactValue(value: string): string {
  if (/^(?:https?|postgres(?:ql)?):\/\//i.test(value)) {
    try {
      const url = new URL(value);
      const database = url.protocol.startsWith("postgres") ? url.pathname : "";

      return `${url.host}${database === "/" ? "" : database}`;
    } catch {
      // Not a parseable URL: fall through to the fingerprint.
    }
  }

  return `sha256:${createHash("sha256").update(value).digest("hex").slice(0, 8)}`;
}

export interface StaleVariable {
  readonly variable: string;
  /** The redacted value exported in the shell. */
  readonly shell: string;
  /** The redacted value the running stack has. */
  readonly stack: string;
  readonly message: string;
}

/**
 * The stack variables the shell exports with another value, such as a
 * `SUPABASE_URL` left over from another checkout's stack. Values are
 * redacted with `redactValue`.
 */
export function staleVariables(
  shell: Readonly<Record<string, string | undefined>>,
  values: Readonly<Record<string, string>>,
): StaleVariable[] {
  return Object.entries(values).flatMap(([variable, stackValue]) => {
    const exported = shell[variable];

    if (
      exported === undefined ||
      exported.length === 0 ||
      exported === stackValue
    ) {
      return [];
    }

    const redactedShell = redactValue(exported);
    const redactedStack = redactValue(stackValue);

    return [
      {
        variable,
        shell: redactedShell,
        stack: redactedStack,
        message: `${variable} is exported as ${redactedShell}, but the running stack has ${redactedStack}.`,
      },
    ];
  });
}
