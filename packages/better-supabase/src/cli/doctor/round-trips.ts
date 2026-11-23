import type { FindingInput, Rule } from "./rules.ts";
import type { SourceModel } from "./source-scan.ts";

import { provablyNotClient } from "./receiver-types.ts";
import { sourceModel, targetKeys } from "./source-scan.ts";

/** A `Promise.all([...])` call and the source of each entry of its array. */
export interface Wave {
  readonly start: number;
  readonly entries: readonly string[];
  /** Where each entry starts in the file, in the order of `entries`. */
  readonly entryStarts: readonly number[];
}

/** Every `Promise.all` over an array literal in `model`. */
export function waves(model: SourceModel): Wave[] {
  return model.calls.flatMap((call): Wave[] => {
    const [list] = call.node.arguments;

    if (call.path !== "Promise.all" || list?.type !== "ArrayExpression") {
      return [];
    }

    const elements = list.elements.filter((element) => element !== null);

    return [
      {
        start: call.start,
        entries: elements.map((element) =>
          model.text.slice(element.start, element.end),
        ),
        entryStarts: elements.map((element) => element.start),
      },
    ];
  });
}

/** An entry that awaits the database: a repository, a block client or a call. */
const DATABASE_READ =
  /\b(?:db|ctx\.db|bsb\.db\(\)|blocks\.\w+)\b[\s\S]*?\(|\$rpc\s*\(/;

function parallelReads(context: Parameters<Rule["check"]>[0]): FindingInput[] {
  const findings: FindingInput[] = [];

  for (const file of context.sources) {
    const model = sourceModel(file.text);
    const found: { start: number; callee: string; reads: number }[] = [];

    for (const wave of waves(model)) {
      const reads = wave.entries.filter((entry, index) => {
        const match = DATABASE_READ.exec(entry);

        if (!match) {
          return false;
        }

        // The receiver is the first name before the call: `db`, or `db` in `ctx.db`.
        const at = match[0].search(/\bdb\b/);

        return (
          at === -1 ||
          provablyNotClient(
            context.symbols,
            file.path,
            wave.entryStarts[index]! + match.index + at,
          ) !== true
        );
      });

      if (reads.length >= context.config.doctor.parallelReads) {
        found.push({
          start: wave.start,
          callee: "Promise.all",
          reads: reads.length,
        });
      }
    }

    if (found.length === 0) {
      continue;
    }

    const keys = targetKeys(file.path, model.functions, found);

    for (const wave of found) {
      const line = file.text.slice(0, wave.start).split("\n").length;

      findings.push({
        message: `${file.path} awaits ${wave.reads} database reads in one Promise.all. They run in parallel, but each is its own request. Load them in one call with a read set: defineReadSet(db, "name", { ... }) and db.$many(readSet, params) (or bsb.bootstrap for a page's first load).`,
        target: keys.get(wave.start)!,
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
