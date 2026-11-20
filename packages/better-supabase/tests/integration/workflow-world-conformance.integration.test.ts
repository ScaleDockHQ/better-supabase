import { atomicStartHookConformance } from "@workflow/world/test-support/atomic-start-hook-conformance.js";
import { inBandFenceConformance } from "@workflow/world/test-support/in-band-fence-conformance.js";
import { Pool } from "pg";
import { afterAll, beforeAll, describe } from "vitest";

import type { SupabaseWorld } from "../../src/workflow-sdk/world/index.ts";

import { createSupabaseWorld } from "../../src/workflow-sdk/world/index.ts";
import { dbUrl, reachable } from "./block-session.ts";
import { installWorld } from "./workflow-world.ts";

const live = await reachable();
const ALPHABET = "0123456789ABCDEFGHJKMNPQRSTVWXYZ";

/** A ULID: ten characters of time, then sixteen random ones. */
function ulid(): string {
  let time = Date.now();
  let head = "";

  for (let index = 0; index < 10; index += 1) {
    head = (ALPHABET[time % 32] ?? "0") + head;
    time = Math.floor(time / 32);
  }

  const random = crypto.getRandomValues(new Uint8Array(16));

  return head + [...random].map((byte) => ALPHABET[byte % 32]).join("");
}

const MODES = ["poll", "pg_net"] as const;

// Every delivery mode shares the storage, so the contract eve relies on
// (atomic start hooks, the spec 9 fence) has to hold through each one.
describe.skipIf(!live).each(MODES)(
  "eve's World requirements in %s mode",
  (delivery) => {
    const pool = new Pool({ connectionString: dbUrl });
    let world: SupabaseWorld;
    let second: SupabaseWorld;

    beforeAll(async () => {
      await installWorld(pool);
      world = createSupabaseWorld({ pool, delivery, deliverySecret: "s" });
      second = createSupabaseWorld({ pool, delivery, deliverySecret: "s" });
    });

    afterAll(async () => {
      await world.close();
      await second.close();
      await pool.end();
    });

    atomicStartHookConformance({
      name: `better-supabase World (${delivery})`,
      storage: () => world,
      capabilities: () => world.capabilities,
      newRunId: () => `wrun_${ulid()}`,
      secondEvents: () => second.events,
      // The retention clock is the database's, so a retention that ends by
      // `until` is moved into the past instead of waited out.
      passRetention: async (until) => {
        await pool.query(
          `update workflow.workflow_hooks
              set token_retention_until = now() - interval '1 second'
            where token_retention_until <= $1`,
          [until],
        );
      },
    });

    inBandFenceConformance({
      name: `better-supabase World (${delivery})`,
      events: () => world.events,
      capabilities: () => world.capabilities,
      newRunId: () => `wrun_${ulid()}`,
      atRunCreation: 1,
      secondEvents: () => second.events,
    });
  },
);
