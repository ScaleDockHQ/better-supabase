import { readFile } from "node:fs/promises";
import { join } from "node:path";
import { describe, expect, it } from "vitest";

const repo = join(import.meta.dirname, "../../..");

const [workspace, manifest, page] = await Promise.all([
  readFile(join(repo, "pnpm-workspace.yaml"), "utf-8"),
  readFile(join(repo, "packages/better-supabase/package.json"), "utf-8"),
  readFile(
    join(
      repo,
      "apps/docs/content/docs/(docs)/(get-started)/getting-started/peers.mdx",
    ),
    "utf-8",
  ),
]);

/** A named catalog in `pnpm-workspace.yaml`, as name to range. */
function peersCatalogFor(name: string): Map<string, string> {
  const marker = `\n  ${name}:\n`;
  const start = workspace.indexOf(marker);
  const lines = workspace.slice(start + marker.length).split("\n");
  const ranges = new Map<string, string>();

  for (const line of lines) {
    if (!line.startsWith("    ")) {
      break;
    }

    const match = /^\s+"?([^"#:\s][^":]*)"?:\s*"?([^"]+?)"?\s*$/.exec(line);

    if (match) {
      ranges.set(match[1]!, match[2]!);
    }
  }

  return ranges;
}

/** The page's tables, as package to range. */
function pageRows(section: string): Map<string, string> {
  const start = page.indexOf(`## ${section}`);
  const end = page.indexOf("\n## ", start + 1);
  const body = page.slice(start, end === -1 ? undefined : end);

  return new Map(
    [...body.matchAll(/^\| `([^`]+)`\s*\| `([^`]+)`\s*\|/gm)].map((match) => [
      match[1]!,
      match[2]!,
    ]),
  );
}

describe("the peers page", () => {
  const peers: Record<string, string> = JSON.parse(manifest).peerDependencies;
  const catalog = peersCatalogFor("peers");
  const rows = pageRows("Peers");

  const dependencies: Record<string, string> =
    JSON.parse(manifest).dependencies;

  const installed = pageRows("Dependencies the CLI installs");

  it("lists every peer with the range the package declares", () => {
    const names = Object.keys(peers);
    expect(
      Object.values(peers).every((specifier) => specifier === "catalog:peers"),
    ).toBe(true);
    expect(
      Object.fromEntries(names.map((name) => [name, rows.get(name)])),
    ).toEqual(
      Object.fromEntries(names.map((name) => [name, catalog.get(name)])),
    );
  });

  it("lists nothing that isn't a peer", () => {
    expect([...rows.keys()].filter((name) => !(name in peers))).toEqual([]);
  });

  it("lists the CLI's pinned dependencies with their catalog versions", () => {
    const pinned = [
      "oxc-parser",
      "@supabase/pg-parser",
      "@supabase/pg-delta",
      "@supabase/pg-topo",
    ];

    const deps = peersCatalogFor("deps");

    expect([...installed.keys()]).toEqual(pinned);

    for (const name of pinned) {
      expect(dependencies[name]).toBe("catalog:deps");
      expect(installed.get(name)).toBe(deps.get(name));
    }
  });
});
