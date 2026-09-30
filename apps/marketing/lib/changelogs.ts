import { cacheLife } from "next/cache";
import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";

import { type ChangelogRelease, parseChangelog } from "./changelog";

// Next.js runs builds from the app directory, locally and on Vercel.
const changelogPath = join(
  process.cwd(),
  "../../packages/better-supabase/CHANGELOG.md",
);

/** Read once per build: the file only changes with a release, which redeploys. */
export async function loadChangelog(): Promise<ChangelogRelease[]> {
  "use cache";
  cacheLife("max");
  if (!existsSync(changelogPath)) {
    return [];
  }
  return parseChangelog(readFileSync(changelogPath, "utf8"));
}
