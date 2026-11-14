import { describe, expect, it } from "vitest";

import { createOptionSets } from "../../../src/blocks/option-sets/index.ts";

function transport(
  results: Record<string, (args: Record<string, unknown>) => unknown>,
) {
  const calls: [string, Record<string, unknown>][] = [];

  return {
    calls,
    call(schema: string, fn: string, args: Record<string, unknown>) {
      expect(schema).toBe("better_supabase");
      calls.push([fn, args]);
      const result = results[fn];

      if (!result) {
        return Promise.reject(new Error(`unexpected ${fn}`));
      }

      return Promise.resolve(result(args));
    },
  };
}

const ITEM = {
  id: "i1",
  option_set_id: "s1",
  key: "high",
  system_key: "high",
  label: "High",
  color: "red",
  icon: null,
  rank: "V",
  level: 3,
};

const SET = {
  id: "s1",
  tenant_id: "o",
  subject_type: "work_item",
  field: "priority",
  scope_id: null,
  key: "default",
  name: "Priority",
  is_default: true,
  items: [ITEM],
};

describe("option-sets block", () => {
  it("lists sets with their items", async () => {
    const t = transport({ list_option_sets: () => [SET] });
    const sets = createOptionSets({ transport: t });

    const [set] = await sets
      .list({
        organizationId: "o",
        subjectType: "work_item",
        field: "priority",
      })
      .orThrow();

    expect(set?.items[0]).toMatchObject({
      key: "high",
      level: 3,
      color: "red",
    });
    expect(set?.items[0]).not.toHaveProperty("icon");
    expect(t.calls[0]).toEqual([
      "list_option_sets",
      {
        tenant: "o",
        filters: { subject_type: "work_item", field: "priority" },
      },
    ]);
  });

  it("restores an archived item", async () => {
    const t = transport({ restore_option_set_item: () => true });
    const sets = createOptionSets({ transport: t });

    expect(await sets.restoreItem("i1").orThrow()).toBe(true);
    expect(t.calls).toEqual([["restore_option_set_item", { item: "i1" }]]);
  });

  it("sends nulls for what an item input leaves out and replaces on archive", async () => {
    const t = transport({
      save_option_set_item: () => ITEM,
      archive_option_set_item: () => true,
      rank_option_set_item: () => true,
    });

    const sets = createOptionSets({ transport: t });

    await sets
      .saveItem({
        optionSetId: "s1",
        input: { key: "high", label: "High", level: 3 },
      })
      .orThrow();
    expect(
      await sets.archiveItem({ itemId: "i1", replacementId: "i2" }).orThrow(),
    ).toBe(true);
    await sets
      .reorderItem({ itemId: "i1", neighbors: { previous: "F" } })
      .orThrow();

    expect(t.calls[0]).toEqual([
      "save_option_set_item",
      {
        option_set: "s1",
        item: null,
        key: "high",
        label: "High",
        level: 3,
        color: null,
        icon: null,
        description: null,
      },
    ]);
    expect(t.calls[1]?.[1]).toEqual({ item: "i1", replacement: "i2" });
    expect(t.calls[2]?.[0]).toBe("rank_option_set_item");
  });
});
