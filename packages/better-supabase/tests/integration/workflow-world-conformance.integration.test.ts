import { atomicStartHookConformance } from "@workflow/world/test-support/atomic-start-hook-conformance.js";
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
// (atomic start hooks; the World declares no spec 9 fence, ADR 1106) has to hold through each one.
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
      // The suites leave runs of workflows no deployment registers. The next
      // World to start re-enqueues active runs, so another suite's poller
      // would log errors for them: the queued messages and the runs go.
      const queued = await pool.query<{ present: boolean }>(
        "select to_regclass('pgmq.q_workflow_deliveries') is not null as present",
      );

      if (queued.rows[0]?.present === true) {
        await pool.query(
          `delete from pgmq.q_workflow_deliveries m
            using workflow.workflow_runs r
            where r.name in ('startHookConformance', 'fenceConformance')
              and m.message::text like '%' || r.id || '%'`,
        );
      }

      await pool.query(
        `do $$
         declare t record;
         begin
           for t in select table_name from information_schema.columns
                    where table_schema = 'workflow' and column_name = 'run_id'
                      and table_name <> 'workflow_run_keys' loop
             execute format(
               'delete from workflow.%I where run_id in (select id from workflow.workflow_runs where name in (''startHookConformance'', ''fenceConformance''))',
               t.table_name);
           end loop;
           delete from workflow.workflow_runs where name in ('startHookConformance', 'fenceConformance');
         end $$`,
      );
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
  },
);
