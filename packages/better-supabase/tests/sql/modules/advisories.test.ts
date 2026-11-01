import { describe, expect, it } from "vitest";

import { renderBlocks } from "../../../src/sql/render.ts";

const BASE = ["memberships", "permissions", "subjects", "advisories"];

const sqlOf = (modules: readonly string[] = BASE): string =>
  renderBlocks(modules, {})
    .filter((file) => file.module === "advisories")
    .map((file) => file.contents)
    .join("\n");

describe("advisories module", () => {
  it("renders the tables and the VEX status check", () => {
    const sql = sqlOf();

    for (const table of [
      "advisory_products",
      "advisory_product_versions",
      "sbom_components",
      "vulnerabilities",
      "vex_statements",
      "advisory_vulnerabilities",
    ]) {
      expect(sql).toContain(`"better_supabase"."${table}"`);
    }

    expect(sql).toContain(
      "'not_affected', 'affected', 'fixed', 'under_investigation'",
    );
  });

  it("registers the permission keys and the enrichment functions", () => {
    const sql = sqlOf();

    expect(sql).toContain("advisories.write");
    expect(sql).toContain("advisories.publish");
    expect(sql).toContain("record_vulnerability_enrichment");
    expect(sql).toContain("vulnerabilities_due");
  });

  it("adds relation kinds only for the blocks that are installed", () => {
    const all = renderBlocks([...BASE, "relations", "incidents", "risks"], {})
      .map((file) => file.contents)
      .join("\n");

    expect(all).toContain("reported_as");
    expect(all).toContain("tracked_as");
    expect(sqlOf([...BASE, "relations"])).not.toContain("reported_as");
  });
});
