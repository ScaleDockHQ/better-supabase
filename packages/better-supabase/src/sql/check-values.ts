import { withoutComments } from "./audit-registrations.ts";
import {
  closingParen,
  NAME,
  qualified,
  splitTopLevel,
  TABLE,
  unquote,
} from "./schema-scan.ts";

/** A simple membership check: one column and the values it accepts. */
export interface CheckValues {
  readonly column: string;
  readonly values: readonly string[];
}

const CHECK = /^check\s*\(/i;

const IN = /^([\s\S]+?)\s+in\s*\(([\s\S]*)\)$/i;

const ANY =
  /^([\s\S]+?)\s*=\s*any\s*\(\s*(?:\(\s*)?array\s*\[([\s\S]*?)\]\s*\)?(?:\s*::\s*[\w." ]+(?:\[\])*)?\s*\)$/i;

const EQUALS = /^([\s\S]+?)\s*=\s*([\s\S]+)$/;

const CAST =
  /\s*::\s*[\w."]+(?:\s+[\w."]+)*(?:\s*\(\s*\d+(?:\s*,\s*\d+)?\s*\))?(?:\[\])*$/;

const LITERAL = /^'((?:[^']|'')*)'$/;

/** `text` without balanced parentheses around it. */
function unwrap(text: string): string {
  let value = text.trim();

  while (value.startsWith("(") && closingParen(value, 0) === value.length - 1) {
    value = value.slice(1, -1).trim();
  }

  return value;
}

/** `text` without a trailing `::type` cast and the parentheses around it. */
function withoutCast(text: string): string {
  let value = unwrap(text);

  while (CAST.test(value)) {
    value = unwrap(value.replace(CAST, ""));
  }

  return value;
}

function columnOf(text: string): string | undefined {
  const value = withoutCast(text);
  const match = new RegExp(`^${NAME}$`).exec(value);

  return match === null ? undefined : unquote(match[0]);
}

function literalOf(text: string): string | undefined {
  const match = LITERAL.exec(withoutCast(text));

  return match === null ? undefined : match[1]!.replaceAll("''", "'");
}

function literals(list: string): readonly string[] | undefined {
  const values = splitTopLevel(list).map(literalOf);

  return values.every((value): value is string => value !== undefined)
    ? values
    : undefined;
}

function membership(body: string): CheckValues | undefined {
  const inMatch = IN.exec(body);

  if (inMatch !== null) {
    const column = columnOf(inMatch[1]!);
    const values = literals(inMatch[2]!);

    return column === undefined || values === undefined
      ? undefined
      : { column, values };
  }

  const anyMatch = ANY.exec(body);

  if (anyMatch !== null) {
    const column = columnOf(anyMatch[1]!);
    const values = literals(anyMatch[2]!);

    return column === undefined || values === undefined
      ? undefined
      : { column, values };
  }

  const equals = EQUALS.exec(body);

  if (equals !== null) {
    const column = columnOf(equals[1]!);
    const value = literalOf(equals[2]!);

    return column === undefined || value === undefined
      ? undefined
      : { column, values: [value] };
  }

  return undefined;
}

/**
 * The column and values a `check (column in (...))` or `check (column = any
 * (array[...]))` constraint accepts, as Postgres prints it or as a schema file
 * writes it. `undefined` for a check that constrains more than one column, a
 * negation, a pattern or an expression.
 */
export function checkValues(definition: string): CheckValues | undefined {
  const text = definition.trim();
  const open = CHECK.exec(text);

  if (open === null) {
    return undefined;
  }

  const close = closingParen(text, open[0].length - 1);

  return close === text.length - 1
    ? membership(unwrap(text.slice(open[0].length, close)))
    : undefined;
}

/** A check of a `create table` in the schema files, with its table. */
export interface TableCheckValues extends CheckValues {
  /** `schema.table`, unquoted. */
  readonly table: string;
}

/**
 * The membership checks of the `create table` statements in `files`, inline on
 * a column or as a table constraint, keyed by the table. Checks in `schemas`
 * only when `schemas` is given.
 */
export function declaredCheckValues(
  files: readonly { readonly text: string }[],
  schemas?: readonly string[],
): TableCheckValues[] {
  const found: TableCheckValues[] = [];

  for (const file of files) {
    const text = withoutComments(file.text);

    for (const match of text.matchAll(TABLE)) {
      const table = qualified(match[1]!);

      if (
        schemas !== undefined &&
        !schemas.includes(table.slice(0, table.indexOf(".")))
      ) {
        continue;
      }

      const open = match.index + match[0].length - 1;
      const close = closingParen(text, open);

      if (close === -1) {
        continue;
      }

      for (const part of splitTopLevel(text.slice(open + 1, close))) {
        const definition = part.trim();

        if (/^like\b/i.test(definition)) {
          continue;
        }

        for (const check of definition.matchAll(/\bcheck\s*\(/gi)) {
          const checkOpen = check.index + check[0].length - 1;
          const checkClose = closingParen(definition, checkOpen);

          if (checkClose === -1) {
            continue;
          }

          const parsed = checkValues(
            definition.slice(check.index, checkClose + 1),
          );

          if (parsed !== undefined) {
            found.push({ table, ...parsed });
          }
        }
      }
    }
  }

  return found;
}
