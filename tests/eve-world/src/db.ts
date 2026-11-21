import { setTimeout as sleep } from "node:timers/promises";
import { Pool } from "pg";

import { dbUrl } from "./server.ts";

export function connect(): Pool {
  const pool = new Pool({ connectionString: dbUrl(), max: 2 });
  // A backend ended by a test must not crash the process through an unhandled event.
  pool.on("error", () => undefined);

  return pool;
}

/**
 * Runs of one eve session: the first run carries the first message as its title
 * and a handoff successor carries the session id, so every scenario starts with
 * a message that is unique.
 */
export async function runsOf(
  pool: Pool,
  sessionId: string,
  title: string,
): Promise<readonly { id: string; status: string }[]> {
  const result = await pool.query<{ id: string; status: string }>(
    `select id, status from workflow.workflow_runs
     where attributes->>'$eve.title' = $1 or attributes->>'$eve.session' = $2
     order by created_at`,
    [title, sessionId],
  );

  return result.rows;
}

/** Waits until `read` returns something other than `undefined`. */
export async function eventually<T>(
  read: () => Promise<T | undefined>,
  timeoutMs = 30_000,
): Promise<T> {
  const deadline = Date.now() + timeoutMs;

  for (;;) {
    const value = await read();

    if (value !== undefined) {
      return value;
    }

    if (Date.now() > deadline) {
      throw new Error("condition not met in time");
    }

    await sleep(250);
  }
}

let counter = 0;

/** A message that no other scenario sent, so its run is easy to find. */
export function unique(message: string): string {
  counter += 1;

  return `${message} #${String(Date.now())}-${String(counter)}`;
}
