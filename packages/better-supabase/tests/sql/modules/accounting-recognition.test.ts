import { describe, expect, it } from "vitest";

import { renderBlocks } from "../../../src/sql/render.ts";

const NAMES = ["memberships", "permissions", "ledger", "periods", "accounting"];

function accounting(recognition: boolean): string {
  const files = renderBlocks(NAMES, {
    modules: { accounting: { options: { recognition } } },
  });

  return files.map((file) => file.contents).join("\n");
}

describe("accounting revenue recognition", () => {
  it("renders the schedule engine only when the option is on", () => {
    const on = accounting(true);
    const off = accounting(false);

    expect(on).toContain("schedule_revenue_recognition");
    expect(on).toContain("accounting_recognition_close");
    expect(on).toContain("'revenue_recognition'");
    expect(off).not.toContain("schedule_revenue_recognition");
    expect(off).not.toContain("accounting_recognition_close");
  });

  it("lists every schedule of the tenant behind accounting.read", () => {
    const on = accounting(true);

    expect(on).toContain("list_revenue_recognition_schedules");
    expect(on).toContain("not allowed to read revenue recognition");
    expect(accounting(false)).not.toContain(
      "list_revenue_recognition_schedules",
    );
  });

  it("always creates the tables so the option can be turned on later", () => {
    expect(accounting(false)).toContain("accounting_recognition_rows");
  });

  it("refuses a non-boolean option", () => {
    expect(() =>
      renderBlocks(NAMES, {
        modules: { accounting: { options: { recognition: "yes" } } },
      }),
    ).toThrow("recognition");
  });
});
