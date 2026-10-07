import { describe, expect, it } from "vitest";

import { substituteParams } from "../../src/sql/read-sets.ts";

describe("substituteParams", () => {
  const substitute = (text: string) =>
    substituteParams(text, (index) => `<${index}>`);

  it("replaces placeholders, two-digit ones whole", () => {
    expect(substitute("select $1, $2 where x = any($10)")).toBe(
      "select <1>, <2> where x = any(<10>)",
    );
  });

  it("leaves $n inside quoted identifiers, literals and plain identifiers", () => {
    expect(
      substitute(
        `select "price$1", 'costs $1', 'it''s $2', "a""$3", price$1 from t where y = $1`,
      ),
    ).toBe(
      `select "price$1", 'costs $1', 'it''s $2', "a""$3", price$1 from t where y = <1>`,
    );
  });

  it("keeps an unterminated quote as it is", () => {
    expect(substitute(`select $1, "open $2`)).toBe(`select <1>, "open $2`);
  });
});
