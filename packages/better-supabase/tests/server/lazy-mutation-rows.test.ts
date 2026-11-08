import { describe, expect, it } from "vitest";

import type { Executor } from "../../src/core/executor.ts";

import { createSupabase } from "../../src/core/define.ts";
import { definePlugin } from "../../src/core/plugin.ts";
import { ok } from "../../src/core/result.ts";
import { schema } from "../fixtures/generated-camel.ts";

function countingExecutor(reads: { count: number }): Executor {
  return {
    name: "counting",
    execute: () =>
      Promise.resolve(
        ok({
          rows: [
            {
              get id(): string {
                reads.count += 1;

                return "t1";
              },
            },
          ],
          count: null,
        }),
      ),
  };
}

const ACME = "00000000-0000-4000-8000-000000000001";

async function writeWith(
  readRows: boolean | "none",
): Promise<{ readonly reads: number }> {
  const reads = { count: 0 };
  const base = createSupabase(schema);

  const betterSupabase =
    readRows === "none"
      ? base
      : base.use(
          definePlugin({
            name: "listener",
            afterMutation: (event) => {
              if (readRows) {
                void event.rows.length;
              }
            },
          }),
        );

  await betterSupabase
    .connect(countingExecutor(reads))
    .tags.create({ id: "t1", name: "a", organizationId: ACME });

  return { reads: reads.count };
}

describe("mutation events", () => {
  it("clones the returned rows only when a listener reads them", async () => {
    const keysOnly = await writeWith(false);
    const reading = await writeWith(true);

    expect(reading.reads).toBeGreaterThan(keysOnly.reads);
  });
});
