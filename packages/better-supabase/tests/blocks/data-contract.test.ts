import { describe, expect, it, vi } from "vitest";

import type { BlockTransport } from "../../src/core/block-transport.ts";
import type { Executor } from "../../src/core/executor.ts";
import type { RecordRef } from "../../src/schema/types.ts";

import { createChannels } from "../../src/blocks/channels/index.ts";
import { createScores } from "../../src/blocks/scores/index.ts";
import { createTags } from "../../src/blocks/tags/index.ts";
import { defineSupabase } from "../../src/core/define.ts";
import { ok } from "../../src/core/result.ts";
import { schema } from "../fixtures/generated-camel.ts";

const READS = ["list", "page", "get", "count", "aggregate"] as const;
const WRITES = ["create", "update", "upsert", "delete"] as const;

const RETIRED = [
  "findMany",
  "findFirst",
  "findOnly",
  "findUnique",
  "findById",
  "paginate",
  "exists",
  "createMany",
  "updateMany",
  "upsertMany",
  "deleteMany",
  "forSubject",
  "save",
  "tag",
  "untag",
] as const;

const DEAL: RecordRef = { type: "deal", id: "d1" };

/** A transport that answers every function with `answer` and records the calls. */
function recording(answer: unknown) {
  const call = vi.fn(
    async (_schema: string, _fn: string, _args: Record<string, unknown>) =>
      answer,
  );

  const transport: BlockTransport = { call };

  return { call, transport };
}

function repository() {
  const executor: Executor = {
    name: "fake",
    execute: () => Promise.resolve(ok({ rows: [], count: 0 })),
  };

  return defineSupabase(schema).connect(executor).customers;
}

describe("the data contract", () => {
  it("gives a table repository the read and write verbs", () => {
    const customers = repository();

    const missing = [...READS, ...WRITES].filter(
      (verb) => typeof customers[verb] !== "function",
    );

    expect(missing).toStrictEqual([]);
    expect(RETIRED.filter((verb) => verb in customers)).toStrictEqual([]);
  });

  it.each([
    [
      "tags",
      (transport: BlockTransport) =>
        createTags({ transport, tenant: "o" }).list({ on: DEAL }),
      "subject_tags",
    ],
    [
      "channels",
      (transport: BlockTransport) =>
        createChannels({ transport, tenant: "o" }).list({ on: DEAL }),
      "channels_for_record",
    ],
    [
      "scores",
      (transport: BlockTransport) =>
        createScores({ transport, tenant: "o" }).list({ on: DEAL }),
      "subject_scores",
    ],
  ])("lists the %s on a record with list({ on })", async (_block, list, fn) => {
    const { call, transport } = recording([]);

    expect(await list(transport).orThrow()).toEqual([]);
    expect(call).toHaveBeenCalledWith(
      expect.any(String),
      fn,
      expect.objectContaining({ subject_type: "deal", subject_id: "d1" }),
    );
  });

  it("attaches and detaches a tag on a record", async () => {
    const { call, transport } = recording(true);
    const tags = createTags({ transport, tenant: "o" });

    expect(await tags.attach(DEAL, "t1").orThrow()).toBe(true);
    expect(await tags.detach(DEAL, "t1").orThrow()).toBe(true);
    expect(call.mock.calls.map(([, fn, args]) => [fn, args])).toEqual([
      [
        "tag",
        { tenant: "o", subject_type: "deal", subject_id: "d1", tag_id: "t1" },
      ],
      [
        "untag",
        { tenant: "o", subject_type: "deal", subject_id: "d1", tag_id: "t1" },
      ],
    ]);
  });

  it("creates a tag from one object input", async () => {
    const { call, transport } = recording({ id: "t1", slug: "vip" });
    const tags = createTags({ transport, tenant: "o" });

    expect(
      await tags
        .create({ kind: "deal", name: "VIP", color: "amber" })
        .orThrow(),
    ).toMatchObject({ id: "t1", name: "VIP" });
    expect(call.mock.calls[0]?.[2]).toMatchObject({
      tenant: "o",
      kind: "deal",
      name: "VIP",
      color: "amber",
      description: null,
    });
  });
});
