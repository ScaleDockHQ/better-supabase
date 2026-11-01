import type { FindingInput, Rule } from "./rules.ts";

const PROMISE_ALL = /\bPromise\.all\s*\(\s*\[/g;

/**
 * Parts of the array literal that starts after `open`, split at top-level
 * commas.
 */
function arrayEntries(text: string, open: number): string[] | undefined {
  const entries: string[] = [];
  let depth = 0;
  let start = open;

  for (let index = open; index < text.length; index += 1) {
    const char = text.charAt(index);

    if (char === "(" || char === "[" || char === "{") {
      depth += 1;
    } else if (char === ")" || char === "}") {
      depth -= 1;
    } else if (char === "]") {
      if (depth === 0) {
        entries.push(text.slice(start, index));

        return entries;
      }

      depth -= 1;
    } else if (char === "," && depth === 0) {
      entries.push(text.slice(start, index));
      start = index + 1;
    }
  }

  return undefined;
}

/** An entry that awaits the database: a repository, a block client or a call. */
const DATABASE_READ =
  /\b(?:db|ctx\.db|bsb\.db\(\)|blocks\.\w+)\b[\s\S]*?\(|\$rpc\s*\(/;

/** Reads in one `Promise.all` before the hint (BS609). */
const MIN_READS = 3;

function parallelReads(context: Parameters<Rule["check"]>[0]): FindingInput[] {
  const findings: FindingInput[] = [];

  for (const file of context.sources) {
    for (const match of file.text.matchAll(PROMISE_ALL)) {
      const open = match.index + match[0].length;
      const entries = arrayEntries(file.text, open);

      const reads = entries?.filter((entry) => DATABASE_READ.test(entry));

      if (reads === undefined || reads.length < MIN_READS) {
        continue;
      }

      const line = file.text.slice(0, match.index).split("\n").length;

      findings.push({
        message: `${file.path} awaits ${reads.length} database reads in one Promise.all. They run in parallel, but each is its own request. Load them in one call with a read set: defineReadSet(db, "name", { ... }) and db.$many(readSet, params) (or bsb.bootstrap for a page's first load).`,
        target: `${file.path}:${match.index}`,
        location: { file: file.path, line },
      });
    }
  }

  return findings;
}

export const ROUND_TRIP_RULES: readonly Rule[] = [
  {
    code: "BS609",
    severity: "info",
    title: "Three or more database reads in one Promise.all",
    description:
      "A page that loads its data with several parallel reads makes one request each. A read set compiles the same reads into one stable database function, so the page waits on one round trip and RLS applies as for any read.",
    check: parallelReads,
  },
];
