import type { NamingRename } from "./codemod-naming.ts";

interface ReviewLine {
  readonly line: number;
  readonly message: string;
}

const IDENTIFIER_START = /[A-Za-z_$]/;
const IDENTIFIER_PART = /[A-Za-z0-9_$]/;

/** The key a `from` path ends in and its parent path, for a same-parent rename. */
function parts(path: string): {
  readonly parent: string;
  readonly key: string;
} {
  const at = path.lastIndexOf(".");

  return at === -1
    ? { parent: "", key: path }
    : { parent: path.slice(0, at), key: path.slice(at + 1) };
}

/**
 * Renames the config keys in `rows` (kind `configKey`) in the text of a file
 * that calls `defineConfig`. A scanner follows the nesting of object literals,
 * skipping strings and comments, so `gen: { output }` becomes `gen: { file }`
 * and `blocks.tasks.output` stays. A row whose `to` has another parent (a key
 * that moved) is not rewritten; it is reported for the author to move.
 */
export function renameConfigKeys(
  text: string,
  rows: readonly NamingRename[],
): { readonly text: string; readonly review: readonly ReviewLine[] } {
  const wanted = rows.filter((row) => row.kind === "configKey");

  if (wanted.length === 0 || !text.includes("defineConfig(")) {
    return { text, review: [] };
  }

  const review: ReviewLine[] = [];
  const stack: string[] = [];
  let pending = "";
  let last = "";
  const start = text.indexOf("defineConfig(");
  let out = text.slice(0, start);
  let line = out.split("\n").length;
  let index = start;

  const pathOf = (): string =>
    stack
      .filter((name) => name !== "" && !name.startsWith("$"))
      .slice(1)
      .map((name) => (/^\d+$/.test(name) ? "*" : name))
      .join(".");

  const rowFor = (key: string): NamingRename | undefined => {
    const parent = pathOf();
    const full = parent === "" ? key : `${parent}.${key}`;

    return wanted.find((row) => row.from === full);
  };

  while (index < text.length) {
    const char = text.charAt(index);
    const next = text.charAt(index + 1);

    if (char === "\n") {
      line += 1;
    }

    if (char === "/" && next === "/") {
      const end = text.indexOf("\n", index);
      const stop = end === -1 ? text.length : end;
      out += text.slice(index, stop);
      index = stop;
      continue;
    }

    if (char === "/" && next === "*") {
      const end = text.indexOf("*/", index + 2);
      const stop = end === -1 ? text.length : end + 2;
      const comment = text.slice(index, stop);
      line += comment.split("\n").length - 1;
      out += comment;
      index = stop;
      continue;
    }

    if (char === '"' || char === "'" || char === "`") {
      let stop = index + 1;

      while (stop < text.length && text.charAt(stop) !== char) {
        stop += text.charAt(stop) === "\\" ? 2 : 1;
      }

      const literal = text.slice(index, stop + 1);
      line += literal.split("\n").length - 1;
      const after = /^\s*:/.exec(text.slice(stop + 1));

      if (after !== null && char !== "`") {
        pending = literal.slice(1, -1);
      }

      out += literal;
      last = char;
      index = stop + 1;
      continue;
    }

    if (IDENTIFIER_START.test(char)) {
      let stop = index + 1;

      while (stop < text.length && IDENTIFIER_PART.test(text.charAt(stop))) {
        stop += 1;
      }

      const word = text.slice(index, stop);
      const isKey = /^\s*:(?!:)/.test(text.slice(stop));
      const keyPosition = last === "{" || last === "," || last === "";

      if (isKey && keyPosition && stack.length > 0) {
        const row = rowFor(word);
        pending = word;

        if (row !== undefined) {
          const target = parts(row.to);

          if (target.parent === parts(row.from).parent) {
            out += target.key;
            last = "a";
            index = stop;
            continue;
          }

          review.push({
            line,
            message: `${row.from} moved to ${row.to}; move the key by hand.`,
          });
        }
      }

      out += word;
      last = "a";
      index = stop;
      continue;
    }

    if (char === "{") {
      stack.push(pending === "" ? String(stack.length) : pending);
      pending = "";
    } else if (char === "[") {
      stack.push(pending === "" ? "" : pending);
      pending = "";
    } else if (char === "}" || char === "]") {
      stack.pop();
      pending = "";
    } else if (char === ",") {
      pending = "";
    }

    out += char;

    if (!/\s/.test(char)) {
      last = char;
    }

    index += 1;
  }

  return { text: out, review };
}
