import { describe, expect, it } from "vitest";

import type { BlockSqlContext } from "../../../src/sql/context.ts";

import { LIMS } from "../../../src/sql/modules/lims.ts";
import { customContracts, renderBlocks } from "../../../src/sql/render.ts";

type Layout = Parameters<typeof renderBlocks>[1];

const BASE = ["memberships", "permissions", "subjects", "lims"];

const sqlOf = (
  modules: readonly string[] = BASE,
  layout: Layout = {},
): string =>
  renderBlocks(modules, layout)
    .filter((file) => file.module === "lims")
    .map((file) => file.contents)
    .join("\n");

describe("lims module", () => {
  it("renders the tables and the specification check", () => {
    const sql = sqlOf();

    expect(sql).toContain("lims_methods");
    expect(sql).toContain("lims_samples");
    expect(sql).toContain("lims_results");
    expect(sql).toContain("'in_spec', 'out_of_spec'");
    expect(sql).toContain("then 'out_of_spec'");
    expect(sql).toContain(
      "'registered', 'in_testing', 'completed', 'released', 'rejected'",
    );
  });

  it("refuses to release a sample whose latest result is out of specification", () => {
    expect(sqlOf()).toContain("record a passing retest first");
  });

  it("opens a nonconformity case only with cases installed", () => {
    expect(sqlOf()).not.toContain("open_case_as");
    expect(sqlOf([...BASE, "tags", "cases"])).toContain("open_case_as");
  });

  it("needs a submission and instrument module before it accepts their ids", () => {
    expect(sqlOf()).toContain("submissionId needs the forms block");
    expect(sqlOf()).toContain("instrumentId needs the assets block");
  });

  it("requires a qualified instrument when the option names a qualification", () => {
    const layout: Layout = {
      modules: {
        lims: { options: { instrumentQualification: "calibration" } },
      },
    };

    expect(() => sqlOf(BASE, layout)).toThrow(/assets and qualifications/);
  });

  it("takes the case source from the cases options", () => {
    const withSources = (sources: unknown): string =>
      sqlOf([...BASE, "tags", "cases"], {
        modules: { cases: { options: { sources } } },
      });

    expect(withSources(["lims", "internal"])).toContain("'lims'");
    expect(withSources(["internal"])).toContain("'internal'");
    expect(withSources(["audit"])).toContain("'audit'");
  });

  it("falls back to defaults for empty options", () => {
    const sql = sqlOf(BASE, {
      modules: {
        lims: {
          options: { instrumentQualification: "", nonconformityKind: "" },
        },
      },
    });

    expect(sql).toContain("lims_results");
  });

  it("names a qualification and a custom nonconformity kind", () => {
    const sql = sqlOf([...BASE, "tags", "cases", "assets", "qualifications"], {
      modules: {
        lims: {
          options: {
            instrumentQualification: "calibration",
            nonconformityKind: "oos",
          },
        },
      },
    });

    expect(sql).toContain("'calibration'");
    expect(sql).toContain("'oos'");
  });

  it("renders nothing in custom mode and lists the functions to implement", () => {
    const custom: Layout = { modules: { lims: { mode: "custom" } } };
    expect(sqlOf(BASE, custom).trim()).toBe("");
    // SAFETY: custom mode returns before reading anything else on the context.
    const context = { mode: "custom" } as unknown as BlockSqlContext;
    expect(LIMS.build(context, {})).toBe("");
    const [contract] = customContracts(["lims"], custom);
    expect(contract?.functions.map((fn) => fn.name)).toEqual(
      expect.arrayContaining([
        "save_lims_method",
        "register_sample",
        "record_lims_result",
        "release_sample",
        "instrument_status",
      ]),
    );
  });
});
