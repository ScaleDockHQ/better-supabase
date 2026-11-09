import { describe, expect, it } from "vitest";

import { renderBlocks } from "../../../src/sql/render.ts";

const sql = (): string =>
  renderBlocks(["warranty"])
    .map((file) => file.contents)
    .join("\n");

describe("warranty claims", () => {
  it("stores the claim, the covered amount and the decision", () => {
    const rendered = sql();

    expect(rendered).toContain("warranty_claims");
    expect(rendered).toContain("supplier_id");
    expect(rendered).toContain("asset_id");
    expect(rendered).toContain("amount");
    expect(rendered).toContain("decision");
    expect(rendered).toContain("warranty.read");
    expect(rendered).toContain("warranty.write");
    expect(rendered).toContain("warranty.decide");
  });

  it("allows draft to submitted, submitted to a decision, and a decision to closed", () => {
    const rendered = sql();

    expect(rendered).toContain(`v_row."status" is distinct from 'draft'`);
    expect(rendered).toContain(
      `v_row."status" = 'submitted' and decide_warranty_claim.next_status in ('approved', 'denied')`,
    );
    expect(rendered).toContain(
      `v_row."status" in ('approved', 'denied') and decide_warranty_claim.next_status = 'closed'`,
    );
    expect(rendered).toContain("when 'draft' then");
    expect(rendered).toContain("when 'submitted' then");
    expect(rendered).toContain("when 'approved' then");
    expect(rendered).toContain("when 'denied' then");
  });

  it("decides a claim from an approval", () => {
    const rendered = sql();

    expect(rendered).toContain("= 'warranty_claim'");
    expect(rendered).toContain(", 'approved',");
    expect(rendered).toContain(", 'denied',");
  });
});
