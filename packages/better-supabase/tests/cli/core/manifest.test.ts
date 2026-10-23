import { globSync, readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";

import type { CommandEffect } from "../../../src/cli/core/manifest.ts";

import { builtinCommands } from "../../../src/cli/builtin-commands.ts";
import {
  COMMANDS,
  findSpec,
  RESERVED_NAMES,
  specPaths,
} from "../../../src/cli/core/manifest.ts";
import { commandArgs } from "../../../src/cli/core/parse.ts";

const DOCS = fileURLToPath(
  new URL("../../../../../apps/docs/content/docs/", import.meta.url),
);

/**
 * A docs URL mapped to its file, with sidebar route groups left out of the
 * slug.
 */
const PAGE_FILES = new Map<string, string>(
  globSync("**/*.mdx", { cwd: DOCS }).map((file) => {
    const slug = file
      .split("/")
      .filter((part) => !/^\(.+\)$/u.test(part))
      .join("/")
      .replace(/\.mdx$/u, "")
      .replace(/\/index$/u, "");

    return [`docs/${slug}`, file] as const;
  }),
);

const { loaders } = builtinCommands();

const leaves = specPaths()
  .filter((path) => (findSpec(path)?.subcommands ?? []).length === 0)
  .map((path) => path.join(" "));

/** The heading anchors Fumadocs generates for a page. */
function anchors(markdown: string): Set<string> {
  return new Set(
    [...markdown.matchAll(/^#{2,4} (.+)$/gm)].map(([, heading = ""]) =>
      heading
        .toLowerCase()
        .replaceAll(/[`'"()<>.,:;]/g, "")
        .trim()
        .replaceAll(/\s+/g, "-"),
    ),
  );
}

describe("command manifest", () => {
  it("has a loader for every leaf and a leaf for every loader", () => {
    expect([...loaders.keys()].toSorted()).toEqual(leaves.toSorted());
  });

  it("gives every built-in command a docs link and its effects, and each top-level one a group", () => {
    const incomplete = specPaths()
      .filter((path) => {
        const spec = findSpec(path);
        const grouped = path.length > 1 || spec?.group !== undefined;

        return !(grouped && spec?.docs && spec.effects);
      })
      .map((path) => path.join(" "));

    expect(incomplete).toEqual([]);
  });

  it("leaves the reserved names free", () => {
    for (const spec of COMMANDS) {
      expect(RESERVED_NAMES).not.toContain(spec.name);
    }
  });

  it.each(specPaths().map((path) => path.join(" ")))(
    "links %s to a docs page and heading that exist",
    (path) => {
      const docs = findSpec(path.split(" "))?.docs ?? "";
      const [page = "", anchor] = docs.replace(/^\//, "").split("#");

      const relative = PAGE_FILES.get(page);
      const file = relative === undefined ? undefined : `${DOCS}${relative}`;

      const headings = file ? [...anchors(readFileSync(file, "utf-8"))] : [];

      expect({ docs, found: file !== undefined }).toEqual({
        docs,
        found: true,
      });
      expect(anchor === undefined || headings.includes(anchor)).toBe(true);
    },
  );

  it.each(leaves)("declares the effects behind the %s flags", async (path) => {
    const command = await loaders.get(path)!();
    const args = await commandArgs(command);

    const effects: readonly CommandEffect[] =
      findSpec(path.split(" "))?.effects ?? [];

    const has = (match: (effect: CommandEffect) => boolean): boolean =>
      effects.some(match);

    const callsApi = has(
      (effect) => effect.kind === "network" && effect.target === "supabase-api",
    );

    const usesDatabase = has((effect) => effect.kind === "database");

    const whenFlags = effects.flatMap((effect) =>
      effect.when ? [effect.when.replace(/^--/, "")] : [],
    );

    expect(!("project-ref" in args) || callsApi).toBe(true);
    expect(!("db-url-stdin" in args) || usesDatabase).toBe(true);
    expect(whenFlags.filter((flag) => !(flag in args))).toEqual([]);
  });
});
