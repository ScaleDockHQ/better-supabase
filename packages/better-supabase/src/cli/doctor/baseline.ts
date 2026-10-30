import type { DoctorContext, Finding } from "./rules.ts";

import { byCodePoint } from "../compare.ts";
import { LIVE_CODES } from "./live-source.ts";
import { EXTRAS_RULES } from "./metadata.ts";
import { DOCS_URL } from "./rules.ts";

/** One accepted finding in `tooling.doctor.baseline`. */
export interface BaselineEntry {
  readonly code: string;
  /** The finding's `target`, or its title when it has none. */
  readonly target: string;
  readonly reason: string;
}

export interface BaselineResult {
  /** The findings the baseline doesn't list, then one error per stale entry. */
  readonly findings: readonly Finding[];
  /** How many findings the baseline accepted. */
  readonly accepted: number;
  readonly stale: readonly BaselineEntry[];
}

const targetOf = (finding: Pick<Finding, "target" | "title">): string =>
  finding.target ?? finding.title;

const keyOf = (code: string, target: string): string =>
  `${code}\u0000${target}`;

const text = (value: unknown): value is string => typeof value === "string";

/**
 * Parses a baseline file, `[{ code, target, reason }]`. Throws a `TypeError`
 * naming the first entry that isn't one.
 */
export function parseBaseline(contents: string, path: string): BaselineEntry[] {
  let value: unknown;

  try {
    value = JSON.parse(contents);
  } catch (cause) {
    throw new TypeError(`${path} is not JSON: ${String(cause)}`, { cause });
  }

  if (!Array.isArray(value)) {
    throw new TypeError(
      `${path} must be an array of { code, target, reason } entries.`,
    );
  }

  return value.map((entry: unknown, index): BaselineEntry => {
    if (
      typeof entry !== "object" ||
      entry === null ||
      !("code" in entry) ||
      !("target" in entry) ||
      !text(entry.code) ||
      !text(entry.target)
    ) {
      throw new TypeError(
        `${path} entry ${String(index)} needs a string code and target.`,
      );
    }

    const reason = "reason" in entry && text(entry.reason) ? entry.reason : "";

    return { code: entry.code, target: entry.target, reason };
  });
}

/**
 * Whether this run could have reported `code`: the check ran, and a check that
 * reads the database or the advisors had them, and the schema didn't come from
 * a metadata document that lacks what the check reads.
 */
function judged(
  code: string,
  ran: ReadonlySet<string>,
  context: Pick<DoctorContext, "database" | "advisors" | "snapshot">,
): boolean {
  if (!ran.has(code)) {
    return false;
  }

  if (context.snapshot.extras.fromMetadata && EXTRAS_RULES.has(code)) {
    return false;
  }

  if (!LIVE_CODES.has(code)) {
    return true;
  }

  const { database, advisors } = context;

  return (
    database !== undefined &&
    !("skipped" in database) &&
    !(advisors !== undefined && "skipped" in advisors)
  );
}

/**
 * Leaves out the findings the baseline lists and adds an error for each entry
 * no finding matched, among the checks this run could judge.
 */
export function applyBaseline(
  findings: readonly Finding[],
  entries: readonly BaselineEntry[],
  ran: ReadonlySet<string>,
  context: Pick<DoctorContext, "database" | "advisors" | "snapshot">,
  path: string,
): BaselineResult {
  const listed = new Set(
    entries.map((entry) => keyOf(entry.code, entry.target)),
  );

  const matched = new Set<string>();
  const kept: Finding[] = [];

  for (const finding of findings) {
    const key = keyOf(finding.code, targetOf(finding));

    if (listed.has(key)) {
      matched.add(key);
    } else {
      kept.push(finding);
    }
  }

  const stale = entries.filter(
    (entry) =>
      !matched.has(keyOf(entry.code, entry.target)) &&
      judged(entry.code, ran, context),
  );

  return {
    findings: [
      ...kept,
      ...stale.map((entry): Finding => ({
        code: entry.code,
        severity: "error",
        title: "A baseline entry matches no finding",
        message: `${path} accepts ${entry.code} at ${entry.target}, which doctor no longer reports. Remove the entry, or run doctor --update-baseline.`,
        target: entry.target,
        help: `${DOCS_URL}#baseline`,
      })),
    ],
    accepted: findings.length - kept.length,
    stale,
  };
}

/**
 * The baseline that accepts every error and warning of this run. An entry keeps
 * its reason, a new entry takes the reason of another entry with its code, and
 * entries for checks this run couldn't judge stay.
 */
export function updatedBaseline(
  findings: readonly Finding[],
  entries: readonly BaselineEntry[],
  ran: ReadonlySet<string>,
  context: Pick<DoctorContext, "database" | "advisors" | "snapshot">,
): BaselineEntry[] {
  const reasons = new Map(
    entries.map((entry) => [keyOf(entry.code, entry.target), entry.reason]),
  );

  const byCode = new Map<string, string>();

  for (const entry of entries) {
    if (entry.reason !== "" && !byCode.has(entry.code)) {
      byCode.set(entry.code, entry.reason);
    }
  }

  const next = new Map<string, BaselineEntry>();

  for (const finding of findings) {
    if (finding.severity === "info") {
      continue;
    }

    const target = targetOf(finding);
    const key = keyOf(finding.code, target);

    next.set(key, {
      code: finding.code,
      target,
      reason: reasons.get(key) ?? byCode.get(finding.code) ?? "",
    });
  }

  for (const entry of entries) {
    const key = keyOf(entry.code, entry.target);

    if (!next.has(key) && !judged(entry.code, ran, context)) {
      next.set(key, entry);
    }
  }

  return [...next.values()].toSorted(
    (a, b) => byCodePoint(a.code, b.code) || byCodePoint(a.target, b.target),
  );
}
