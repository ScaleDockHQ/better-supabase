import { describe, expect, it } from "vitest";

import { detailArg } from "../../src/commerce/stock-detail.ts";

describe("detailArg", () => {
  it("passes null without a detail", () => {
    expect(detailArg(undefined)).toBeNull();
  });

  it("keeps only the keys the detail sets", () => {
    expect(detailArg({})).toEqual({});
    expect(
      detailArg({
        binId: "b1",
        lotId: "lot-1",
        lot: { code: "L1", expiresOn: "2027-01-31" },
        serials: ["SN-1", "SN-2"],
      }),
    ).toEqual({
      binId: "b1",
      lotId: "lot-1",
      lot: { code: "L1", expiresOn: "2027-01-31" },
      serials: ["SN-1", "SN-2"],
    });
  });
});
