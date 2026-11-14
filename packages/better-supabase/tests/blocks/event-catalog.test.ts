import { describe, expect, it } from "vitest";

import { webhookEventCatalog } from "../../src/blocks/event-catalog.ts";
import { BLOCK_MANIFESTS } from "../../src/blocks/registry.ts";
import { defineEvents, event } from "../../src/core/event-map.ts";

const sample = defineEvents({
  "note.created": event<{ id: string }>({ public: true }),
  "note.touched": event<{ id: string }>(),
  "note.archived": event<{ id: string }>({ public: true }),
});

describe("the webhook event catalog", () => {
  it("lists only the events a block marks public, sorted", () => {
    expect(
      webhookEventCatalog([
        { name: "zeta", events: sample },
        { name: "alpha", events: sample },
        { name: "quiet", events: defineEvents({ "a.b": event<object>() }) },
      ]),
    ).toStrictEqual([
      { block: "alpha", type: "note.archived" },
      { block: "alpha", type: "note.created" },
      { block: "zeta", type: "note.archived" },
      { block: "zeta", type: "note.created" },
    ]);
  });

  it("keeps every event type, public or not", () => {
    expect(sample.types).toStrictEqual([
      "note.created",
      "note.touched",
      "note.archived",
    ]);
    expect(sample.public).toStrictEqual(["note.created", "note.archived"]);
  });

  it("leaves `public` off an event map that marks nothing", () => {
    expect(defineEvents({ "a.b": event<object>() })).toStrictEqual({
      types: ["a.b"],
    });
  });

  it("only marks event types the block declares", () => {
    for (const block of BLOCK_MANIFESTS) {
      for (const type of block.events.public ?? []) {
        expect(block.events.types, `${block.name}.${type}`).toContain(type);
      }
    }
  });

  it("covers the blocks that expose webhooks", () => {
    const blocks = new Set(
      webhookEventCatalog(BLOCK_MANIFESTS).map((entry) => entry.block),
    );

    expect([...blocks].toSorted()).toStrictEqual([
      "invoices",
      "orders",
      "organizations",
      "shipments",
    ]);
  });
});
