import { describe, expect, it } from "vitest";

import { renderBlocks } from "./app-columns.ts";

// A write that takes `fields jsonb` only with extra columns has two
// signatures; a build creates one of them.

function render(module: string, extraColumns?: object): string {
  return renderBlocks([module], {
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

describe("the fields parameter of writes with extra columns", () => {
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
