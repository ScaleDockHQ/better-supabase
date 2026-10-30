import { describe, expect, it } from "vitest";

import type { BlockSqlContext } from "../../../src/sql/context.ts";

import {
  DEFAULT_RISK_MATRIX,
  riskMatrixProblem,
} from "../../../src/sql/modules/risks-sql.ts";
import { RISKS } from "../../../src/sql/modules/risks.ts";
import { customContracts, renderBlocks } from "../../../src/sql/render.ts";

type Layout = Parameters<typeof renderBlocks>[1];

const BASE = ["memberships", "permissions", "subjects", "versions", "risks"];

const sqlOf = (
  layout: Layout = {},
  modules: readonly string[] = BASE,
): string =>
  renderBlocks(modules, layout)
    .filter((file) => file.module === "risks")
    .map((file) => file.contents)
    .join("\n");

describe("risks module", () => {
  it("reads barriers and cases only with relations installed", () => {
    expect(sqlOf()).not.toContain("'mitigated_by'");
    const linked = sqlOf({}, [...BASE, "relations"]);
    expect(linked).toContain("'mitigated_by'");
    expect(linked).toContain("'materialized_as'");
  });

  it("notifies the owner of a due review only with notifications installed", () => {
    expect(sqlOf()).not.toContain("'risk.review_date_reached:' ||");
    expect(sqlOf({}, [...BASE, "notifications"])).toContain(
      "'risk.review_date_reached:' ||",
    );
  });

  it("checks categories and seeds the default matrix from the options", () => {
    const sql = sqlOf({
      modules: {
        risks: {
          options: {
            categories: ["product", "privacy"],
            defaultMatrix: {
              ...DEFAULT_RISK_MATRIX,
              key: "iso",
              name: "ISO 14971",
            },
          },
        },
      },
    });

    expect(sql).toContain("array['product', 'privacy']::text[]");
    expect(sql).toContain("'ISO 14971'");
  });

  it("rejects a default matrix with gaps between its bands", () => {
    expect(riskMatrixProblem(DEFAULT_RISK_MATRIX)).toBeUndefined();

    const gap = {
      ...DEFAULT_RISK_MATRIX,
      bands: DEFAULT_RISK_MATRIX.bands.filter((band) => band.key !== "medium"),
    };

    expect(riskMatrixProblem(gap)).toMatch(/cover/);
    expect(() =>
      sqlOf({ modules: { risks: { options: { defaultMatrix: gap } } } }),
    ).toThrow(TypeError);
  });

  it("refuses to build on versions in custom mode", () => {
    expect(() => sqlOf({ modules: { versions: { mode: "custom" } } })).toThrow(
      "blocks.risks needs the versions tables",
    );
  });

  it("renders nothing in custom mode and lists the functions to implement", () => {
    const custom: Layout = { modules: { risks: { mode: "custom" } } };
    expect(sqlOf(custom).trim()).toBe("");
    // SAFETY: custom mode returns before reading anything else on the context.
    const context = { mode: "custom" } as unknown as BlockSqlContext;
    expect(RISKS.build(context, {})).toBe("");
    const [contract] = customContracts(["risks"], custom);
    expect(contract?.functions.map((fn) => fn.name)).toEqual(
      expect.arrayContaining([
        "save_risk_matrix",
        "create_risk",
        "assess_risk",
        "risk_heatmap",
        "notify_due_risk_reviews",
      ]),
    );
  });
});
