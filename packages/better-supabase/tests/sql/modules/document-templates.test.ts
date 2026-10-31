import { describe, expect, it } from "vitest";

import {
  DOCUMENT_TYPES,
  DOCUMENT_VARIABLES,
  documentContract,
} from "../../../src/sql/modules/document-templates-values.ts";
import { renderBlocks } from "../../../src/sql/render.ts";

const BASE = [
  "memberships",
  "permissions",
  "settings",
  "legal-entities",
  "document-templates",
];

const sqlOf = (modules: readonly string[] = BASE): string =>
  renderBlocks(modules, {})
    .filter((file) => file.module === "document-templates")
    .map((file) => file.contents)
    .join("\n");

describe("document-templates module", () => {
  it("keeps one template per slot and one snapshot per document", () => {
    const sql = sqlOf();

    expect(sql).toMatch(/unique index[^;]*"document_type"[^;]*"name"/is);
    expect(sql).toMatch(/unique[^;]*"document_type"[^;]*"document_id"/is);
  });

  it("raises the hint of each validation issue", () => {
    const sql = sqlOf();

    expect(sql).toContain("hint = 'DOCUMENT_TEMPLATE_UNKNOWN_VARIABLE'");
    expect(sql).toContain("DOCUMENT_TEMPLATE_SYNTAX");
    expect(sql).toContain("DOCUMENT_TEMPLATE_UNKNOWN_FILTER");
  });

  it("refuses to change a frozen document", () => {
    expect(sqlOf()).toContain("DOCUMENT_SNAPSHOT_IMMUTABLE");
  });

  it("renders without the invoices module, reading only what is installed", () => {
    expect(() => sqlOf()).not.toThrow();
  });
});

describe("document variables over the installed modules", () => {
  const FULL = [
    ...BASE,
    "contacts",
    "tax",
    "invoices",
    "quotes",
    "orders",
    "shipments",
  ];

  const full = (on: readonly string[]): string =>
    renderBlocks(FULL, {
      modules: { "legal-entities": { options: { on: [...on] } } },
    })
      .filter((file) => file.module === "document-templates")
      .map((file) => file.contents)
      .join("\n");

  it("builds every document type when its block is installed", () => {
    const sql = full([]);

    for (const name of [
      "invoice",
      "quote",
      "order",
      "delivery_note",
      "dunning_letter",
      "statement",
    ]) {
      expect(sql).toContain(`document_variables_${name}`);
    }

    expect(sql).not.toContain("documents need the");
  });

  it("reads the legal entity column only where the entity is extended", () => {
    const plain = full([]);
    const extended = full(["invoices", "quotes", "orders"]);

    expect(extended).not.toBe(plain);
    expect(extended.length).toBeGreaterThan(plain.length);
  });

  it("names the missing block for a type it cannot build", () => {
    const sql = sqlOf([
      "memberships",
      "permissions",
      "settings",
      "legal-entities",
      "invoices",
      "document-templates",
    ]);

    expect(sql).toContain("quote documents need the quotes block");
    expect(sql).toContain("DOCUMENT_TYPE_UNAVAILABLE");
  });
});

describe("the variable contract", () => {
  it("lists variables for every document type", () => {
    for (const type of DOCUMENT_TYPES) {
      const contract = documentContract(type);

      expect(contract.version).toBe(1);
      expect(contract.variables.length).toBeGreaterThan(10);
      expect(contract.variables.map((variable) => variable.path)).toContain(
        "document.number",
      );
    }
  });

  it("names no variable twice for one type", () => {
    for (const type of DOCUMENT_TYPES) {
      const paths = documentContract(type).variables.map(
        (variable) => variable.path,
      );

      expect(new Set(paths).size).toBe(paths.length);
    }
  });

  it("describes every variable", () => {
    for (const type of DOCUMENT_TYPES) {
      expect(
        DOCUMENT_VARIABLES[type].every((variable) => variable.description),
      ).toBe(true);
    }
  });
});
