import type { QueuePrefix, World } from "@workflow/world";

import type { pollingStreamReader } from "./polling.ts";
import type { StoredMessage } from "./types.ts";
import type { SupabaseWorld } from "./world.ts";

import { dbError } from "../../core/errors.ts";
import { problemResponse } from "../../core/problem.ts";

/**
 * JSON with Uint8Array values as `{ __type: "Uint8Array", data: <base64> }`, as
 * world-postgres sends them.
 */
export function serialize(value: unknown): Buffer {
  return Buffer.from(
    JSON.stringify(value, (_key, inner: unknown) =>
      inner instanceof Uint8Array
        ? { __type: "Uint8Array", data: Buffer.from(inner).toString("base64") }
        : inner,
    ),
  );
}

export function isStoredMessage(value: unknown): value is StoredMessage {
  if (typeof value !== "object" || value === null) {
    return false;
  }

  const record: Record<string, unknown> = { ...value };

  return (
    typeof record["queueName"] === "string" &&
    typeof record["messageId"] === "string" &&
    typeof record["attempt"] === "number" &&
    typeof record["body"] === "string"
  );
}

/** The run a flow message belongs to, when its body names one. */
export function runIdOf(message: StoredMessage): string | undefined {
  try {
    const body: unknown = JSON.parse(
      Buffer.from(message.body, "base64").toString("utf-8"),
    );

    if (typeof body === "object" && body !== null && "runId" in body) {
      return typeof body.runId === "string" ? body.runId : undefined;
    }
  } catch {
    return undefined;
  }

  return undefined;
}

export function deliveryProblem(
  kind: "invalid_request" | "unauthorized" | "network",
  detail: string,
): Response {
  return problemResponse(
    dbError(kind, detail, { code: "WORKFLOW_DELIVERY_REJECTED" }),
    { expose: true },
  );
}

/**
 * Retry delay after a failed delivery, as world-postgres (exp(min(attempt, 10))
 * seconds).
 */
export const backoffSeconds = (attempt: number): number =>
  Math.ceil(Math.exp(Math.min(attempt, 10)));

/**
 * The storage a transaction pooler can serve: stream reads poll the rows, and
 * the optional listeners (`events.subscribe`, `runs.waitForTerminalStatus`) are
 * left out, so the runtime polls for them as the World contract allows.
 */
export function transactionStorage(
  base: World,
  poller: ReturnType<typeof pollingStreamReader>,
): Pick<World, "streams" | "events" | "runs"> {
  // The two members are dropped, never called, so the unbound reference is safe.
  // oxlint-disable-next-line typescript/unbound-method
  const { subscribe: _subscribe, ...events } = base.events;
  const { waitForTerminalStatus: _wait, ...runs } = base.runs;

  return {
    events,
    runs,
    streams: {
      ...base.streams,
      get: (_runId, name, startIndex) =>
        Promise.resolve(poller.get(name, startIndex)),
    },
  };
}

/** The entry of the longest prefix `queueName` starts with. */
export const byPrefix = <T>(
  entries: ReadonlyMap<QueuePrefix, T>,
  queueName: string,
): T | undefined => {
  let found: T | undefined;
  let length = -1;

  for (const [prefix, value] of entries) {
    if (queueName.startsWith(prefix) && prefix.length > length) {
      found = value;
      length = prefix.length;
    }
  }

  return found;
};

const REGISTRY: unique symbol = Symbol.for("better-supabase.workflow.worlds");

/**
 * The Worlds `createWorld()` made, on `globalThis`: the Workflow SDK imports
 * the factory once per bundle, and each copy must share one pool and poller.
 */
export function worldRegistry(): Map<string, SupabaseWorld> {
  // SAFETY: only this function writes the symbol, always a Map of Worlds.
  const holder = globalThis as { [REGISTRY]?: Map<string, SupabaseWorld> };
  holder[REGISTRY] ??= new Map<string, SupabaseWorld>();

  return holder[REGISTRY];
}
