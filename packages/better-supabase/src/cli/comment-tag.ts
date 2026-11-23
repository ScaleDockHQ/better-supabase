import { factsOf } from "./schema-reader/index.ts";
import { primeSchemaFacts } from "./sql-facts.ts";

/** A comment string with its quotes doubled, as a SQL literal. */
const literal = (text: string): string => `'${text.replaceAll("'", "''")}'`;

/**
 * `text` with the tag `line` (`@bsb fields a, b`) in the comment on a table or
 * column. The comment is found by the reader's facts, so a commented-out
 * statement or a string that looks like one never matches. An existing comment
 * gets the line, whichever quoting it used; a missing one gets `create`.
 *
 * @param text - The SQL file.
 * @param root - The project root, for the Postgres version.
 * @param target - What the comment is on.
 * @param name - `schema.table`, plus `.column` for a column.
 * @param line - The tag line.
 * @param create - The statement that adds a comment when there is none.
 * @returns The new text.
 */
export async function withCommentTag(
  text: string,
  root: string,
  target: "column" | "table",
  name: string,
  line: string,
  create: string,
): Promise<string> {
  await primeSchemaFacts([{ path: "codemod.sql", text }], root, {
    lenient: true,
  });

  const found = factsOf(text).comments.find(
    (comment) => comment.target === target && comment.name === name,
  );

  if (found?.span === undefined) {
    return `${text.replace(/\n*$/u, "\n")}\n${create}\n`;
  }

  const [start, end] = found.span;
  const body = found.text;

  // One `@bsb` starts the tag block and `;` separates the tags in it, so a
  // second `@bsb` would read as a word of the tag before it.
  const next = /(^|\s)@bsb(?:\s|$)/u.test(body)
    ? `${body.trimEnd().replace(/;$/u, "")}; ${line.replace(/^@bsb\s+/u, "")}`
    : `${body === "" ? "" : `${body}\n`}${line}`;

  return `${text.slice(0, start)}${literal(next)}${text.slice(end)}`;
}
