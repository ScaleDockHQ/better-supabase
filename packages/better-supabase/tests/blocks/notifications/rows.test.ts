import { describe, expect, it } from "vitest";

import { toItem } from "../../../src/blocks/notifications/rows.ts";

const row = {
  id: "n1",
  event_id: "e1",
  type: "invoice.due",
  created_at: "2026-10-25T12:00:00Z",
};

describe("toItem", () => {
  it("keeps the actions that have a key and a label", () => {
    const item = toItem({
      ...row,
      actions: [
        {
          key: "pay",
          label: "Pay",
          operation: "invoices.pay",
          payload: { id: 1 },
        },
        { key: "later", label: "Later" },
        { key: "broken" },
        "not an action",
        null,
      ],
    });

    expect(item.actions).toEqual([
      {
        key: "pay",
        label: "Pay",
        operation: "invoices.pay",
        payload: { id: 1 },
      },
      { key: "later", label: "Later" },
    ]);
  });

  it("reads actions that aren't an array as none, and a resolution object as is", () => {
    const item = toItem({
      ...row,
      actions: { key: "pay" },
      resolution: { outcome: "paid" },
    });

    expect(item.actions).toEqual([]);
    expect(item.resolution).toEqual({ outcome: "paid" });
  });
});
