import { Pool } from "pg";
import { afterAll, beforeAll, describe, expect, it } from "vitest";

import { deriveRunKey } from "../../src/workflow-sdk/world/crypto.ts";
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

const OLD = Buffer.alloc(32, 1).toString("base64");
const NEW = Buffer.alloc(32, 2).toString("base64");

const ring = (second: string): string =>
  JSON.stringify([
    { id: "old", key: OLD, from: "1970-01-01T00:00:00Z" },
    { id: "new", key: NEW, from: second },
  ]);

describe.skipIf(!live)("the run key id", () => {
  const pool = new Pool({ connectionString: dbUrl });

  beforeAll(async () => {
    await installWorld(pool);
  });

  afterAll(async () => {
    await pool.end();
  });

  it("stamps the key a run uses and keeps it when the ring's dates change", async () => {
    // The second key starts in the future, so a run created now uses the first.
    const before = createSupabaseWorld({
      pool,
      encryptionKeys: ring("2999-01-01T00:00:00Z"),
    });

    const id = runId();

    await before.events.create(id, {
      eventType: "run_created",
      specVersion: SPEC,
      eventData: {
        deploymentId: "dpl_keys",
        workflowName: "keyId",
        input: new Uint8Array([1]),
      },
    });

    const stored = await pool.query<{ key: string | null }>(
      "select attributes->>'$bsb.key_id' as key from workflow.workflow_runs where id = $1",
      [id],
    );

    expect(stored.rows[0]?.key).toBe("old");

    // Someone moves the second key's start into the past: by date this run would now use "new".
    const after = createSupabaseWorld({
      pool,
      encryptionKeys: ring("2000-01-01T00:00:00Z"),
    });

    const key = await after.getEncryptionKeyForRun?.(id);

    expect(key).toEqual(await deriveRunKey(Buffer.from(OLD, "base64"), id));

    await before.close();
    await after.close();
  });
});
