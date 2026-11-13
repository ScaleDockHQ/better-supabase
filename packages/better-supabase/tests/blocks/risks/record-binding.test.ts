import { describe, expect, it } from "vitest";

import {
  createRisks,
  risksBinding,
  risksBlock,
} from "../../../src/blocks/risks/index.ts";

function transport(calls: [string, Record<string, unknown>][]) {
  return {
    call(_schema: string, fn: string, args: Record<string, unknown>) {
      calls.push([fn, args]);

      return Promise.resolve([]);
    },
  };
}

describe("risksBinding", () => {
  it("reads the risks linked to a record in the block's organization", async () => {
    const calls: [string, Record<string, unknown>][] = [];

    const client = createRisks({
      tenant: "org-1",
      transport: transport(calls),
    });

    const loaded = await risksBinding.load(
      client,
      { type: "project", id: "s1" },
      undefined,
    );

    expect(loaded.ok && loaded.data).toEqual([]);

    expect(calls).toEqual([
      [
        "list_risks_for_subject",
        {
          tenant: "org-1",
          subject_type: "project",
          subject_id: "s1",
          page_size: null,
        },
      ],
    ]);
    expect(risksBlock.record).toBe(risksBinding);
    expect(risksBinding.events).toEqual(["risk.*"]);
  });

  it("fails without an organization", async () => {
    const client = createRisks({ transport: transport([]) });

    const loaded = await risksBinding.load(
      client,
      { type: "project", id: "s1" },
      undefined,
    );

    expect(loaded.ok).toBe(false);
  });
});
