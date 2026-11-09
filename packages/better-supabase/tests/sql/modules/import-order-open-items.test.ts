import { describe, expect, it } from "vitest";

import { renderBlocks } from "../../../src/sql/render.ts";

const sqlOf = (names: readonly string[]): string =>
  renderBlocks([...names])
    .map((file) => file.contents)
    .join("\n");

describe("import order and open items today", () => {
  it("applies a chunk in orderBy then readAt order", () => {
    const sql = sqlOf(["imports"]);

    expect(sql).toContain("e.value #>> '{data,orderBy}'");
    expect(sql).toContain("e.value #>> '{data,readAt}'");
    expect(sql).toContain("heartbeat_import_run");
    expect(sql).toContain("import_ensure_ref");
    expect(sql).toContain("import_entities");
    expect(sql).toContain("IMPORT_REF_CREATED");
    expect(sql).toContain("'incomplete'");
  });

  it("reads stored invoice balances when as_of is today", () => {
    const sql = sqlOf(["invoices", "ledger"]);

    expect(sql).toContain(
      "open_items_for_party.as_of is null or open_items_for_party.as_of = current_date",
    );
    expect(sql).toContain('"paid_total"');
  });
});
