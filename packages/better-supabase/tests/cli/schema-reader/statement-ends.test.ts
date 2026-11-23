import { describe, expect, it } from "vitest";

import { statementEnds } from "../../../src/cli/schema-reader/statement-ends.ts";

const words = (text: string): string[] => text.split(" ");

describe("statementEnds", () => {
  it("ends at every top-level semicolon", () => {
    expect([...statementEnds(words("select 1 ; select 2 ;"))]).toEqual([2, 5]);
  });

  it("keeps the semicolons inside parentheses", () => {
    expect([
      ...statementEnds(words("do also ( insert ; update ) ; select ;")),
    ]).toEqual([7, 9]);
  });

  it("keeps the semicolons inside begin atomic, with case closing on end", () => {
    expect([
      ...statementEnds(
        words("begin atomic select case when x then 1 end ; select 2 ; end ;"),
      ),
    ]).toEqual([14]);
  });

  it("ends at every semicolon when the nesting never closes", () => {
    expect([...statementEnds(words("select ( 1 ; select 2 ;"))]).toEqual([
      3, 6,
    ]);
  });

  it("ignores a lone begin and a lone end", () => {
    expect([...statementEnds(words("begin ; end ;"))]).toEqual([1, 3]);
  });
});
