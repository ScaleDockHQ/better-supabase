import { rpcTransport } from "better-supabase/blocks";
import { describe, expect, it } from "vitest";

import { blockSet } from "@/lib/supabase";

// The outbox relay route spreads `sinks` into its consumers, and the blocks
// that consume a port get the provider's client from `createBlocks`. The
// transport is never called: building the blocks only wires them.
const NO_CLIENT = { rpc: () => Promise.reject(new Error("not used")) };

function build() {
  return blockSet.create({
    // SAFETY: the transport is built but no block method runs in this test.
    transport: rpcTransport(NO_CLIENT as never),
  });
}

describe("block ports", () => {
  it("builds one outbox sink per block that provides one", () => {
    const { sinks } = build();

    expect(Object.keys(sinks).toSorted()).toEqual([
      "facilities",
      "search",
      "tasks",
    ]);

    for (const sink of Object.values(sinks)) {
      expect(sink).toHaveProperty("send");
    }
  });

  it("builds the blocks that consume a port without a missing provider", () => {
    const blocks = build();

    for (const key of [
      "activities",
      "collections",
      "comments",
      "drive",
      "knowledge",
      "reminders",
      "sequences",
      "tasks",
      "workflow-editor",
    ] as const) {
      expect(blocks[key]).toBeDefined();
    }
  });
});
