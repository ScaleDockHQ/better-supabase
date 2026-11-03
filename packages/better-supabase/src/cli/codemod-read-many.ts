import type { ReviewLine } from "./codemod.ts";

import { arrayEntries, PROMISE_ALL } from "./doctor/round-trips.ts";

const REPOSITORY_READ =
  /^\s*(?:await\s+)?((?:ctx\.)?db|bsb\.db\(\))\.(\w+)\.(list|page|get|count|aggregate)\(/;

/**
 * Lists each `Promise.all` of repository reads on one `db`. `db.$many` takes
 * specs and resolves to one `Result` of a tuple, so the call sites change
 * shape; the codemod names the group and leaves the text.
 */
export function reportReadMany(text: string): {
  readonly text: string;
  readonly review: readonly ReviewLine[];
} {
  const review: ReviewLine[] = [];

  for (const match of text.matchAll(PROMISE_ALL)) {
    const entries = arrayEntries(text, match.index + match[0].length);

    if (entries === undefined || entries.length < 2) {
      continue;
    }

    const reads = entries.map((entry) => REPOSITORY_READ.exec(entry));
    const first = reads[0];

    if (!first) {
      continue;
    }

    const line = text.slice(0, match.index).split("\n").length;

    if (reads.every((read) => read !== null && read[1] === first[1])) {
      review.push({
        line,
        message: `${entries.length} reads on ${first[1]} run as separate requests. Build them with betterSupabase.spec and run db.$many([...]), or name them in a read set. $many resolves to one Result holding the tuple, so unwrap it once instead of per read.`,
      });
    } else {
      review.push({
        line,
        message:
          "This Promise.all mixes repository reads with other calls, so it can't move to db.$many as is. Put the repository reads in a read set and keep the rest beside it.",
      });
    }
  }

  return { text, review };
}
