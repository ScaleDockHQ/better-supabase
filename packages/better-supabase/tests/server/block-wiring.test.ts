import { describe, expect, it } from "vitest";

import type { BlockContext, Notifier } from "../../src/blocks/index.ts";

import { defineBlock, defineBlocks } from "../../src/blocks/index.ts";
import { createFakeClient } from "../../src/testing/fake-client.ts";

describe("block wiring", () => {
  it("is validated once per defineBlocks, not once per builder", () => {
    let reads = 0;

    const provides = {
      get notifier(): (client: Notifier) => Notifier {
        reads += 1;

        return (client) => client;
      },
    };

    const notifications = defineBlock({
      name: "notifications",
      create: (_options: BlockContext): Notifier => ({
        send: () => Promise.resolve({ ok: true, data: null, error: null }),
      }),
      provides,
      category: "collaboration",
    });

    const blocks = defineBlocks(
      { notifications: { schema: "better_supabase", options: {} } },
      { notifications },
    );

    const admin = createFakeClient(() => ({ data: [] }));

    void blocks.serviceBlocks(admin).notifications;
    const afterFirst = reads;

    for (let request = 0; request < 5; request += 1) {
      void blocks.serviceBlocks(admin).notifications;
    }

    expect(afterFirst).toBeGreaterThan(0);
    expect(reads).toBe(afterFirst);
  });
});
