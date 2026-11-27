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

/** Names the read set after the file: `src/app/tasks/page.tsx` is `tasks_page`. */
function readSetName(path: string): string {
  const parts = path
    .replace(/\.[a-z]+$/, "")
    .split("/")
    .filter(
      (part) => part !== "" && !/^(?:src|app|lib|\(.*\)|\[.*\])$/.test(part),
    );

  const name = parts
    .slice(-2)
    .join("_")
    .replaceAll(/[^a-zA-Z0-9]+/g, "_")
    .toLowerCase();

  return name === "" ? "page_reads" : name;
}

/**
 * The `defineReadSet` and `db.$many` calls that replace `entries`: the same
 * reads on the builder `s`, keyed by the table each reads.
 */
export function readSetFor(path: string, entries: readonly string[]): string {
  const used = new Map<string, number>();

  const keyed = entries.map((entry, index) => {
    const source = entry
      .trim()
      .replace(/^await\s+/, "")
      .replace(/^(?:ctx\.db|bsb\.db\(\)|db)\b/, "s");

    const table = /^s\.(\w+)\./.exec(source)?.[1] ?? `read${String(index + 1)}`;
    const seen = used.get(table) ?? 0;
    used.set(table, seen + 1);

    return { key: seen === 0 ? table : `${table}${String(seen + 1)}`, source };
  });

  const name = readSetName(path);

  return [
    `  export const ${name.replaceAll(/_(\w)/g, (_, char: string) => char.toUpperCase())} = defineReadSet(betterSupabase, "${name}", {}, (s) => ({`,
    ...keyed.map(({ key, source }) => `    ${key}: ${source},`),
    "  }));",
    `  const { ${keyed.map(({ key }) => key).join(", ")} } = await db.$many(${name.replaceAll(/_(\w)/g, (_, char: string) => char.toUpperCase())}, {}).orThrow();`,
    "  // A value from the page (an id, a filter) becomes a placeholder in the first {} and p.<name> in the reads.",
  ].join("\n");
}

function parallelReads(context: Parameters<Rule["check"]>[0]): FindingInput[] {
  const findings: FindingInput[] = [];

  for (const file of context.sources) {
    const model = sourceModel(file.text);

    const found: {
      start: number;
      callee: string;
      reads: number;
      entries: readonly string[];
    }[] = [];

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
          entries: reads,
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
        message: `${file.path} awaits ${wave.reads} database reads in one Promise.all. They run in parallel, but each is its own request. Load them in one call with a read set, with read_batch (what bsb.record(type).get uses for a record page), or with bsb.bootstrap for a page's first load. The read set that replaces them:\n${readSetFor(file.path, wave.entries)}`,
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
      "A page that loads its data with several parallel reads makes one request each. A read set compiles the same reads into one stable database function, so the page waits on one round trip and RLS applies as for any read. A record page can send the same bindings through read_batch, which bsb.record(type).get calls.",
    check: parallelReads,
  },
];
