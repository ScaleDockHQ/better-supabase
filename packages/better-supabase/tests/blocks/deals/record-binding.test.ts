import { describe, expect, it } from "vitest";

import {
  createDeals,
  dealsBinding,
  dealsBlock,
} from "../../../src/blocks/deals/index.ts";

function transport(calls: [string, Record<string, unknown>][]) {
  return {
    call(_schema: string, fn: string, args: Record<string, unknown>) {
      calls.push([fn, args]);

      return Promise.resolve([]);
    },
  };
}

describe("dealsBinding", () => {
  it("reads the subject's deals in the block's organization", async () => {
    const calls: [string, Record<string, unknown>][] = [];

    const client = createDeals({
      tenant: "org-1",
      transport: transport(calls),
    });

    const loaded = await dealsBinding.load(
      client,
      { type: "company", id: "c1" },
      undefined,
    );

    expect(loaded.ok && loaded.data).toEqual([]);
    expect(calls).toEqual([
      [
        "list_deals_for_subject",
        {
          tenant: "org-1",
          subject_type: "company",
          subject_id: "c1",
          page_size: null,
        },
      ],
    ]);
    expect(dealsBlock.record).toBe(dealsBinding);

    expect(dealsBinding.events).toEqual(["deal.*"]);
  });

  it("fails without an organization", async () => {
    const client = createDeals({ transport: transport([]) });

    const loaded = await client.list({
      subject: { type: "company", id: "c1" },
    });

    expect(loaded.ok).toBe(false);
  });
});
