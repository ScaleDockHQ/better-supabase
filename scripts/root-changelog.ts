import { assembleReleasePlan } from "@changesets/assemble-release-plan";
import { readConfig } from "@changesets/config";
import { readPreState } from "@changesets/pre";
import { readChangesets } from "@changesets/read";
import { getPackages } from "@manypkg/get-packages";
// Prepends a dated section with every pending changeset summary to the root
// CHANGELOG.md. `changeset version` deletes the changeset files, so
// `pnpm version-packages` runs this first.
import { readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { cwd, exit } from "node:process";

const primaryPackage = "better-supabase";
const heading = "# Changelog";

const root = cwd();
const changesets = await readChangesets(root);
if (changesets.length === 0) {
  console.log("root-changelog: no changesets, CHANGELOG.md unchanged.");
  exit(0);
}

const packages = await getPackages(root);
const parsed = await readConfig(root, packages);
if (parsed.config === undefined) {
  console.error(
    `root-changelog: invalid .changeset/config.json\n${parsed.errors.join("\n")}`,
  );
  exit(1);
}

const plan = assembleReleasePlan(
  changesets,
  packages,
  parsed.config,
  await readPreState(root),
);
const release =
  plan.releases.find((candidate) => candidate.name === primaryPackage) ??
  plan.releases[0];
if (release === undefined) {
  console.log(
    "root-changelog: the changesets release no package, CHANGELOG.md unchanged.",
  );
  exit(0);
}

const bumpOrder = { major: 0, minor: 1, patch: 2, none: 3 } as const;
const rank = (changeset: (typeof changesets)[number]): number =>
  Math.min(...changeset.releases.map((entry) => bumpOrder[entry.type]));

const entries = changesets
  .toSorted((a, b) => rank(a) - rank(b))
  .map((changeset) => {
    const [first = "", ...rest] = changeset.summary.trim().split("\n");
    return [
      `- ${first}`,
      ...rest.map((line) => (line === "" ? "" : `  ${line}`)),
    ].join("\n");
  });

const date = new Date().toISOString().slice(0, 10);
const section = `## ${release.newVersion} (${date})\n\n${entries.join("\n")}\n`;

const path = join(root, "CHANGELOG.md");
const current = readFileSync(path, "utf8");
const body = current.startsWith(heading)
  ? current.slice(heading.length).trimStart()
  : current;
writeFileSync(path, `${heading}\n\n${section}\n${body}`);
console.log(
  `root-changelog: added ${release.newVersion} with ${entries.length} entries.`,
);
