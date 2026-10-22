import { describe, expect, it } from "vitest";

import { SQL_MODULES } from "../../src/sql/registry.ts";
import { renderModules } from "../../src/sql/render.ts";

// A write that takes `fields jsonb` only with extra columns has two
// signatures. Each build drops the one it doesn't create, so turning
// `extraColumns` on or off never leaves two overloads a call matches.

const MODULES = Object.entries(SQL_MODULES)
  .filter(([, module]) => module.names?.options?.includes("extraColumns"))
  .map(([name]) => name);

function render(module: string, extraColumns?: object): string {
  return renderModules([module], {
    modules: { [module]: { options: extraColumns ? { extraColumns } : {} } },
  })
    .filter((file) => file.module === module)
    .map((file) => file.contents)
    .join("\n");
}

/** Splits a parameter list at its top-level commas. */
function params(list: string): string[] {
  const out: string[] = [];
  let depth = 0;
  let quoted = false;
  let current = "";

  for (const char of list) {
    if (char === "'") {
      quoted = !quoted;
    }

    if (!quoted && char === "(") {
      depth += 1;
    }

    if (!quoted && char === ")") {
      depth -= 1;
    }

    if (!quoted && depth === 0 && char === ",") {
      out.push(current.trim());
      current = "";
    } else {
      current += char;
    }
  }

  if (current.trim() !== "") {
    out.push(current.trim());
  }

  return out;
}

const CREATE = /create or replace function ([^\s(]+)\(([\s\S]*?)\)\nreturns/g;

/** Each function's parameters, by name. */
function functions(sql: string): Map<string, string[]> {
  return new Map(
    [...sql.matchAll(CREATE)].map((match) => [
      match[1] ?? "",
      params(match[2] ?? ""),
    ]),
  );
}

/** The argument counts of each `drop function if exists` of `name`. */
function drops(sql: string, name: string): number[] {
  const escaped = name.replaceAll(/[.*+?^${}()|[\]\\]/g, "\\$&");

  return [
    ...sql.matchAll(
      new RegExp(`drop function if exists ${escaped}\\(([^;]*)\\);`, "g"),
    ),
  ].map((match) => params(match[1] ?? "").length);
}

describe("the fields parameter of writes with extra columns", () => {
  it.each(MODULES)("%s drops the signature it doesn't create", (module) => {
    const plain = render(module);
    const extra = render(module, { app_note: "text" });
    const before = functions(plain);

    const added = [...functions(extra)].filter(
      ([name, list]) =>
        list.at(-1) === "fields jsonb default null" &&
        before.get(name)?.at(-1) !== "fields jsonb default null",
    );

    for (const [name, list] of added) {
      expect(drops(plain, name), `${name} without extra columns`).toContain(
        list.length,
      );
      expect(drops(extra, name), `${name} with extra columns`).toContain(
        list.length - 1,
      );
    }
  });

  it("finds the writes of the modules that take fields", () => {
    const extra = render("tags", { app_note: "text" });
    expect(
      [...functions(extra)]
        .filter(([, list]) => list.at(-1) === "fields jsonb default null")
        .map(([name]) => name),
    ).toEqual([
      '"better_supabase"."create_tag"',
      '"better_supabase"."update_tag"',
    ]);
  });
});
