import { describe, expect, it } from "vitest";

import {
  primeStatements,
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
});
