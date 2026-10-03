// Copies the better-supabase version into the files `changeset version` does
// not touch: both VERSION constants, the plugin manifests and server.json.
// `pnpm version-packages` runs it after `changeset version`.
import { getPackages } from "@manypkg/get-packages";
import { readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { cwd } from "node:process";

const root = cwd();
const read = (path: string): string => readFileSync(join(root, path), "utf8");

const library = (await getPackages(root)).packages.find(
  (candidate) => candidate.packageJson.name === "better-supabase",
);
if (library === undefined)
  throw new Error("sync-versions: no better-supabase package in the workspace");
const { version } = library.packageJson;

const MANIFEST_VERSION = /("version":\s*")[^"]+(")/g;
const constant = (): string => `export const VERSION = "${version}";\n`;
const manifestVersion = (source: string): string =>
  source.replace(MANIFEST_VERSION, `$1${version}$2`);

const files = {
  "packages/better-supabase/src/core/version.ts": constant,
  "packages/better-supabase/src/cli/version.ts": constant,
  ".claude-plugin/plugin.json": manifestVersion,
  ".claude-plugin/marketplace.json": manifestVersion,
  ".cursor-plugin/plugin.json": manifestVersion,
  "server.json": manifestVersion,
} satisfies Record<string, (source: string) => string>;

const written: string[] = [];
for (const [path, update] of Object.entries(files)) {
  const current = read(path);
  const next = update(current);
  if (next === current) continue;
  writeFileSync(join(root, path), next);
  written.push(path);
}

console.log(
  written.length === 0
    ? `sync-versions: every file is at ${version}.`
    : `sync-versions: wrote ${version} to ${written.join(", ")}.`,
);
