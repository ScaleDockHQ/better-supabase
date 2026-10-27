const IDENTIFIER = String.raw`(?:"(?:[^"]|"")+"|[a-z_][a-z0-9_$]*)`;

const STATEMENT_START = String.raw`(?:^|;|\bthen\b|\belse\b|\bbegin\b|\bloop\b)\s*`;

const ASSIGNS = new RegExp(
  String.raw`${STATEMENT_START}new\s*\.\s*(${IDENTIFIER})\s*:?=|new\s*\.\s*(${IDENTIFIER})\s*:=`,
  "gi",
);

const SELECT_INTO = new RegExp(
  String.raw`\binto\s+(?:strict\s+)?(new(?:\s*\.\s*${IDENTIFIER})?(?:\s*,\s*new(?:\s*\.\s*${IDENTIFIER})?)*)`,
  "gi",
);

const WHOLE_ROW = new RegExp(String.raw`${STATEMENT_START}new\s*:?=`, "i");

/**
 * The columns a PL/pgSQL trigger function assigns on `new`, from `new.col :=
 * …`, `new.col = …` as a statement and `select … into new.col`. `undefined`
 * means unknown: another language, or the body replaces the whole row (`new :=
 * …`, `select … into new`).
 */
export function triggerFills(
  language: string,
  source: string,
): readonly string[] | undefined {
  if (language !== "plpgsql") {
    return undefined;
  }

  const body = stripLiterals(source);

  if (WHOLE_ROW.test(body)) {
    return undefined;
  }

  const filled = new Set<string>();

  for (const match of body.matchAll(ASSIGNS)) {
    filled.add(unquote(match[1] ?? match[2] ?? ""));
  }

  for (const match of body.matchAll(SELECT_INTO)) {
    for (const target of (match[1] ?? "").split(",")) {
      const [, column] = target.split(".");

      if (column === undefined) {
        return undefined;
      }

      filled.add(unquote(column.trim()));
    }
  }

  return [...filled].toSorted();
}

/** Drops comments and string literals so their text never counts. */
function stripLiterals(source: string): string {
  return source
    .replaceAll(/\$([a-z_]*)\$[\s\S]*?\$\1\$/giu, " ")
    .replaceAll(/'(?:[^']|'')*'/gu, " ")
    .replaceAll(/--[^\n]*/gu, " ")
    .replaceAll(/\/\*[\s\S]*?\*\//gu, " ");
}

function unquote(identifier: string): string {
  return identifier.startsWith('"')
    ? identifier.slice(1, -1).replaceAll('""', '"')
    : identifier.toLowerCase();
}
