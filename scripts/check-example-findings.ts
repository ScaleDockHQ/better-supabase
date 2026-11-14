// Keeps `docs/agents/example-findings.md` and the lanes in
// `docs/agents/block-consistency-audit.md` consistent. It fails when a table
// has a stray header, a blank row or a duplicate id, when the status counts at
// the top are stale, when an unfinished row (open, partly fixed or deferred) is
// named by no lane's Findings line, when a lane is `merged` while one of
// its rows is unfinished, when an id named by a lane's Findings line or by a
// range in the Progress section has no row (a lost table), and when the row
// count falls below the committed floor in `example-findings.count`. A row stated `deferred (needs: ...)` waits on a
// maintainer step and does not block a merged lane. `--write` rewrites the status counts; without it the
// script only validates. Run with `node scripts/check-example-findings.ts`.
import { readFileSync, writeFileSync } from "node:fs";
import { argv, exit } from "node:process";

const FINDINGS = "docs/agents/example-findings.md";
const AUDIT = "docs/agents/block-consistency-audit.md";
const COUNT_FILE = "docs/agents/example-findings.count";
const START = "<!-- example-findings:counts:start -->";
const END = "<!-- example-findings:counts:end -->";

export const STATES = [
  "fixed",
  "closed",
  "measured away",
  "open",
  "partly fixed",
  "deferred",
] as const;

export type FindingState = (typeof STATES)[number];

const UNFINISHED: ReadonlySet<FindingState> = new Set([
  "open",
  "partly fixed",
  "deferred",
]);

export interface Finding {
  readonly id: string;
  readonly state: FindingState;
  /** `deferred (needs: ...)`: only a maintainer step (keys, accounts) is left. */
  readonly waiting?: boolean;
}

export interface Lane {
  readonly name: string;
  readonly status: string;
  readonly findings: readonly string[];
}

const ROW = /^\|\s*(EX-\d+)\s*\|/;
const FINDING_HEADER = /^\|\s*Id\s*\|\s*Found on\s*\|\s*Kind\s*\|\s*State\s*\|/;

const cells = (line: string): string[] =>
  line
    .split("|")
    .slice(1, -1)
    .map((cell) => cell.trim());

// A `measured (ADR n)` state counts as `measured away`.
export const stateOf = (cell: string): FindingState | undefined => {
  if (cell.startsWith("measured")) {
    return "measured away";
  }

  return STATES.find((state) => cell.startsWith(state));
};

export interface ParsedFindings {
  readonly rows: readonly Finding[];
  readonly problems: readonly string[];
}

export const parseFindings = (markdown: string): ParsedFindings => {
  const rows: Finding[] = [];
  const problems: string[] = [];
  const seen = new Set<string>();
  let inFindingTable = false;
  let lastWasRow = false;

  for (const [index, line] of markdown.split("\n").entries()) {
    const where = `${FINDINGS}:${index + 1}`;

    if (!line.startsWith("|")) {
      inFindingTable = false;
      lastWasRow = false;
      continue;
    }

    if (FINDING_HEADER.test(line)) {
      if (lastWasRow) {
        problems.push(`${where} has a header row inside a table`);
      }

      inFindingTable = true;
      lastWasRow = false;
      continue;
    }

    if (/^\|\s*Id\s*\|/.test(line)) {
      inFindingTable = false;
      lastWasRow = false;
      continue;
    }

    if (!inFindingTable) {
      continue;
    }

    if (/^\|[\s:|]*-[\s:|-]*$/.test(line)) {
      if (lastWasRow) {
        problems.push(`${where} has a separator row inside a table`);
      }

      continue;
    }

    const match = ROW.exec(line);

    if (!match?.[1]) {
      problems.push(`${where} is not a finding row: ${line.slice(0, 40)}`);
      continue;
    }

    lastWasRow = true;

    const parts = cells(line);
    const id = match[1];
    const state = stateOf(parts[3] ?? "");

    if (parts.length !== 5) {
      problems.push(`${where} (${id}) has ${parts.length} columns, not 5`);
    }

    if (!state) {
      problems.push(`${where} (${id}) has an unknown state: ${parts[3] ?? ""}`);
      continue;
    }

    if (seen.has(id)) {
      problems.push(`${where} repeats ${id}`);
    }

    seen.add(id);
    rows.push({
      id,
      state,
      waiting:
        state === "deferred" && (parts[3] ?? "").startsWith("deferred (needs:"),
    });
  }

  return { rows, problems };
};

export const countStates = (
  rows: readonly Finding[],
): Record<FindingState, number> => {
  const count = (state: FindingState): number =>
    rows.filter((row) => row.state === state).length;

  return {
    fixed: count("fixed"),
    closed: count("closed"),
    "measured away": count("measured away"),
    open: count("open"),
    "partly fixed": count("partly fixed"),
    deferred: count("deferred"),
  };
};

export const renderCounts = (rows: readonly Finding[]): string => {
  const counts = countStates(rows);
  const unfinished = rows.filter((row) => UNFINISHED.has(row.state)).length;

  return [
    `${rows.length} findings: ${counts.fixed} fixed, ${counts.closed} closed, ${counts["measured away"]} measured away,`,
    `${counts.open} open, ${counts["partly fixed"]} partly fixed and ${counts.deferred} deferred`,
    `(${unfinished} unfinished). \`pnpm check:example-findings\` keeps this line current; \`--write\` rewrites it.`,
  ].join("\n");
};

export const replaceCounts = (markdown: string, rows: readonly Finding[]) => {
  const start = markdown.indexOf(START);
  const end = markdown.indexOf(END);

  if (start === -1 || end === -1 || end < start) {
    return;
  }

  return `${markdown.slice(0, start + START.length)}\n\n${renderCounts(rows)}\n${markdown.slice(end)}`;
};

const IDS = /EX-(\d+)(?:\s+to\s+EX-(\d+))?/g;

export const expandIds = (text: string): string[] => {
  const ids: string[] = [];

  for (const match of text.matchAll(IDS)) {
    const width = match[1]?.length ?? 0;
    const from = Number(match[1]);
    const to = match[2] ? Number(match[2]) : from;

    for (let n = from; n <= to; n += 1) {
      ids.push(`EX-${String(n).padStart(width, "0")}`);
    }
  }

  return ids;
};

export const parseLanes = (markdown: string): Lane[] => {
  const lanes: Lane[] = [];
  let current: { name: string; status: string; findings: string[] } | undefined;

  for (const line of markdown.split("\n")) {
    const heading = /^### Lane (\S+)\s*$/.exec(line);

    if (heading?.[1]) {
      current = { name: heading[1], status: "", findings: [] };
      lanes.push(current);
      continue;
    }

    if (/^#{1,3} /.test(line)) {
      current = undefined;
      continue;
    }

    if (!current) {
      continue;
    }

    const status = /^- Status:\s*(.*)$/.exec(line);

    if (status?.[1] !== undefined) {
      current.status = status[1];
    }

    const findings = /^- Findings:\s*(.*)$/.exec(line);

    if (findings?.[1] !== undefined) {
      current.findings.push(...expandIds(findings[1]));
    }
  }

  return lanes;
};

export const checkLanes = (
  rows: readonly Finding[],
  lanes: readonly Lane[],
): string[] => {
  const problems: string[] = [];

  const unfinished = new Map(
    rows.filter((row) => UNFINISHED.has(row.state)).map((r) => [r.id, r.state]),
  );

  const waiting = new Set(
    rows.filter((row) => row.waiting === true).map((row) => row.id),
  );

  const named = new Set(lanes.flatMap((lane) => lane.findings));
  const orphans = [...unfinished.keys()].filter((id) => !named.has(id));

  if (orphans.length > 0) {
    problems.push(
      `${orphans.length} unfinished rows are named by no lane's Findings line: ${orphans.join(", ")}`,
    );
  }

  for (const lane of lanes) {
    if (!lane.status.startsWith("merged")) {
      continue;
    }

    // A merged lane may keep a row that waits on a maintainer step, because
    // the lane's code is done and no further PR can close it.
    const open = lane.findings.filter(
      (id) => unfinished.has(id) && !waiting.has(id),
    );

    if (open.length > 0) {
      problems.push(
        `Lane ${lane.name} is merged but ${open.join(", ")} ${open.length === 1 ? "is" : "are"} unfinished`,
      );
    }
  }

  return problems;
};

const RANGE = /EX-\d+\s+to\s+EX-\d+/g;

// Ids a lane relies on: its Findings lines and every `EX-n to EX-m` range in
// the Progress section.
export const namedIds = (
  lanes: readonly Lane[],
  tracker: string,
): ReadonlySet<string> => {
  const start = tracker.search(/^## Progress$/m);
  const rest = start === -1 ? "" : tracker.slice(start + 1);
  const end = rest.search(/^## /m);
  const progress = end === -1 ? rest : rest.slice(0, end);

  const ranges = [...progress.matchAll(RANGE)].flatMap((match) =>
    expandIds(match[0]),
  );

  return new Set([...lanes.flatMap((lane) => lane.findings), ...ranges]);
};

export const checkMissingRows = (
  rows: readonly Finding[],
  named: ReadonlySet<string>,
): string[] => {
  const have = new Set(rows.map((row) => row.id));
  const missing = [...named].filter((id) => !have.has(id));

  return missing.length === 0
    ? []
    : [
        `${missing.length} ids named by a lane have no row in ${FINDINGS} (a table may have been lost in a merge): ${missing.join(", ")}`,
      ];
};

export const checkRowFloor = (
  rows: readonly Finding[],
  floor: number,
): string[] =>
  rows.length < floor
    ? [
        `${FINDINGS} has ${rows.length} rows, below the committed floor of ${floor} in ${COUNT_FILE}; restore the lost rows`,
      ]
    : [];

export const unfinishedIds = (rows: readonly Finding[]): string[] =>
  rows.filter((row) => UNFINISHED.has(row.state)).map((row) => row.id);

const main = (): void => {
  const write = argv.includes("--write");
  const markdown = readFileSync(FINDINGS, "utf-8");
  const { rows, problems } = parseFindings(markdown);
  const found = [...problems];
  const next = replaceCounts(markdown, rows);

  if (next === undefined) {
    found.push(`${FINDINGS} has no ${START} and ${END} markers`);
  } else if (next !== markdown) {
    if (write) {
      writeFileSync(FINDINGS, next);
    } else {
      found.push(
        `The status counts in ${FINDINGS} are stale; run \`node scripts/check-example-findings.ts --write\``,
      );
    }
  }

  const tracker = readFileSync(AUDIT, "utf-8");
  const lanes = parseLanes(tracker);

  found.push(
    ...checkLanes(rows, lanes),
    ...checkMissingRows(rows, namedIds(lanes, tracker)),
  );

  const floor = Number(readFileSync(COUNT_FILE, "utf-8").trim());

  if (write && rows.length > floor) {
    writeFileSync(COUNT_FILE, `${rows.length}\n`);
  } else {
    found.push(...checkRowFloor(rows, floor));
  }

  if (found.length > 0) {
    console.error(found.join("\n"));
    exit(1);
  }

  console.log(
    `${rows.length} findings, ${unfinishedIds(rows).length} unfinished.`,
  );
};

if (process.argv[1]?.endsWith("check-example-findings.ts")) {
  main();
}
