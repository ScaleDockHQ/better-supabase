/** One lexical piece of an access SQL template. */
export type TemplateToken =
  | { readonly kind: "word"; readonly text: string; readonly quoted: boolean }
  | { readonly kind: "string"; readonly text: string }
  | { readonly kind: "placeholder"; readonly text: string }
  | { readonly kind: "punct"; readonly text: string }
  | { readonly kind: "space"; readonly text: string }
  | { readonly kind: "comment"; readonly text: string }
  | { readonly kind: "dollar"; readonly text: string }
  | { readonly kind: "error"; readonly text: string };

const WORD_START = /[A-Za-z_]/;
const WORD_PART = /[\w$]/;

function readString(source: string, start: number, escapes: boolean): number {
  let index = start + 1;

  while (index < source.length) {
    const char = source[index];

    if (escapes && char === "\\") {
      index += 2;
      continue;
    }

    if (char === "'") {
      if (source[index + 1] === "'") {
        index += 2;
        continue;
      }

      return index + 1;
    }

    index += 1;
  }

  return -1;
}

function readQuoted(source: string, start: number): number {
  let index = start + 1;

  while (index < source.length) {
    if (source[index] === '"') {
      if (source[index + 1] === '"') {
        index += 2;
        continue;
      }

      return index + 1;
    }

    index += 1;
  }

  return -1;
}

/**
 * Splits a template into tokens. Strings, quoted identifiers and comments are
 * read whole, so a `;` or `(` inside them is never mistaken for code. A
 * dollar-quote tag (`$$`, `$tag$`), an unterminated string, quoted identifier
 * or block comment, and a stray `{` come back as `dollar` and `error` tokens
 * for the caller to refuse.
 */
export function tokenizeTemplate(source: string): TemplateToken[] {
  const tokens: TemplateToken[] = [];
  let index = 0;

  const push = (token: TemplateToken, end: number): void => {
    tokens.push(token);
    index = end;
  };

  while (index < source.length) {
    const char = source[index]!;
    const rest = source.slice(index);

    if (/\s/.test(char)) {
      const end = index + (/^\s+/.exec(rest)?.[0].length ?? 1);
      push({ kind: "space", text: source.slice(index, end) }, end);
    } else if (rest.startsWith("--")) {
      const newline = source.indexOf("\n", index);
      const end = newline === -1 ? source.length : newline;
      push({ kind: "comment", text: source.slice(index, end) }, end);
    } else if (rest.startsWith("/*")) {
      const close = source.indexOf("*/", index + 2);
      const end = close === -1 ? source.length : close + 2;
      push(
        {
          kind: close === -1 ? "error" : "comment",
          text: source.slice(index, end),
        },
        end,
      );
    } else if (char === "'" || /^[eE]'/.test(rest)) {
      const escapes = char !== "'";
      const open = escapes ? index + 1 : index;
      const end = readString(source, open, escapes);
      const stop = end === -1 ? source.length : end;
      push(
        {
          kind: end === -1 ? "error" : "string",
          text: source.slice(index, stop),
        },
        stop,
      );
    } else if (char === '"') {
      const end = readQuoted(source, index);
      const stop = end === -1 ? source.length : end;
      push(
        end === -1
          ? { kind: "error", text: source.slice(index, stop) }
          : {
              kind: "word",
              text: source.slice(index + 1, stop - 1),
              quoted: true,
            },
        stop,
      );
    } else if (char === "$") {
      const tag = /^\$(?:[A-Za-z_]\w*)?\$/.exec(rest)?.[0];

      if (tag === undefined) {
        push({ kind: "punct", text: char }, index + 1);
      } else {
        push({ kind: "dollar", text: tag }, index + tag.length);
      }
    } else if (char === "{") {
      const match = /^\{(\w+)\}/.exec(rest);

      if (match === null) {
        push({ kind: "error", text: char }, index + 1);
      } else {
        push({ kind: "placeholder", text: match[1]! }, index + match[0].length);
      }
    } else if (WORD_START.test(char)) {
      let end = index + 1;

      while (end < source.length && WORD_PART.test(source[end]!)) {
        end += 1;
      }

      push(
        { kind: "word", text: source.slice(index, end), quoted: false },
        end,
      );
    } else {
      push({ kind: "punct", text: char }, index + 1);
    }
  }

  return tokens;
}
