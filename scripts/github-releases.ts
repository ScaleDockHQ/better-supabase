// Creates a GitHub Release for each package the release workflow published.
// GitHub rejects a release body above 125,000 characters, and a 0.x changelog
// section can pass that, so the body is cut at a line boundary and ends with a
// link to the full changelog.
import { execFileSync } from "node:child_process";
import {
  existsSync,
  mkdtempSync,
  readdirSync,
  readFileSync,
  writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { argv, cwd, env, exit } from "node:process";

/** GitHub's limit is 125,000; this leaves room for the link. */
export const MAX_BODY_LENGTH = 120_000;

export interface PublishedPackage {
  readonly name: string;
  readonly version: string;
}

/** The section of a changesets changelog that belongs to `version`. */
export function changelogSection(changelog: string, version: string): string {
  const lines = changelog.split("\n");
  const start = lines.findIndex((line) => line.trim() === `## ${version}`);

  if (start === -1) {
    return "";
  }

  const next = lines.findIndex(
    (line, index) => index > start && line.startsWith("## "),
  );

  return lines
    .slice(start + 1, next === -1 ? undefined : next)
    .join("\n")
    .trim();
}

/**
 * Cuts `body` at the last line break under the limit and links the full
 * changelog.
 */
export function truncateNotes(
  body: string,
  changelogUrl: string,
  limit: number = MAX_BODY_LENGTH,
): string {
  if (body.length <= limit) {
    return body;
  }

  const footer = `\n\n---\n\nThese notes are cut at GitHub's length limit. Read the full release in the [changelog](${changelogUrl}).`;
  const room = limit - footer.length;
  const cut = body.lastIndexOf("\n", room);

  return `${body.slice(0, cut > 0 ? cut : room).trimEnd()}${footer}`;
}

function packageDirectory(root: string, name: string): string | undefined {
  const parent = join(root, "packages");

  return readdirSync(parent)
    .map((entry) => join(parent, entry))
    .find((dir) => {
      const manifest = join(dir, "package.json");

      // SAFETY: a workspace manifest is a JSON object; only `name` is read.
      return (
        existsSync(manifest) &&
        (JSON.parse(readFileSync(manifest, "utf-8")) as { name?: string })
          .name === name
      );
    });
}

function gh(args: readonly string[]): string {
  return execFileSync("gh", [...args], { encoding: "utf-8" });
}

function main(): void {
  // SAFETY: the value is the changesets action's `published-packages` output.
  const published = JSON.parse(
    argv[2] ?? env.PUBLISHED_PACKAGES ?? "[]",
  ) as PublishedPackage[];

  const repository = env.GITHUB_REPOSITORY;
  const root = cwd();

  if (repository === undefined) {
    console.error("github-releases: GITHUB_REPOSITORY is not set.");
    exit(1);
  }

  for (const { name, version } of published) {
    const directory = packageDirectory(root, name);

    if (directory === undefined) {
      console.warn(`github-releases: no workspace package named ${name}.`);
      continue;
    }

    const tag = `${name}@${version}`;
    const changelogPath = join(directory, "CHANGELOG.md");
    const changelogUrl = `https://github.com/${repository}/blob/${tag}/${directory.slice(root.length + 1)}/CHANGELOG.md`;

    const section = existsSync(changelogPath)
      ? changelogSection(readFileSync(changelogPath, "utf-8"), version)
      : "";

    const notes = truncateNotes(
      section === "" ? `Release ${version}.` : section,
      changelogUrl,
    );

    const file = join(mkdtempSync(join(tmpdir(), "release-")), "notes.md");

    writeFileSync(file, notes);

    let exists = true;

    try {
      gh(["release", "view", tag]);
    } catch {
      exists = false;
    }

    gh(
      exists
        ? ["release", "edit", tag, "--notes-file", file]
        : [
            "release",
            "create",
            tag,
            "--verify-tag",
            "--title",
            tag,
            "--notes-file",
            file,
          ],
    );
    console.log(`github-releases: ${exists ? "updated" : "created"} ${tag}.`);
  }
}

if (argv[1]?.endsWith("github-releases.ts")) {
  main();
}
