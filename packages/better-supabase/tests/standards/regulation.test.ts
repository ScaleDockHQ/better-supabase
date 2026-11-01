import { describe, expect, it } from "vitest";

import { SPEC_PINS } from "../../src/core/spec-pins.ts";
import { renderBlocks } from "../../src/sql/render.ts";

const sqlOf = (module: string, also: readonly string[] = []): string =>
  renderBlocks([module, ...also], { modules: {} })
    .filter((file) => file.module === module)
    .map((file) => file.contents)
    .join("\n");

describe("regulation pins", () => {
  it("pins each regulation and signal specification the blocks follow", () => {
    expect(SPEC_PINS.euDsa).toBe("2022/2065");
    expect(SPEC_PINS.euNis2).toBe("2022/2555");
    expect(SPEC_PINS.euDora).toBe("2022/2554");
    expect(SPEC_PINS.euCra).toBe("2024/2847");
    expect(SPEC_PINS.euGdpr).toBe("2016/679");
    expect(SPEC_PINS.gpc).toBe("WD-20260924");
    expect(SPEC_PINS.iabTcf).toBe("2.2");
    expect(SPEC_PINS.iabGpp).toBe("1.1");
    expect(SPEC_PINS.oscal).toBe("1.2.3");
  });
});

describe("DSA moderation (Regulation 2022/2065)", () => {
  const sql = sqlOf("moderation");

  it("keeps statements of reasons, notices, trusted flaggers and appeals", () => {
    for (const fn of [
      "submit_notice",
      "decide_notice",
      "issue_statement",
      "set_trusted_flagger",
      "file_appeal",
      "decide_appeal",
      "transparency_report",
    ]) {
      expect(sql).toContain(`"${fn}"`);
    }
  });
});

describe("incident reporting (NIS2, DORA, CRA)", () => {
  const sql = sqlOf("incidents");

  it("plans the deadlines each regime names", () => {
    expect(sql).toContain("interval '24 hours'");
    expect(sql).toContain("interval '72 hours'");
    expect(sql).toContain("interval '1 month'");
    expect(sql).toContain("interval '4 hours'");
    expect(sql).toContain("interval '14 days'");
  });
});

describe("consent signals (GPC, TCF v2.2, GPP)", () => {
  const sql = sqlOf("consents");

  it("parses TCF and GPP strings and records Sec-GPC as an opt-out", () => {
    expect(sql).toContain('"parse_tc_string"');
    expect(sql).toContain('"parse_gpp_string"');
    expect(sql).toContain('"record_consent_signal"');
  });
});

describe("data subject requests (GDPR)", () => {
  const sql = sqlOf("data-lifecycle");

  it("gives a 30 day due date and one extension to three months", () => {
    expect(sql).toContain("now() + interval '30 days'");
    expect(sql).toContain(`"received_at" + interval '3 months'`);
  });
});

describe("OSCAL (compliance)", () => {
  const sql = sqlOf("compliance", ["versions", "attachments"]);

  it("imports catalogs and profiles and exports assessment results", () => {
    expect(sql).toContain('"import_oscal_catalog"');
    expect(sql).toContain('"apply_oscal_profile"');
    expect(sql).toContain('"export_oscal_assessment_results"');
  });
});
