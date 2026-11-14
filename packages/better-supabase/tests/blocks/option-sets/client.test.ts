import { describe, expect, it, vi } from "vitest";

import type {
  OptionSet,
  OptionSets,
} from "../../../src/blocks/option-sets/index.ts";

import { createOptionSetsController } from "../../../src/blocks/option-sets/client.ts";
import { fakeAuth, flush, mount, resolved } from "../../fixtures/ports.ts";

const item = (id: string, rank: string, level: number) => ({
  id,
  optionSetId: "s1",
  key: id,
  label: id,
  rank,
  level,
});

const SET: OptionSet = {
  id: "s1",
  organizationId: "o",
  subjectType: "work_item",
  field: "priority",
  key: "default",
  name: "Priority",
  isDefault: true,
  items: [item("a", "F", 1), item("b", "V", 2), item("c", "j", 3)],
};

function fakeClient() {
  return {
    list: vi.fn(() => resolved([SET])),
    ensure: vi.fn(() => resolved(SET)),
    upsert: vi.fn(() => resolved(SET)),
    saveItem: vi.fn(() => resolved(SET.items[0]!)),
    reorderItem: vi.fn(() => resolved("k")),
    archiveItem: vi.fn(() => resolved(true)),
    restoreItem: vi.fn(() => resolved(true)),
  } satisfies OptionSets;
}

describe("createOptionSetsController", () => {
  it("ensures the field, loads the sets and moves an item between its neighbors", async () => {
    const client = fakeClient();

    const controller = createOptionSetsController({
      client,
      auth: fakeAuth(),
      organizationId: "o",
      subjectType: "work_item",
      field: "priority",
    });

    const { view, unmount } = mount(controller);
    await flush();
    expect(client.ensure).toHaveBeenCalledOnce();
    expect(view().sets).toEqual([SET]);

    await view().moveItem({ optionSetId: "s1", itemId: "c", afterItemId: "a" });
    expect(client.reorderItem).toHaveBeenCalledWith({
      itemId: "c",
      neighbors: { previous: "F", next: "V" },
    });

    await view().archiveItem({ itemId: "b", replacementId: "a" });
    expect(client.archiveItem).toHaveBeenCalledWith({
      itemId: "b",
      replacementId: "a",
    });
    unmount();
  });
});
