import { describe, expect, it } from "vitest";

import { historyTabs } from "../../../src/blocks/field-history/index.ts";

describe("historyTabs", () => {
  it("lists the entities that declare history", () => {
    expect(
      historyTabs([
        {
          name: "deals",
          entities: {
            deal: { mutability: "editable", history: true },
            stage: { mutability: "editable", history: ["name"] },
            note: { mutability: "editable", history: false },
            tag: { mutability: "editable" },
          },
        },
      ]),
    ).toStrictEqual([
      { block: "deals", entity: "deal", fields: undefined },
      { block: "deals", entity: "stage", fields: ["name"] },
    ]);
  });
});
