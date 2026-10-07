import { describe, expect, it } from "vitest";

import { renderModules, SQL_MODULES } from "../../src/sql/registry.ts";

/** Every function a rendered file creates that has no `set search_path`. */
function mutable(contents: string): string[] {
  return contents
    .split(/(?=create (?:or replace )?function )/i)
    .filter((part) => /^create (?:or replace )?function /i.test(part))
    .filter((part) => {
      const end = part.search(/\bas \$/);
      return !/\bset search_path\b/i.test(part.slice(0, end));
    })
    .map((part) => part.slice(0, part.indexOf("(")));
}

describe("function search paths", () => {
  it("fixes the search_path of every module and pgTAP kit function", () => {
    const names = Object.keys(SQL_MODULES);
    const layouts = [
      {},
      {
        modules: {
          tenant: {
            options: {
              sameTenant: [
                {
                  table: "tasks",
                  column: "project_id",
                  references: "projects",
                },
              ],
            },
          },
          "data-lifecycle": {
            options: {
              anonymize: [
                {
                  table: "candidates",
                  after: "1 year",
                  from: "ended_at",
                  set: { email: null },
                  markedBy: "anonymized_at",
                },
              ],
            },
          },
        },
      },
    ];
    for (const layout of layouts) {
      const files = renderModules(names, layout);
      expect(files.some((file) => file.module === "pgtap")).toBe(true);
      const found = files.flatMap((file) =>
        mutable(file.contents).map((fn) => `${file.module}: ${fn}`),
      );
      expect(found).toEqual([]);
    }
  });

  it("finds a function without one", () => {
    expect(
      mutable(
        "create or replace function a.b()\nreturns void\nlanguage sql\nas $$ select 1 $$;\ncreate function a.c() returns void language sql set search_path = '' as $$ select 1 $$;",
      ),
    ).toEqual(["create or replace function a.b"]);
  });
});
