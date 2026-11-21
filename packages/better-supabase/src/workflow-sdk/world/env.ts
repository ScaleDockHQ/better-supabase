import type { SupabaseWorldOptions } from "./types.ts";

import { WORKFLOW_DELIVERY_MODES } from "../../sql/modules/workflow-sdk.ts";
import { protectionBypassHeaders } from "../../vercel/vercel.ts";
import { FLOW_PATH } from "./types.ts";

export function env(name: string): string | undefined {
  const value = process.env[name];

  return value === undefined || value === "" ? undefined : value;
}

function positiveInt(value: string | undefined): number | undefined {
  const parsed = Math.trunc(Number(value ?? ""));

  return Number.isFinite(parsed) && parsed > 0 ? parsed : undefined;
}

/** Whether the process runs on a serverless host (Vercel, Lambda, Netlify). */
export function isServerless(
  source: Readonly<Record<string, string | undefined>> = process.env,
): boolean {
  return ["VERCEL", "AWS_LAMBDA_FUNCTION_NAME", "NETLIFY"].some(
    (name) => source[name] !== undefined && source[name] !== "",
  );
}

/**
 * The connection string variables in the order the pool reads them: the
 * Supabase and generic names, then the Vercel integration's pooled and direct
 * strings. The World detects a transaction pooler from the string itself.
 */
export const CONNECTION_VARIABLES: readonly string[] = [
  "WORKFLOW_POSTGRES_URL",
  "SUPABASE_DB_URL",
  "DATABASE_URL",
  "POSTGRES_URL",
  "POSTGRES_URL_NON_POOLING",
];

/** The first connection string variable set in `read`'s source. */
export function connectionStringFrom(
  read: (name: string) => string | undefined,
): string | undefined {
  for (const name of CONNECTION_VARIABLES) {
    const value = read(name);

    if (value !== undefined) {
      return value;
    }
  }

  return undefined;
}

/** The flow route: `flowUrl`, `WORKFLOW_FLOW_URL`, or the local server. */
export function resolveFlowUrl(flowUrl?: string): string {
  const explicit = flowUrl ?? env("WORKFLOW_FLOW_URL");

  if (explicit !== undefined) {
    return explicit;
  }

  const base =
    env("WORKFLOW_LOCAL_BASE_URL") ??
    `http://localhost:${env("PORT") ?? "3000"}`;

  const url = new URL(base);
  url.pathname = `${url.pathname.replace(/\/+$/, "")}${FLOW_PATH}`;
  url.search = "";
  url.hash = "";

  return url.toString();
}

/**
 * `route` (an absolute path such as the flow path) on the host of `flowUrl`,
 * keeping the path prefix `flowUrl` has before the flow path, so an app served
 * under a base path (`/app/.well-known/workflow/v1/flow`) keeps it.
 */
export function routeUrl(route: string, flowUrl: string): string {
  const url = new URL(flowUrl);
  const at = url.pathname.indexOf(FLOW_PATH);
  const prefix = at > 0 ? url.pathname.slice(0, at).replace(/\/+$/, "") : "";

  return new URL(`${prefix}${route}`, url).toString();
}

/** A JSON object of string values, or `undefined` when `text` is not one. */
export function parseHeaders(
  text: string | undefined,
): Record<string, string> | undefined {
  if (text === undefined) {
    return undefined;
  }

  let parsed: unknown;

  try {
    parsed = JSON.parse(text);
  } catch {
    return undefined;
  }

  if (typeof parsed !== "object" || parsed === null || Array.isArray(parsed)) {
    return undefined;
  }

  const headers: Record<string, string> = {};

  for (const [name, value] of Object.entries(parsed)) {
    if (typeof value !== "string") {
      return undefined;
    }

    headers[name] = value;
  }

  return headers;
}

/** The options `createWorld()` reads from the environment. */
export function worldOptionsFromEnv(
  source: Readonly<Record<string, string | undefined>> = process.env,
): SupabaseWorldOptions {
  const read = (name: string): string | undefined => {
    const value = source[name];

    return value === undefined || value === "" ? undefined : value;
  };

  const delivery = read("WORKFLOW_DELIVERY");

  const mode = WORKFLOW_DELIVERY_MODES.find((known) => known === delivery);

  if (delivery !== undefined && mode === undefined) {
    throw new TypeError(
      `better-supabase: WORKFLOW_DELIVERY must be "poll", "pg_net" or "vercel-queue", got "${delivery}"`,
    );
  }

  const headersText = read("WORKFLOW_DELIVERY_HEADERS");
  const parsedHeaders = parseHeaders(headersText);

  if (headersText !== undefined && parsedHeaders === undefined) {
    throw new TypeError(
      "better-supabase: WORKFLOW_DELIVERY_HEADERS must be a JSON object of header names and string values",
    );
  }

  const recoverAfter = positiveInt(read("WORKFLOW_RECOVER_AFTER_SECONDS"));

  const connectionString = connectionStringFrom(read);

  const flowUrl = read("WORKFLOW_FLOW_URL");

  // The deployment's own bypass secret goes to the flow route only when that
  // route is on this deployment; headers the app sets explicitly win.
  const bypass =
    flowUrl === undefined
      ? {}
      : protectionBypassHeaders(source, { url: flowUrl });

  const deliveryHeaders =
    parsedHeaders === undefined && Object.keys(bypass).length === 0
      ? undefined
      : { ...bypass, ...parsedHeaders };

  const deliverySecret = read("WORKFLOW_DELIVERY_SECRET");
  const encryptionKey = read("WORKFLOW_ENCRYPTION_KEY");
  const queue = read("WORKFLOW_DELIVERY_QUEUE");
  const namespace = read("WORKFLOW_QUEUE_NAMESPACE");
  const concurrency = positiveInt(read("WORKFLOW_POSTGRES_WORKER_CONCURRENCY"));
  const pollInterval = positiveInt(read("WORKFLOW_POSTGRES_POLL_INTERVAL_MS"));

  // world-postgres's name first; MAX_CONNECTIONS is this World's older alias.
  const maxConnections = positiveInt(
    read("WORKFLOW_POSTGRES_MAX_POOL_SIZE") ??
      read("WORKFLOW_POSTGRES_MAX_CONNECTIONS"),
  );

  const connectionTimeout = positiveInt(
    read("WORKFLOW_POSTGRES_CONNECTION_TIMEOUT_MS"),
  );

  const idleTimeout = positiveInt(read("WORKFLOW_POSTGRES_IDLE_TIMEOUT_MS"));

  const statementTimeout = positiveInt(
    read("WORKFLOW_POSTGRES_STATEMENT_TIMEOUT_MS"),
  );

  const idleInTransactionTimeout = positiveInt(
    read("WORKFLOW_POSTGRES_IDLE_IN_TRANSACTION_TIMEOUT_MS"),
  );

  const connection = read("WORKFLOW_POSTGRES_CONNECTION");

  if (
    connection !== undefined &&
    connection !== "session" &&
    connection !== "transaction"
  ) {
    throw new TypeError(
      `better-supabase: WORKFLOW_POSTGRES_CONNECTION must be "session" or "transaction", got "${connection}"`,
    );
  }

  const encryptionKeys = read("WORKFLOW_ENCRYPTION_KEYS");

  const enableInvoke = read("WORKFLOW_POSTGRES_ENABLE_INVOKE");
  const skipWorkers = read("WORKFLOW_POSTGRES_SKIP_WORKERS");

  const streamFlushIntervalMs = Number(
    read("WORKFLOW_POSTGRES_STREAM_FLUSH_INTERVAL_MS") ?? "",
  );

  return {
    ...(enableInvoke === undefined
      ? {}
      : { enableInvoke: enableInvoke === "1" || enableInvoke === "true" }),
    ...(skipWorkers === undefined
      ? {}
      : { skipWorkers: skipWorkers === "1" || skipWorkers === "true" }),
    ...(Number.isFinite(streamFlushIntervalMs) &&
    streamFlushIntervalMs >= 0 &&
    read("WORKFLOW_POSTGRES_STREAM_FLUSH_INTERVAL_MS") !== undefined
      ? { streamFlushIntervalMs: Math.trunc(streamFlushIntervalMs) }
      : {}),
    ...(connection === undefined ? {} : { connection }),
    ...(encryptionKeys === undefined ? {} : { encryptionKeys }),
    ...(connectionString === undefined ? {} : { connectionString }),
    ...(mode === undefined ? {} : { delivery: mode }),
    ...(deliveryHeaders === undefined ? {} : { deliveryHeaders }),
    ...(recoverAfter === undefined ? {} : { recoverAfter }),
    ...(flowUrl === undefined ? {} : { flowUrl }),
    ...(deliverySecret === undefined ? {} : { deliverySecret }),
    ...(encryptionKey === undefined ? {} : { encryptionKey }),
    ...(queue === undefined ? {} : { queue }),
    ...(namespace === undefined ? {} : { namespace }),
    ...(concurrency === undefined ? {} : { concurrency }),
    ...(pollInterval === undefined ? {} : { pollInterval }),
    ...(maxConnections === undefined ? {} : { maxConnections }),
    ...(connectionTimeout === undefined ? {} : { connectionTimeout }),
    ...(idleTimeout === undefined ? {} : { idleTimeout }),
    ...(statementTimeout === undefined ? {} : { statementTimeout }),
    ...(idleInTransactionTimeout === undefined
      ? {}
      : { idleInTransactionTimeout }),
  };
}
