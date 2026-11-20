import type { SupabaseWorldOptions } from "./types.ts";

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

/** The options `createWorld()` reads from the environment. */
export function worldOptionsFromEnv(
  source: Readonly<Record<string, string | undefined>> = process.env,
): SupabaseWorldOptions {
  const read = (name: string): string | undefined => {
    const value = source[name];

    return value === undefined || value === "" ? undefined : value;
  };

  const delivery = read("WORKFLOW_DELIVERY");

  if (delivery !== undefined && delivery !== "poll" && delivery !== "pg_net") {
    throw new TypeError(
      `better-supabase: WORKFLOW_DELIVERY must be "poll" or "pg_net", got "${delivery}"`,
    );
  }

  const connectionString =
    read("WORKFLOW_POSTGRES_URL") ??
    read("SUPABASE_DB_URL") ??
    read("DATABASE_URL");

  const flowUrl = read("WORKFLOW_FLOW_URL");
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

  const streamFlushIntervalMs = Number(
    read("WORKFLOW_POSTGRES_STREAM_FLUSH_INTERVAL_MS") ?? "",
  );

  return {
    ...(enableInvoke === undefined
      ? {}
      : { enableInvoke: enableInvoke === "1" || enableInvoke === "true" }),
    ...(Number.isFinite(streamFlushIntervalMs) &&
    streamFlushIntervalMs >= 0 &&
    read("WORKFLOW_POSTGRES_STREAM_FLUSH_INTERVAL_MS") !== undefined
      ? { streamFlushIntervalMs: Math.trunc(streamFlushIntervalMs) }
      : {}),
    ...(connection === undefined ? {} : { connection }),
    ...(encryptionKeys === undefined ? {} : { encryptionKeys }),
    ...(connectionString === undefined ? {} : { connectionString }),
    ...(delivery === undefined ? {} : { delivery }),
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
