/** One SQL statement and the line (1-based) it starts on. */
export interface SqlStatement {
  /** The statement without its comments and the closing semicolon. */
  readonly text: string;
  readonly line: number;
}

const DOLLAR_TAG = /\$(?:[A-Za-z_][A-Za-z0-9_]*)?\$/uy;

/**
 * `text` split into statements at the semicolons outside quotes, dollar quotes
 * and comments. Comments are dropped; strings and dollar-quoted bodies stay as
 * they are.
 */
export function splitStatements(text: string): SqlStatement[] {
  const statements: SqlStatement[] = [];
  let current = "";
  let start = 1;
  let line = 1;
  let index = 0;

  const push = (): void => {
    const trimmed = current.trim();

    if (trimmed !== "") {
      statements.push({ text: trimmed, line: start });
    }

    current = "";
  };

  const advance = (until: number): void => {
    for (let at = index; at < until; at += 1) {
      if (text[at] === "\n") {
        line += 1;
      }
    }

    index = until;
  };

  while (index < text.length) {
    if (current.trim() === "") {
      start = line;
    }

    const char = text[index];

    if (text.startsWith("--", index)) {
      const end = text.indexOf("\n", index);

      advance(end === -1 ? text.length : end);
      continue;
    }

    if (text.startsWith("/*", index)) {
      let depth = 0;
      let at = index;

      while (at < text.length) {
        if (text.startsWith("/*", at)) {
          depth += 1;
          at += 2;
        } else if (text.startsWith("*/", at)) {
          depth -= 1;
          at += 2;

          if (depth === 0) {
            break;
          }
        } else {
          at += 1;
        }
      }

      current += " ";
      advance(at);
      continue;
    }

    if (char === "'" || char === '"') {
      let at = index + 1;

      while (at < text.length) {
        if (text[at] === char) {
          if (text[at + 1] === char) {
            at += 2;
            continue;
          }

          break;
        }

        at += 1;
      }

      current += text.slice(index, at + 1);
      advance(Math.min(at + 1, text.length));
      continue;
    }

    DOLLAR_TAG.lastIndex = index;

    const tag = char === "$" ? DOLLAR_TAG.exec(text)?.[0] : undefined;

    if (tag !== undefined) {
      const close = text.indexOf(tag, index + tag.length);
      const end = close === -1 ? text.length : close + tag.length;

      current += text.slice(index, end);
      advance(end);
      continue;
    }

    if (char === ";") {
      push();
      advance(index + 1);
      continue;
    }

    current += char;
    advance(index + 1);
  }

  push();

  return statements;
}
