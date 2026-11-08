import { splitStatements } from "../../sql/index.ts";

/**
 * One column a projection view selects: the base column and the name it has in
 * the view.
 */
export interface ProjectedColumn {
  readonly source: string;
  readonly name: string;
}

/**
 * An app view that selects named columns of one block table, with an optional
 * `where`. Clients read the view, so PowerSync streams the same columns and
 * rows from the table under it.
 */
export interface Projection {
  /** The view, as `schema.view`. */
  readonly view: string;
  readonly columns: readonly ProjectedColumn[];
  /** The view's `where` condition, over the base table's columns. */
  readonly where?: string;
}

const IDENT = String.raw`(?:"(?:[^"]|"")+"|[A-Za-z_][\w$]*)`;
const NAMED = String.raw`(${IDENT}(?:\s*\.\s*${IDENT})?)`;

const VIEW = new RegExp(
  String.raw`^create\s+(?:or\s+replace\s+)?view\s+${NAMED}\s*(?:with\s*\([^)]*\)\s*)?as\s+select\s+([\s\S]+?)\s+from\s+${NAMED}(?:\s+(?:as\s+)?(?!where\b)(${IDENT}))?(?:\s+where\s+([\s\S]+))?$`,
  "i",
);

const ITEM = new RegExp(
  String.raw`^(?:${IDENT}\s*\.\s*)?(${IDENT})(?:\s+as\s+(${IDENT}))?$`,
  "i",
);

const COMPLEX = /\b(?:join|group\s+by|union|order\s+by|limit|distinct)\b/i;

const unquote = (part: string): string =>
  part.startsWith('"')
    ? part.slice(1, -1).replaceAll('""', '"')
    : part.toLowerCase();

const qualified = (name: string): string => {
  const parts = name.split(/\s*\.\s*/).map((part) => unquote(part.trim()));

  return parts.length === 1 ? `public.${parts[0]!}` : parts.join(".");
};

function topLevel(text: string): string[] {
  const parts: string[] = [];
  let depth = 0;
  let current = "";

  for (const char of text) {
    if (char === "(") {
      depth += 1;
    } else if (char === ")") {
      depth -= 1;
    }

    if (char === "," && depth === 0) {
      parts.push(current);
      current = "";
    } else {
      current += char;
    }
  }

  return [...parts, current].map((part) => part.trim());
}

/**
 * The projections the app's schema files declare, by the table each one reads.
 * A view with a join, an aggregate or an expression in its select list is not a
 * projection: it has no one-to-one stream.
 */
export function projectionsOf(
  texts: readonly { readonly text: string }[],
): ReadonlyMap<string, Projection> {
  const found = new Map<string, Projection>();

  for (const { text } of texts) {
    for (const statement of splitStatements(text)) {
      const match = VIEW.exec(statement.text.replaceAll(/\s+/g, " "));

      if (match === null || COMPLEX.test(statement.text)) {
        continue;
      }

      const columns: ProjectedColumn[] = [];

      for (const item of topLevel(match[2]!)) {
        const parsed = ITEM.exec(item);

        if (parsed === null) {
          columns.length = 0;
          break;
        }

        const source = unquote(parsed[1]!);

        columns.push({
          source,
          name: parsed[2] === undefined ? source : unquote(parsed[2]),
        });
      }

      const table = qualified(match[3]!);

      if (columns.length > 0 && !found.has(table)) {
        found.set(table, {
          view: qualified(match[1]!),
          columns,
          ...(match[5] === undefined ? {} : { where: match[5] }),
        });
      }
    }
  }

  return found;
}
