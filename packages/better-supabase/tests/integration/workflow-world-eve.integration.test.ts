import { Pool } from "pg";
import { afterAll, beforeAll, describe, expect, it } from "vitest";

import type { SupabaseWorld } from "../../src/workflow-sdk/world/index.ts";

import { createSupabaseWorld } from "../../src/workflow-sdk/world/index.ts";
import { dbUrl, reachable } from "./block-session.ts";
import { installWorld } from "./workflow-world.ts";

const live = await reachable();
const SPEC = 9;

function runId(): string {
  const alphabet = "0123456789ABCDEFGHJKMNPQRSTVWXYZ";
  let time = Date.now();
  let head = "";

  for (let index = 0; index < 10; index += 1) {
    head = (alphabet[time % 32] ?? "0") + head;
    time = Math.floor(time / 32);
  }

  const random = crypto.getRandomValues(new Uint8Array(16));

  return `wrun_${head}${[...random].map((byte) => alphabet[byte % 32]).join("")}`;
}

async function readAll(stream: ReadableStream<Uint8Array>): Promise<string[]> {
  const chunks: string[] = [];
  const reader = stream.getReader();

  for (;;) {
    const { done, value } = await reader.read();

    if (done) {
      return chunks;
    }

    chunks.push(new TextDecoder().decode(value));
  }
}

describe.skipIf(!live)("eve's World storage", () => {
  const pool = new Pool({ connectionString: dbUrl });
  const worlds: Record<"session" | "transaction", SupabaseWorld> = {} as never;

  beforeAll(async () => {
    await installWorld(pool);
    worlds.session = createSupabaseWorld({
      pool,
      connection: "session",
      streamFlushIntervalMs: 0,
    });
    worlds.transaction = createSupabaseWorld({
      pool,
      connection: "transaction",
      streamFlushIntervalMs: 0,
      streamPollInterval: 20,
    });
  });

  afterAll(async () => {
    await worlds.session.close();
    await worlds.transaction.close();
    await pool.end();
  });

  it("declares the capabilities eve requires", () => {
    for (const world of [worlds.session, worlds.transaction]) {
      expect(world.capabilities).toMatchObject({
        atomicStartHook: { active: true },
        inBandFence: false,
      });
    }
  });

  const MODES = ["session", "transaction"] as const;

  it.each(MODES)("resumes a stream from an index in %s mode", async (mode) => {
    const world = worlds[mode];
    const run = runId();
    const name = `resume-${mode}`;

    for (const chunk of ["a", "b", "c", "d", "e"]) {
      await world.streams.write(run, name, chunk);
    }

    await world.streams.close(run, name);

    expect(await readAll(await world.streams.get(run, name))).toEqual([
      "a",
      "b",
      "c",
      "d",
      "e",
    ]);
    expect(await readAll(await world.streams.get(run, name, 2))).toEqual([
      "c",
      "d",
      "e",
    ]);
    expect(await readAll(await world.streams.get(run, name, -2))).toEqual([
      "d",
      "e",
    ]);
  });

  it.each(MODES)(
    "delivers a chunk written while a reader waits in %s mode",
    async (mode) => {
      const world = worlds[mode];
      const run = runId();
      const name = `live-${mode}`;
      const pending = readAll(await world.streams.get(run, name));

      await world.streams.write(run, name, "x");
      await world.streams.write(run, name, "y");
      await world.streams.close(run, name);

      expect(await pending).toEqual(["x", "y"]);
    },
  );

  it("clears user data of a run with retention 0 and keeps it otherwise", async () => {
    const { events } = worlds.session;
    const kept = runId();
    const cleared = runId();

    for (const [id, attributes] of [
      [kept, undefined],
      [cleared, { $retention: "0" }],
    ] as const) {
      await events.create(id, {
        eventType: "run_created",
        specVersion: SPEC,
        eventData: {
          deploymentId: "dpl_eve",
          workflowName: "eveRetention",
          input: new Uint8Array([1, 2, 3]),
          ...(attributes === undefined
            ? {}
            : { attributes, allowReservedAttributes: true }),
        },
      });
      await events.create(id, { eventType: "run_started", specVersion: SPEC });
      await events.create(id, {
        eventType: "run_completed",
        specVersion: SPEC,
        eventData: { output: new Uint8Array([4]) },
      });
    }

    const { rows } = await pool.query<{
      id: string;
      input: unknown;
      output: unknown;
    }>(
      "select id, input_cbor as input, output_cbor as output from workflow.workflow_runs where id = any($1)",
      [[kept, cleared]],
    );

    const byId = Object.fromEntries(rows.map((row) => [row.id, row]));

    expect(byId[kept]?.output).not.toBeNull();
    expect(byId[cleared]?.input ?? null).toBeNull();
    expect(byId[cleared]?.output ?? null).toBeNull();
  });
});
