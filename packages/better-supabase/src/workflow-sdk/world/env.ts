import { FLOW_PATH, type SupabaseWorldOptions } from "./types.ts";

export function env(name: string): string | undefined {
  const value = process.env[name];

  return value === undefined || value === "" ? undefined : value;
}

function positiveInt(value: string | undefined): number | undefined {
  const parsed = Math.trunc(Number(value ?? ""));

  return Number.isFinite(parsed) && parsed > 0 ? parsed : undefined;
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
  const maxConnections = positiveInt(read("WORKFLOW_POSTGRES_MAX_CONNECTIONS"));

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

  return {
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
