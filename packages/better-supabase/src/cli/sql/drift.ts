/** Why a generated block SQL file differs from a fresh render. */
export type DriftKind = "subjects" | "search" | "other";

const SUBJECT_LINE =
  /_subject_readable|\bsubject_type\b|^\s*when '[^']+' then\b/;

const SEARCH_LINE = /search/i;

function counts(text: string): Map<string, number> {
  const result = new Map<string, number>();

  for (const line of text.split("\n")) {
    result.set(line, (result.get(line) ?? 0) + 1);
  }

  return result;
}

/** The lines `from` has more often than `other` does. */
function surplus(from: string, other: string): string[] {
  const seen = counts(other);
  const lines: string[] = [];

  for (const line of from.split("\n")) {
    const left = seen.get(line) ?? 0;

    if (left > 0) {
      seen.set(line, left - 1);
    } else if (line.trim() !== "") {
      lines.push(line);
    }
  }

  return lines;
}

/**
 * Sorts a difference between the file on disk and a fresh render. A file that
 * differs only in `*_subject_readable` cases changed because a block was added
 * or removed, which `upgrade` should write. A difference in search lines (a
 * missing trigger) is drift worth a look, and any other line is a hand edit or
 * an older generator.
 */
export function classifyDrift(
  current: string | undefined,
  expected: string,
): DriftKind {
  const changed = [
    ...surplus(expected, current ?? ""),
    ...surplus(current ?? "", expected),
  ];

  if (current === undefined || changed.length === 0) {
    return "other";
  }

  if (
    changed.some((line) => !SUBJECT_LINE.test(line) && !SEARCH_LINE.test(line))
  ) {
    return "other";
  }

  return changed.some(
    (line) => SEARCH_LINE.test(line) && !SUBJECT_LINE.test(line),
  )
    ? "search"
    : "subjects";
}

/** One line per kind that names how many files fall in it. */
export function driftSummary(
  kinds: Readonly<Record<DriftKind, readonly string[]>>,
): string | undefined {
  const parts = [
    kinds.subjects.length === 0
      ? undefined
      : `${kinds.subjects.length} differ only in subject cases (a block was added or removed; \`upgrade\` writes them)`,
    kinds.search.length === 0
      ? undefined
      : `${kinds.search.length} differ in search triggers (check the \`search\` config)`,
    kinds.other.length === 0
      ? undefined
      : `${kinds.other.length} differ in other lines`,
  ].filter((part) => part !== undefined);

  return parts.length === 0 ? undefined : `Drift: ${parts.join("; ")}.`;
}
