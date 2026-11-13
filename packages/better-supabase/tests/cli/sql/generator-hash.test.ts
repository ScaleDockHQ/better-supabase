import { existsSync, readFileSync } from "node:fs";
import { dirname, join, relative, resolve } from "node:path";
import { describe, expect, it } from "vitest";

import {
  generatorHash,
  generatorRoot,
} from "../../../src/cli/sql/generator-hash.ts";

const RELATIVE_IMPORT = /\bfrom\s+"(\.{1,2}\/[^"]+)"/gu;

/** Every source file `entry` reaches through relative imports. */
function importClosure(entry: string): ReadonlySet<string> {
  const found = new Set<string>();
  const queue = [entry];

  for (let file = queue.pop(); file !== undefined; file = queue.pop()) {
    if (found.has(file)) {
      continue;
    }

    found.add(file);

    for (const match of readFileSync(file, "utf-8").matchAll(RELATIVE_IMPORT)) {
      const target = resolve(dirname(file), match[1] ?? "");

      if (target.endsWith(".ts") && existsSync(target)) {
        queue.push(target);
      }
    }
  }

  return found;
}

describe("generatorHash", () => {
  it("is one stable hex digest per process", async () => {
    const first = await generatorHash();

    expect(first).toMatch(/^[0-9a-f]{64}$/u);
    expect(await generatorHash()).toBe(first);
  });

  // EX-1115: the hash covered only src/sql, so a change to a block's search
  // subjects (the preset catalog) left the salt alone and gen served renders
  // without the search triggers.
  it("covers every file the SQL render imports", () => {
    const root = generatorRoot();
    const render = join(root, "sql/render.ts");
    const closure = [...importClosure(render)];

    expect(closure).toContain(join(root, "config/block-subjects.ts"));
    expect(closure).toContain(join(root, "preset/catalog.generated.ts"));
    expect(
      closure.filter((file) => relative(root, file).startsWith("..")),
    ).toEqual([]);
  });
});
