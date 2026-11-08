import { describe, expect, it } from "vitest";

import type { BlockContext, Notifier } from "../../src/blocks/index.ts";

import { defineBlock, defineBlocks } from "../../src/blocks/index.ts";
import { createFakeClient } from "../../src/testing/fake-client.ts";

describe("block wiring", () => {
  it("is validated once per defineBlocks, not once per builder", () => {
    const notifications = defineBlock({
      name: "notifications",
      create: (_options: BlockContext): Notifier => ({
        send: () => Promise.resolve({ ok: true, data: null, error: null }),
      }),
      provides: { notifier: (client) => client },
      category: "collaboration",
    });

    const consumer = defineBlock({
      name: "consumer",
      create: (_options: Record<string, unknown>) => ({}),
      consumes: { notifier: "optional" },
      category: "work",
    });

    let scans = 0;

    // The wiring check walks the block map once per consumed port; a build does not.
    const map = new Proxy(
      { notifications, consumer },
      {
        ownKeys: (target) => {
          scans += 1;

          return Object.keys(target);
        },
      },
    );

    const blocks = defineBlocks(
      {
        notifications: { schema: "better_supabase", options: {} },
        consumer: { schema: "better_supabase", options: {} },
      },
      map,
    );

    const admin = createFakeClient(() => ({ data: [] }));

    const cost = (): number => {
      const before = scans;
      void blocks.serviceBlocks(admin).consumer;

      return scans - before;
    };

    const first = cost();
    const later = cost();

    expect(first).toBeGreaterThan(later);
    expect(cost()).toBe(later);
  });
});
