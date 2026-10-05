/** A table registered with `better_supabase.audit(...)` in a SQL file. */
export interface AuditedTable {
  /** `schema.table`, unquoted; an unqualified name is in `public`. */
  readonly target: string;
  readonly ignore: readonly string[];
  readonly redact: readonly string[];
}

/** `text` with comments blanked out, string and identifier quotes kept. */
function withoutComments(text: string): string {
  let out = "";
  let index = 0;
  while (index < text.length) {
    const char = text[index]!;
    const next = text[index + 1];
    if (char === "'" || char === '"') {
      const end = closing(text, index, char);
      out += text.slice(index, end);
      index = end;
    } else if (char === "-" && next === "-") {
      const end = text.indexOf("\n", index);
      index = end === -1 ? text.length : end;
    } else if (char === "/" && next === "*") {
      const end = text.indexOf("*/", index + 2);
      index = end === -1 ? text.length : end + 2;
      out += " ";
    } else {
      out += char;
      index += 1;
    }
  }
  return out;
}

/** The index after the quote that closes the one at `start`; doubled quotes escape. */
function closing(text: string, start: number, quote: string): number {
  let index = start + 1;
  while (index < text.length) {
    if (text[index] === quote) {
      if (text[index + 1] !== quote) return index + 1;
      index += 2;
    } else {
      index += 1;
    }
  }
  return text.length;
}

/** The arguments between the parenthesis at `open` and its match, split on top-level commas. */
function callArgs(text: string, open: number): string[] | undefined {
  const args: string[] = [];
  let depth = 0;
  let start = open + 1;
  let index = open;
  while (index < text.length) {
    const char = text[index]!;
    if (char === "'" || char === '"') {
      index = closing(text, index, char);
      continue;
    }
    if (char === "(" || char === "[") depth += 1;
    else if (char === ")" || char === "]") {
      depth -= 1;
      if (depth === 0) {
        args.push(text.slice(start, index).trim());
        return args.filter((arg) => arg !== "");
      }
    } else if (char === "," && depth === 1) {
      args.push(text.slice(start, index).trim());
      start = index + 1;
    }
    index += 1;
  }
  return undefined;
}

const NAMED = /^([a-z_]+)\s*(?:=>|:=)\s*([\s\S]+)$/i;

/** The value of a string literal, with any `::type` cast; undefined for other expressions. */
function literal(expression: string): string | undefined {
  const match = /^[eE]?'((?:[^']|'')*)'(?:\s*::\s*[\w.[\]\s]+)?$/.exec(
    expression.trim(),
  );
  return match ? match[1]!.replaceAll("''", "'") : undefined;
}

/** A `'{a,b}'` literal or `array['a', 'b']`, as names; undefined when it is neither. */
function nameList(expression: string): string[] | undefined {
  const text = literal(expression);
  if (text !== undefined) {
    const inner = /^\{(.*)\}$/s.exec(text.trim());
    if (!inner) return undefined;
    return inner[1]!
      .split(",")
      .map((name) => name.trim().replace(/^"(.*)"$/, "$1"))
      .filter((name) => name !== "");
  }
  const array = /^array\s*\[([\s\S]*?)\](?:\s*::\s*[\w[\]\s]+)?$/i.exec(
    expression.trim(),
  );
  if (!array) return undefined;
  const items = array[1]!.trim() === "" ? [] : array[1]!.split(",");
  const names = items.map((item) => literal(item));
  return names.every((name) => name !== undefined) ? names : undefined;
}

/** `schema.table`, unquoted, from a regclass literal such as `'public."Customers"'`. */
function qualifiedName(target: string): string {
  const parts = target.match(/"(?:[^"]|"")*"|[^.]+/g) ?? [];
  const names = parts.map((part) =>
    part.startsWith('"')
      ? part.slice(1, -1).replaceAll('""', '"')
      : part.trim().toLowerCase(),
  );
  return names.length === 1 ? `public.${names[0]!}` : names.join(".");
}

const POSITIONS = ["target", "ignore", "replace_trigger", "redact"] as const;

/** One `audit(...)` or `unaudit(...)` call's target and lists, or undefined when they are not literals. */
function registration(args: readonly string[]): AuditedTable | undefined {
  const named = new Map<string, string>();
  args.forEach((arg, index) => {
    const match = NAMED.exec(arg);
    if (match) named.set(match[1]!.toLowerCase(), match[2]!);
    else if (index < POSITIONS.length) named.set(POSITIONS[index]!, arg);
  });
  const target = literal(named.get("target") ?? "");
  if (target === undefined) return undefined;
  const list = (name: string): string[] | undefined => {
    const value = named.get(name);
    return value === undefined ? [] : nameList(value);
  };
  const ignore = list("ignore");
  const redact = list("redact");
  if (!ignore || !redact) return undefined;
  return { target: qualifiedName(target), ignore, redact };
}

const CALL = /\bbetter_supabase\s*\.\s*(un)?audit\s*\(/gi;

/**
 * The tables `files` register with `better_supabase.audit(...)`, in file
 * order: a later call for the same table replaces the earlier one, and
 * `unaudit(...)` removes it. Calls with non-literal arguments are skipped.
 */
export function auditRegistrations(
  files: readonly { readonly text: string }[],
): AuditedTable[] {
  const tables = new Map<string, AuditedTable>();
  for (const file of files) {
    const text = withoutComments(file.text);
    for (const match of text.matchAll(CALL)) {
      const args = callArgs(text, match.index + match[0].length - 1);
      if (!args) continue;
      if (match[1] !== undefined) {
        const target = literal(args[0] ?? "");
        if (target !== undefined) tables.delete(qualifiedName(target));
        continue;
      }
      const entry = registration(args);
      if (entry) tables.set(entry.target, entry);
    }
  }
  return [...tables.values()].sort((a, b) =>
    a.target < b.target ? -1 : a.target > b.target ? 1 : 0,
  );
}
