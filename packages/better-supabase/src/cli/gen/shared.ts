export const q = (value: string): string => JSON.stringify(value);

/** A property key: bare when it is a valid identifier, quoted otherwise. */
export function prop(name: string): string {
  return /^[A-Za-z_$][\w$]*$/.test(name) ? name : q(name);
}

export function nullable(type: string, isNullable: boolean): string {
  return isNullable ? `${type} | null` : type;
}

/** `T[]`, parenthesized when `T` is a union or other compound type. */
export function arrayOf(type: string): string {
  return /^[\w.$]+$/.test(type) ? `${type}[]` : `(${type})[]`;
}

export function indent(lines: readonly string[], depth: number): string[] {
  const pad = "  ".repeat(depth);
  return lines
    .flatMap((line) => line.split("\n"))
    .map((line) => (line === "" ? line : pad + line));
}

/** `name: {` + indented children + `};`, or an inline empty type. */
export function block(
  name: string,
  children: readonly string[],
  empty = "{ [_ in never]: never }",
): string[] {
  if (children.length === 0) return [`${name}: ${empty};`];
  return [`${name}: {`, ...indent(children, 1), "};"];
}

export function sameColumns(
  left: readonly string[],
  right: readonly string[],
): boolean {
  return (
    left.length === right.length &&
    left.every((column) => right.includes(column))
  );
}

export function singular(name: string): string {
  if (name.endsWith("ies")) return `${name.slice(0, -3)}y`;
  if (name.endsWith("sses")) return name.slice(0, -2);
  if (name.endsWith("s") && !name.endsWith("ss")) return name.slice(0, -1);
  return name;
}

export function pascal(name: string): string {
  return name
    .replaceAll(/(^|[_-]+)([a-z0-9])/g, (_, __, char: string) =>
      char.toUpperCase(),
    )
    .replace(/^[a-z]/, (char) => char.toUpperCase());
}

export function isJsonUdt(udt: string): boolean {
  return udt === "json" || udt === "jsonb";
}

const CHECK_ANY =
  /^CHECK \(\(\(?"?(\w+)"?\)?(?:::\w+)? = ANY \(\(?ARRAY\[(.+)\]\)?(?:::\w+\[\])?\)\)\)$/;
const CHECK_OR = /^CHECK \(\((.+)\)\)$/;
const OR_TERM = /^\(?"?(\w+)"?\)?(?:::\w+)? = '((?:[^']|'')*)'(?:::\w+)?\)?$/;
const LITERAL = /'((?:[^']|'')*)'(?:::[\w ]+)?/g;

/**
 * Extracts `column in ('a', 'b')` CHECK constraints, which Postgres stores as
 * `CHECK ((col = ANY (ARRAY['a'::text, 'b'::text])))` or an OR chain.
 */
export function parseCheckUnion(
  definition: string,
): { column: string; values: string[] } | undefined {
  const any = CHECK_ANY.exec(definition);
  if (any?.[1] && any[2]) {
    const values = [...any[2].matchAll(LITERAL)].map((match) =>
      (match[1] ?? "").replaceAll("''", "'"),
    );
    return values.length > 0 ? { column: any[1], values } : undefined;
  }
  const chain = CHECK_OR.exec(definition);
  if (chain?.[1]) {
    const terms = chain[1].split(/\) OR \(|\s+OR\s+/);
    let column: string | undefined;
    const values: string[] = [];
    for (const term of terms) {
      const match = OR_TERM.exec(term.trim());
      if (!match?.[1]) return undefined;
      if (column && column !== match[1]) return undefined;
      column = match[1];
      values.push((match[2] ?? "").replaceAll("''", "'"));
    }
    return column && values.length > 1 ? { column, values } : undefined;
  }
  return undefined;
}
