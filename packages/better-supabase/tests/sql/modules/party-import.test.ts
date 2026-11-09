import { describe, expect, it } from "vitest";

import { renderBlocks } from "../../../src/sql/render.ts";

describe("party import targets", () => {
  const sql = renderBlocks(["contacts"])
    .map((file) => file.contents)
    .join("\n");

  it("imports a party, its contacts, methods, locations and bank accounts", () => {
    for (const name of [
      "import_party",
      "import_party_contact",
      "import_contact_method",
      "import_party_location",
      "import_party_bank_account",
    ]) {
      expect(sql).toContain(`"${name}"`);
    }

    expect(sql).toContain("validate_iban");
    expect(sql).toContain("normalize_phone");
    expect(sql).toContain("is not distinct from");
    expect(sql).toContain("IMPORT_ITEM_INVALID");
    expect(sql).toContain("IMPORT_NAME_FALLBACK");
    expect(sql).toContain("coalesce(v_display, v_legal, v_person, v_number)");
    expect(sql).toContain("party_locations");
    expect(sql).toContain("party_bank_accounts");
    expect(sql).toContain("party_channels");
  });
});
