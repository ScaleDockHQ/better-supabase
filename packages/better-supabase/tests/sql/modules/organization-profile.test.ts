import { describe, expect, it } from "vitest";

import { renderBlocks } from "../../../src/sql/render.ts";

describe("organization profile import", () => {
  const sql = renderBlocks(["organizations"])
    .map((file) => file.contents)
    .join("\n");

  it("keeps a primary account and skips a country-only VAT number", () => {
    expect(sql).toContain("import_organization_profile");
    expect(sql).toContain("IMPORT_VAT_PREFIX");
    expect(sql).toContain("coalesce(v_vat, x.");
    expect(sql).toContain("when v_primary is true then true else");
    expect(sql).toContain("organization_payment_accounts");
  });
});
