import { describe, expect, it } from "vitest";

import {
  codeStatementsOf,
  primeCodeStatements,
  primeStatements,
  rawStatementsOf,
  statementsOf,
} from "../../../src/cli/schema-reader/index.ts";

const split = async (text: string) => {
  await primeStatements([text]);

  return statementsOf(text);
};

describe("statementsOf", () => {
  it("splits at semicolons outside quotes, dollar quotes and comments", async () => {
    expect(
      await split(
        [
          "-- a comment; with a semicolon",
          "create table a (x text default 'a;b');",
          "/* block; /* nested; */ */",
          "create function f() returns void language plpgsql as $body$",
          "begin perform 1; end;",
          "$body$;",
          'select ";" as "x;y"',
        ].join("\n"),
      ),
    ).toEqual([
      { text: "create table a (x text default 'a;b')", line: 2 },
      {
        text: "create function f() returns void language plpgsql as $body$\nbegin perform 1; end;\n$body$",
        line: 4,
      },
      { text: 'select ";" as "x;y"', line: 7 },
    ]);
  });

  it("reads CRLF text with the same statements and lines", async () => {
    const lf = await split("select 1;\n-- note\nselect 2;\n");
    const crlf = await split("select 1;\r\n-- note\r\nselect 2;\r\n");

    expect(crlf.map((statement) => statement.line)).toEqual(
      lf.map((statement) => statement.line),
    );
    expect(crlf.map((statement) => statement.text)).toEqual(
      lf.map((statement) => statement.text),
    );
  });

  it("splits a text that does not parse", async () => {
    expect(await split("selec 1;\nselect 2;")).toHaveLength(2);
  });

  it("keeps a begin atomic body and a multi-action rule whole", async () => {
    const text = [
      "create function f(x int) returns int language sql",
      "begin atomic",
      "  select case when x > 0 then 1 else 0 end;",
      "  select 2;",
      "end;",
      "create rule r as on insert to t do also (",
      "  insert into a values (1);",
      "  update b set c = 1",
      ");",
      "select 3;",
    ].join("\n");

    expect((await split(text)).map((statement) => statement.line)).toEqual([
      1, 6, 10,
    ]);
    expect(rawStatementsOf(text)).toHaveLength(3);

    await primeCodeStatements([text]);

    expect(codeStatementsOf(text).map((statement) => statement.line)).toEqual([
      1, 6, 10,
    ]);
  });

  it("splits after an unclosed parenthesis so later statements stay", async () => {
    expect(await split("select (1;\nselect 2;")).toHaveLength(2);
  });
});
