import type pg from "pg";

import { existsSync, rmSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { afterAll, beforeAll, describe, expect, it } from "vitest";

import type { EveServer } from "../src/server.ts";

import { Client } from "../src/client.ts";
import { connect, eventually, runsOf, unique } from "../src/db.ts";
import { startServer } from "../src/server.ts";

const LOCAL_WORLD_DIR = fileURLToPath(
  new URL("../.eve/.workflow-data", import.meta.url),
);

let pool: pg.Pool;

beforeAll(() => {
  pool = connect();
});

afterAll(async () => {
  await pool.end();
});

async function retainedHooks(runIds: readonly string[]): Promise<number> {
  const result = await pool.query<{ n: string }>(
    "select count(*) as n from workflow.workflow_hooks where run_id = any($1) and token_retention_until is not null",
    [runIds],
  );

  return Number(result.rows[0]?.n);
}

async function compactAndHandOff(
  client: Client,
  pool: pg.Pool,
): Promise<readonly string[]> {
  const title = unique("hello");
  const id = await client.create(title);
  await client.waitFor(id, "turn.settled");
  await client.post(id, {}, "/compact");
  await client.waitFor(id, "context.settled");

  const runs = await eventually(async () => {
    const found = await runsOf(pool, id, title);

    return found.length >= 2 ? found : undefined;
  });

  return runs.map((run) => run.id);
}

describe("eve dev on the Supabase World keeps its state in Postgres", () => {
  it("never writes the local file world (A10)", async () => {
    rmSync(LOCAL_WORLD_DIR, { recursive: true, force: true });
    const server = await startServer({ command: "dev", delivery: "poll" });

    try {
      const client = new Client(server.url);
      const title = unique("hello");
      const id = await client.create(title);
      await client.waitFor(id, "turn.settled");

      expect(await runsOf(pool, id, title)).toHaveLength(1);
      expect(existsSync(LOCAL_WORLD_DIR)).toBe(false);
    } finally {
      await server.stop();
    }
  });
});

describe("a parked hook survives a restart", () => {
  it("answers an approval on a second server process", async () => {
    const first = await startServer({ command: "dev", delivery: "poll" });
    const client = new Client(first.url);
    const id = await client.create(unique("tool:delete_record"));
    const parked = await client.waitFor(id, "turn.paused");
    const opened = parked.find((event) => event.type === "interaction.opened");
    await first.stop();

    let second: EveServer | undefined;

    try {
      second = await startServer({ command: "dev", delivery: "poll" });
      const again = new Client(second.url);

      const answer = await again.post(id, {
        answers: [
          { interactionId: opened?.data["interactionId"], optionId: "approve" },
        ],
      });

      expect(answer.status).toBeLessThan(300);

      const events = await again.waitFor(
        id,
        "turn.settled",
        parked.at(-1)?.line ?? 0,
      );
      expect(JSON.stringify(events)).toContain("rec_1");
    } finally {
      await second?.stop();
    }
  });
});

describe("session idle timeout", () => {
  it("ends the session after the configured idle time", async () => {
    const server = await startServer({
      command: "dev",
      delivery: "poll",
      env: { EVE_WORLD_IDLE_MS: "3000" },
    });

    try {
      const client = new Client(server.url);
      const id = await client.create(unique("hello"));
      const events = await client.waitFor(id, "session.ended");

      expect(events.at(-1)?.data["outcome"]).toBe("completed");
    } finally {
      await server.stop();
    }
  });
});

describe("hook retention after a handoff", () => {
  it("keeps the old hook for the default period", async () => {
    const server = await startServer({
      command: "dev",
      delivery: "poll",
      env: { EVE_WORLD_RETENTION: "default" },
    });

    try {
      const runIds = await compactAndHandOff(new Client(server.url), pool);

      expect(await retainedHooks(runIds)).toBeGreaterThan(0);
    } finally {
      await server.stop();
    }
  });

  // eve's `retention: 0` marks a run `$retention: "0"`, and the World clears the data of a run
  // when it completes (`workflow-world-eve.integration.test.ts` asserts that). It does not shorten
  // the hook a handoff keeps, or the session could lose its address.
  it("still hands off and keeps the hook with retention 0", async () => {
    const server = await startServer({
      command: "dev",
      delivery: "poll",
      env: { EVE_WORLD_RETENTION: "0" },
    });

    try {
      const runIds = await compactAndHandOff(new Client(server.url), pool);

      expect(runIds.length).toBeGreaterThanOrEqual(2);
      expect(await retainedHooks(runIds)).toBeGreaterThan(0);
    } finally {
      await server.stop();
    }
  });
});
