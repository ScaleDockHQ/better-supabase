import { describe, expect, it } from "vitest";

import type { DocumentVariableType } from "../../../src/sql/modules/document-templates-values.ts";

import { validateDocumentTemplate } from "../../../src/blocks/document-templates/template.ts";
import { renderBlocks } from "../../../src/sql/render.ts";

const BASE = [
  "memberships",
  "permissions",
  "settings",
  "legal-entities",
  "document-templates",
];

const NOTICE: {
  readonly notice: {
    readonly function: string;
    readonly variables: readonly {
      readonly path: string;
      readonly type: DocumentVariableType;
    }[];
  };
} = {
  notice: {
    function: "app.notice_variables",
    variables: [
      { path: "document", type: "object" },
      { path: "document.number", type: "string" },
      { path: "claimant.name", type: "string" },
    ],
  },
};

const sqlOf = (documentTypes?: unknown): string =>
  renderBlocks(
    BASE,
    documentTypes === undefined
      ? {}
      : { modules: { "document-templates": { options: { documentTypes } } } },
  )
    .filter((file) => file.module === "document-templates")
    .map((file) => file.contents)
    .join("\n");

describe("document-templates app types", () => {
  it("adds the type to the checks, the contract and the dispatcher", () => {
    const sql = sqlOf(NOTICE);

    expect(sql).toContain("'notice'");
    expect(sql).toContain(
      'when \'notice\' then return "app"."notice_variables"',
    );
    expect(sql).toContain('"path":"claimant.name"');
  });

  it("changes nothing without the option", () => {
    expect(sqlOf()).not.toContain("'notice'");
  });

  it("refuses a built-in name, a bad function and an empty contract", () => {
    expect(() => sqlOf({ invoice: NOTICE.notice })).toThrow(/built-in/);
    expect(() =>
      sqlOf({ notice: { ...NOTICE.notice, function: "notice_variables" } }),
    ).toThrow(/schema.name/);
    expect(() =>
      sqlOf({ notice: { ...NOTICE.notice, variables: [] } }),
    ).toThrow(/at least one variable/);
  });

  it("validates a template against the app contract", () => {
    const app = { notice: NOTICE.notice.variables };

    expect(
      validateDocumentTemplate("notice", "{{ claimant.name }}", app),
    ).toEqual([]);
    expect(
      validateDocumentTemplate("notice", "{{ totals.total }}", app),
    ).toHaveLength(1);
  });
});
