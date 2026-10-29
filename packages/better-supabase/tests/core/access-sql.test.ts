import { describe, expect, it } from "vitest";

import {
  fillTemplate,
  sameTemplateFunction,
  templateProblems,
} from "../../src/core/access-sql.ts";
import { tokenizeTemplate } from "../../src/core/sql-template-tokens.ts";

describe("templateProblems", () => {
  it("accepts schema-qualified calls and placeholders", () => {
    expect(
      templateProblems(
        "select id from app.ids_with({permission}, {scope}) where x in (1, 2)",
      ),
    ).toEqual([]);
  });

  it("ignores ; -- and calls inside strings and quoted identifiers", () => {
    expect(templateProblems(`select 'a;b -- c f(x)' as "odd;(name"`)).toEqual(
      [],
    );
    expect(templateProblems(String.raw`select E'it\'s; f(x)'`)).toEqual([]);
  });

  it("refuses dollar quotes, tagged ones too", () => {
    expect(templateProblems("select $$x$$")).toEqual(['contains "$$"']);
    expect(templateProblems("select $tag$x$tag$")).toContain(
      'contains "$tag$"',
    );
  });

  it("refuses a semicolon, a line comment and a block comment", () => {
    expect(templateProblems("select 1; select 2")).toEqual(['contains ";"']);
    expect(templateProblems("select 1 -- x")).toEqual(['contains "--"']);
    expect(templateProblems("select /* x */ 1")).toEqual(['contains "/*"']);
  });

  it("refuses unterminated strings, identifiers and comments", () => {
    expect(templateProblems("select 'oops")).toEqual([
      "contains an unterminated string",
    ]);
    expect(templateProblems('select "oops')).toEqual([
      "contains an unterminated identifier",
    ]);
    expect(templateProblems("select /* oops")).toEqual([
      "contains an unterminated comment",
    ]);
  });

  it("refuses a stray brace", () => {
    expect(templateProblems("select {")).toEqual([
      'contains a "{" that is not a {name} placeholder',
    ]);
  });

  it("refuses a call without a schema, quoted or not", () => {
    expect(templateProblems("select now()")).toEqual([
      "calls now() without a schema",
    ]);
    expect(templateProblems('select "now"()')).toEqual([
      "calls now() without a schema",
    ]);
  });

  it("does not treat keywords followed by a paren as calls", () => {
    expect(templateProblems("select 1 where a in (1) and not (b)")).toEqual([]);
  });
});

describe("sameTemplateFunction", () => {
  it("matches {resource} against any resource name, either way round", () => {
    expect(
      sameTemplateFunction("authz.{resource}_ids", "authz.file_node_ids"),
    ).toBe(true);
    expect(
      sameTemplateFunction("authz.file_node_ids", "authz.{resource}_ids"),
    ).toBe(true);
    expect(sameTemplateFunction("authz.ids", "AUTHZ.IDS")).toBe(true);
  });

  it("keeps the rest of the name literal", () => {
    expect(
      sameTemplateFunction("authz.{resource}_ids", "authz.file_node_id"),
    ).toBe(false);
    expect(sameTemplateFunction("authz.{resource}_ids", "authzx_ids")).toBe(
      false,
    );
    expect(sameTemplateFunction("authz.{resource}_ids", "authz._ids")).toBe(
      false,
    );
    expect(
      sameTemplateFunction("authz.{resource}_ids", 'authz."a-b"_ids'),
    ).toBe(false);
  });
});

describe("fillTemplate", () => {
  it("fills placeholders", () => {
    expect(fillTemplate("x", "select {a}", { a: "1" })).toBe("select 1");
  });

  it("throws for an unsafe template", () => {
    expect(() => fillTemplate("x", "select 1; drop", {})).toThrow(
      'x: the template contains ";"',
    );
  });

  it("throws for an unknown placeholder", () => {
    expect(() => fillTemplate("x", "select {b}", { a: "1" })).toThrow(
      "{b} is not available here",
    );
  });
});

describe("tokenizeTemplate", () => {
  it("round-trips the source", () => {
    const source = `select 'a' || "b" from {x}.t -- c`;
    expect(
      tokenizeTemplate(source)
        .map((token) =>
          token.kind === "placeholder"
            ? `{${token.text}}`
            : token.kind === "word" && token.quoted
              ? `"${token.text}"`
              : token.text,
        )
        .join(""),
    ).toBe(source);
  });
});
