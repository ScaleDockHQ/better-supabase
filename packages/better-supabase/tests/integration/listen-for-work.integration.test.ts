import { Client, Pool } from "pg";
import { afterAll, describe, expect, it, vi } from "vitest";

import { silentLogger } from "../../src/core/logger.ts";
import { listenForWork } from "../../src/postgres/listen.ts";
import { stackDbUrl } from "./stack-env.ts";

const dbUrl = stackDbUrl();

async function reachable(): Promise<boolean> {
  const client = new Client({ connectionString: dbUrl });

  try {
    await client.connect();

    return true;
  } catch {
    return false;
  } finally {
    await client.end().catch(() => undefined);
  }
}

const live = await reachable();
const QUEUE = "listen_probe";

describe.skipIf(!live)("listenForWork", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 3 });

  afterAll(async () => {
    await pool.query("select pgmq.drop_queue($1)", [QUEUE]).catch(() => false);
    await pool.end();
  });

  it("drains a queue when a job is enqueued from SQL, and not on a rollback", async () => {
    const drained = vi.fn(async () => undefined);

    const listener = await listenForWork(pool, {
      queues: { [QUEUE]: drained },
      debounceMs: 5,
      logger: silentLogger,
    });

    try {
      const writer = await pool.connect();

      try {
        await writer.query("begin");
        await writer.query("select better_supabase.enqueue_job($1, $2)", [
          QUEUE,
          { n: 0 },
        ]);
        await writer.query("rollback");
      } finally {
        writer.release();
      }

      await new Promise((done) => {
        setTimeout(done, 200);
      });
      expect(drained).not.toHaveBeenCalled();

      await pool.query("select better_supabase.enqueue_job($1, $2)", [
        QUEUE,
        { n: 1 },
      ]);
      await vi.waitFor(() => {
        expect(drained).toHaveBeenCalledOnce();
      });
    } finally {
      await listener.close();
    }
  });

  it("probes for work written while it was away", async () => {
    await pool.query("select better_supabase.enqueue_job($1, $2)", [
      QUEUE,
      { n: 2 },
    ]);

    const drained = vi.fn(async () => undefined);

    const listener = await listenForWork(pool, {
      queues: { [QUEUE]: drained },
      debounceMs: 5,
      logger: silentLogger,
    });

    try {
      await vi.waitFor(() => {
        expect(drained).toHaveBeenCalledWith();
      });
    } finally {
      await listener.close();
    }
  });
});
