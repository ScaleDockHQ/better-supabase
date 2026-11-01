import { describe, expect, it } from "vitest";

import type { BetterSupabase } from "../../src/core/define.ts";

import {
  compositeReadSet,
  defineCompositeReadSet,
} from "../../src/blocks/composite-reads.ts";
import { crmReadSets } from "../../src/blocks/crm/index.ts";

describe("composite read sets", () => {
  it("ships crm's pipeline page as data", () => {
    expect(crmReadSets.dashboard).toEqual({
      name: "crm_dashboard",
      params: { pipelineId: "uuid" },
      reads: {
        board: {
          block: "deals",
          read: "board",
          args: { pipelineId: "pipelineId" },
        },
      },
    });
  });

  it("names the read an app doesn't install", () => {
    const set = compositeReadSet("page", {}, { x: { block: "a", read: "b" } });

    expect(() =>
      // SAFETY: the check runs before the instance is used.
      defineCompositeReadSet(
        {} as unknown as BetterSupabase<never, never, never, never>,
        set,
        {},
      ),
    ).toThrow(/needs the a\.b read/u);
  });
});
