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

/** The `peers:` catalog, as name to range. */
function peersCatalog(): Map<string, string> {
  const start = workspace.indexOf("\n  peers:\n");
  const lines = workspace.slice(start + "\n  peers:\n".length).split("\n");
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

/** The page's table, as peer to range. */
function pageRows(): Map<string, string> {
  return new Map(
    [...page.matchAll(/^\| `([^`]+)`\s*\| `([^`]+)`\s*\|/gm)].map((match) => [
      match[1]!,
      match[2]!,
    ]),
  );
}

describe("the peers page", () => {
  const peers: Record<string, string> = JSON.parse(manifest).peerDependencies;
  const catalog = peersCatalog();
  const rows = pageRows();

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
});
