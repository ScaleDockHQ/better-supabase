import { describe, expect, it } from "vitest";

import {
  createQuotes,
  quotesBinding,
  quotesBlock,
} from "../../../src/blocks/quotes/index.ts";

function transport(calls: [string, Record<string, unknown>][]) {
  return {
    call(_schema: string, fn: string, args: Record<string, unknown>) {
      calls.push([fn, args]);

      return Promise.resolve([]);
    },
  };
}

describe("quotesBinding", () => {
  it("reads the subject's quotes in the block's organization", async () => {
    const calls: [string, Record<string, unknown>][] = [];

    const client = createQuotes({
      tenant: "org-1",
      transport: transport(calls),
    });

    const loaded = await quotesBinding.load(
      client,
      { type: "company", id: "c1" },
      undefined,
    );

    expect(loaded.ok && loaded.data).toEqual([]);

    expect(calls).toEqual([
      [
        "list_quotes_for_subject",
        {
          tenant: "org-1",
          subject_type: "company",
          subject_id: "c1",
          page_size: null,
        },
      ],
    ]);
    expect(quotesBlock.record).toBe(quotesBinding);

    expect(quotesBinding.events).toEqual(["quote.*"]);
  });

  it("fails without an organization", async () => {
    const client = createQuotes({ transport: transport([]) });

    const loaded = await client.list({
      subject: { type: "company", id: "c1" },
    });

    expect(loaded.ok).toBe(false);
  });
});
