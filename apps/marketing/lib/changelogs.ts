import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";

import { type ChangelogRelease, parseChangelog } from "./changelog";

// Next.js runs builds from the app directory, locally and on Vercel.
const changelogPath = join(
  process.cwd(),
  "../../packages/better-supabase/CHANGELOG.md",
);

export function loadChangelog(): ChangelogRelease[] {
  if (!existsSync(changelogPath)) {
    return [];
  }
  return parseChangelog(readFileSync(changelogPath, "utf8"));
}
