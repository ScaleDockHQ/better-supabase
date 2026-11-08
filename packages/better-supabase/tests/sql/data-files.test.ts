import { describe, expect, it } from "vitest";

import { splitStatements } from "../../src/sql/index.ts";
import { SQL_MODULES } from "../../src/sql/registry.ts";
import { renderBlocks } from "../../src/sql/render.ts";

const files = renderBlocks(
  Object.keys(SQL_MODULES).filter((name) => name !== "pgtap"),
  { modules: { memberships: { options: { roles: { many: true } } } } },
);

describe("module files and data files", () => {
  it("keeps every top-level insert out of the schema files", () => {
    const inserts = files
      .filter((file) => file.kind === "schema")
      .flatMap((file) =>
        splitStatements(file.contents)
          .filter((statement) => /^insert\s/i.test(statement.text))
          .map((statement) => `${file.path}:${String(statement.line)}`),
      );

    expect(inserts).toEqual([]);
  });

  it("keys every insert of a data file", () => {
    const unkeyed = files
      .filter((file) => file.kind === "data")
      .flatMap((file) =>
        splitStatements(file.contents)
          .filter(
            (statement) =>
              /^insert\s/i.test(statement.text) &&
              !/\bon\s+conflict\b/i.test(statement.text) &&
              !/\bnot\s+exists\b/i.test(statement.text),
          )
          .map((statement) => `${file.path}:${String(statement.line)}`),
      );

    expect(unkeyed).toEqual([]);
  });

  it("gives every seed function a locale", () => {
    const functions = files
      .filter((file) => file.kind === "schema")
      .flatMap((file) =>
        [
          ...file.contents.matchAll(
            /create\s+(?:or\s+replace\s+)?function\s+[\w".]*?"?(seed_\w+_defaults)"?\s*\(([^)]*)\)/gi,
          ),
        ].map((match) => ({ name: match[1]!, args: match[2]! })),
      );

    expect(functions.length).toBeGreaterThan(0);
    expect(functions.filter((fn) => !fn.args.includes("p_locale"))).toEqual([]);
  });

  it("writes the memberships backfill as a keyed upsert in its data file", () => {
    const data = files.find(
      (file) => file.kind === "data" && file.module === "memberships",
    );

    expect(data?.contents).toContain(
      'on conflict ("organization_id", "user_id", "role") do nothing',
    );
  });
});
