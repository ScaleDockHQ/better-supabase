import { describe, expect, it } from "vitest";

import {
  arrayOf,
  block,
  indent,
  nullable,
  parseCheckUnion,
  prop,
  sameColumns,
  singular,
} from "../../src/gen/shared.ts";

describe("gen helpers", () => {
  it("quotes property keys that are not identifiers", () => {
    expect(prop("orgId")).toBe("orgId");
    expect(prop("org-id")).toBe('"org-id"');
  });

  it("adds null only to nullable types", () => {
    expect(nullable("string", true)).toBe("string | null");
    expect(nullable("string", false)).toBe("string");
  });

  it("parenthesizes compound array element types", () => {
    expect(arrayOf("Json")).toBe("Json[]");
    expect(arrayOf('"a" | "b"')).toBe('("a" | "b")[]');
  });

  it("indents every non-empty line", () => {
    expect(indent(["a\n\nb"], 2)).toEqual(["    a", "", "    b"]);
  });

  it("writes an inline type for an empty block", () => {
    expect(block("Views", [])).toEqual(["Views: { [_ in never]: never };"]);
    expect(block("Row", ["id: string;"])).toEqual([
      "Row: {",
      "  id: string;",
      "};",
    ]);
  });

  it("compares column lists without order", () => {
    expect(sameColumns(["a", "b"], ["b", "a"])).toBe(true);
    expect(sameColumns(["a"], ["a", "b"])).toBe(false);
    expect(sameColumns(["a", "c"], ["a", "b"])).toBe(false);
  });

  it("singularizes table names", () => {
    expect(singular("companies")).toBe("company");
    expect(singular("addresses")).toBe("address");
    expect(singular("tags")).toBe("tag");
    expect(singular("access")).toBe("access");
    expect(singular("staff")).toBe("staff");
  });
});

describe("parseCheckUnion", () => {
  it("ignores an ANY constraint without literals", () => {
    expect(
      parseCheckUnion("CHECK ((status = ANY (ARRAY[other_column])))"),
    ).toBeUndefined();
  });

  it("needs at least two terms in an OR chain", () => {
    expect(parseCheckUnion("CHECK ((kind = 'a'::text))")).toBeUndefined();
  });

  it("rejects an OR chain with a term that is not an equality", () => {
    expect(
      parseCheckUnion("CHECK (((kind = 'a'::text) OR (length(kind) > 2)))"),
    ).toBeUndefined();
  });
});
