import type { EnvIssue, EnvSource } from "../env/index.ts";

import {
  ENV_VARIABLES,
  EnvValidationError,
  projectRefOf,
  withEnvPrefix,
} from "../env/index.ts";

export type { EnvIssue, EnvSource };

/** The header Vercel reads for Protection Bypass for Automation. */
export const PROTECTION_BYPASS_HEADER = "x-vercel-protection-bypass";

/** The system variable that holds the project's bypass secret. */
export const PROTECTION_BYPASS_VARIABLE = "VERCEL_AUTOMATION_BYPASS_SECRET";

/** Which deployment URL `deploymentUrl` returns. */
export type DeploymentUrlTarget =
  | "auto"
  | "production"
  | "branch"
  | "deployment";

export interface DeploymentUrlOptions {
  /**
   * `production`: the project's production domain. `branch`: the Git branch
   * URL. `deployment`: the URL of this one deployment. `auto` (default):
   * production on a production deployment, the branch URL on any other.
   */
  readonly target?: DeploymentUrlTarget;
  /** A path (and query) to append, such as `/auth/callback`. */
  readonly path?: string;
  /**
   * Returned when the variables are not set, as on a laptop. Without it the
   * function returns `undefined`.
   */
  readonly fallback?: string;
}

function read(source: EnvSource, name: string): string | undefined {
  const value = source[name]?.trim();

  return value === undefined || value === "" ? undefined : value;
}

/** A Vercel host variable without a scheme or trailing slash. */
function hostOf(source: EnvSource, name: string): string | undefined {
  const value = read(source, name);

  return value?.replace(/^https?:\/\//i, "").replace(/\/+$/, "");
}

/** The target environment: `VERCEL_TARGET_ENV`, then `VERCEL_ENV`. */
export function vercelEnvironment(source: EnvSource): string | undefined {
  return read(source, "VERCEL_TARGET_ENV") ?? read(source, "VERCEL_ENV");
}

/**
 * The URL of this deployment from the variables Vercel sets, for auth redirects
 * and absolute links. It takes the environment as an argument, so it runs on
 * every runtime. `VERCEL_PROJECT_PRODUCTION_URL` is set on preview deployments
 * too, which is why `auto` picks it only when the deployment is production.
 *
 * ```ts
 * const redirectTo = deploymentUrl(process.env, {
 *   path: "/auth/callback",
 *   fallback: "http://localhost:3000",
 * });
 * ```
 */
export function deploymentUrl(
  source: EnvSource,
  options: DeploymentUrlOptions = {},
): string | undefined {
  const target = options.target ?? "auto";
  const production = hostOf(source, "VERCEL_PROJECT_PRODUCTION_URL");
  const branch = hostOf(source, "VERCEL_BRANCH_URL");
  const deployment = hostOf(source, "VERCEL_URL");
  const isProduction = vercelEnvironment(source) === "production";

  let host: string | undefined;

  switch (target) {
    case "production": {
      host = production;

      break;
    }

    case "branch": {
      host = branch ?? deployment;

      break;
    }

    case "deployment": {
      host = deployment;

      break;
    }

    case "auto": {
      host = isProduction ? (production ?? deployment) : (branch ?? deployment);

      break;
    }

    default: {
      const unreachable: never = target;

      throw new TypeError(
        `Unknown deployment URL target: ${String(unreachable)}`,
      );
    }
  }

  if (host === undefined) {
    return options.fallback;
  }

  const path = options.path ?? "";

  return `https://${host}${path === "" || path.startsWith("/") ? path : `/${path}`}`;
}

/** The hosts of this deployment: its URL, branch URL and production domain. */
function ownHosts(source: EnvSource): string[] {
  return [
    "VERCEL_URL",
    "VERCEL_BRANCH_URL",
    "VERCEL_PROJECT_PRODUCTION_URL",
  ].flatMap((name) => {
    const host = hostOf(source, name);

    return host === undefined ? [] : [host.toLowerCase()];
  });
}

export interface ProtectionBypassOptions {
  /**
   * The URL the request goes to. The secret is only added when its host is one
   * of this deployment's (`VERCEL_URL`, `VERCEL_BRANCH_URL`,
   * `VERCEL_PROJECT_PRODUCTION_URL`) or in `allowHosts`, so a callback to
   * another service never carries it. Without `url`, the headers are always
   * returned.
   */
  readonly url?: string | URL;
  /** More hosts of the same project, such as a second production domain. */
  readonly allowHosts?: readonly string[];
  /** The secret to use instead of `VERCEL_AUTOMATION_BYPASS_SECRET`. */
  readonly secret?: string;
}

function bypassSecret(
  source: EnvSource,
  options: ProtectionBypassOptions,
): string | undefined {
  const secret = options.secret ?? read(source, PROTECTION_BYPASS_VARIABLE);

  if (secret === undefined || secret === "") {
    return undefined;
  }

  if (options.url === undefined) {
    return secret;
  }

  let host: string;

  try {
    host = new URL(options.url).hostname.toLowerCase();
  } catch {
    return undefined;
  }

  const allowed = [
    ...ownHosts(source),
    ...(options.allowHosts ?? []).map((name) => name.toLowerCase()),
  ];

  return allowed.includes(host) ? secret : undefined;
}

/**
 * The `x-vercel-protection-bypass` header for a callback to a protected
 * deployment: a queue delivery, a cron or schedule call, a webhook. The result
 * is empty when the project has no bypass secret, so it is safe to spread into
 * any header set. Pass it as the World's `deliveryHeaders`, or write it as JSON
 * to the `workflow_delivery_headers` Vault secret.
 *
 * ```ts
 * await fetch(url, {
 *   method: "POST",
 *   headers: { ...protectionBypassHeaders(process.env, { url }) },
 * });
 * ```
 */
export function protectionBypassHeaders(
  source: EnvSource,
  options: ProtectionBypassOptions = {},
): Record<string, string> {
  const secret = bypassSecret(source, options);

  return secret === undefined ? {} : { [PROTECTION_BYPASS_HEADER]: secret };
}

/**
 * `url` with the bypass secret as the `x-vercel-protection-bypass` query
 * parameter, for a caller that cannot set a header, such as a database webhook
 * or `pg_net` job URL. A header is safer, because URLs end up in logs. The URL
 * comes back unchanged when no secret applies.
 */
export function protectionBypassUrl(
  url: string,
  source: EnvSource,
  options: Omit<ProtectionBypassOptions, "url"> = {},
): string {
  const secret = bypassSecret(source, { ...options, url });

  if (secret === undefined) {
    return url;
  }

  const result = new URL(url);
  result.searchParams.set(PROTECTION_BYPASS_HEADER, secret);

  return result.toString();
}

export interface DeploymentCheckOptions {
  /**
   * The project ref of the production Supabase project. A preview or
   * development deployment that points at it is reported.
   */
  readonly productionProjectRef?: string;
  /** The integration's custom prefix, as in `parseEnv`. */
  readonly prefix?: string;
}

/**
 * Problems with where this deployment points. A deployment on Vercel that is
 * not production, whose `SUPABASE_URL` is the production project, would write
 * preview data into production. The issues name variables, never values.
 */
export function deploymentIssues(
  source: EnvSource,
  options: DeploymentCheckOptions = {},
): readonly EnvIssue[] {
  const env =
    options.prefix === undefined
      ? source
      : withEnvPrefix(source, options.prefix);

  const environment = vercelEnvironment(env);

  if (
    options.productionProjectRef === undefined ||
    environment === undefined ||
    environment === "production"
  ) {
    return [];
  }

  const url = ENV_VARIABLES.url
    .map((name) => read(env, name))
    .find((value) => value !== undefined);

  if (url === undefined || projectRefOf(url) !== options.productionProjectRef) {
    return [];
  }

  return [
    {
      variables: ENV_VARIABLES.url,
      message: `points at the production project on a ${environment} deployment. Give ${environment} its own Supabase project or a branch database, so a preview never writes to production`,
    },
  ];
}

/**
 * Throws `EnvValidationError` when `deploymentIssues` finds one. Call it once
 * at startup (`instrumentation.ts`).
 */
export function assertDeployment(
  source: EnvSource,
  options: DeploymentCheckOptions = {},
): void {
  const issues = deploymentIssues(source, options);

  if (issues.length > 0) {
    throw new EnvValidationError(issues);
  }
}
