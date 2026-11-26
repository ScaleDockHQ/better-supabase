/** One `KEY=value` assignment of a dotenv file and the line its key is on. */
export interface DotenvEntry {
  readonly key: string;
  readonly value: string;
  readonly line: number;
}

const KEY_START = /[A-Za-z_]/;
const KEY_PART = /[A-Za-z0-9_]/;
const QUOTES = new Set(['"', "'", "`"]);

const isBlank = (char: string | undefined): boolean =>
  char === " " || char === "\t" || char === "\r";

/**
 * The assignments of a dotenv text, read token by token: a `#` comment (whole
 * line or after the value) is skipped, `export` is dropped, and a quoted value
 * may run over several lines, so a line inside it is never read as a key.
 *
 * @param text - The file contents.
 * @returns The entries in file order.
 */
export function getDotenv(text: string): readonly DotenvEntry[] {
  const entries: DotenvEntry[] = [];
  let at = 0;
  let line = 1;

  const skipLine = (): void => {
    while (at < text.length && text[at] !== "\n") {
      at += 1;
    }
  };

  const skipBlanks = (): void => {
    while (isBlank(text[at])) {
      at += 1;
    }
  };

  const wordAt = (): string => {
    const start = at;

    if (KEY_START.test(text[at] ?? "")) {
      at += 1;

      while (KEY_PART.test(text[at] ?? "")) {
        at += 1;
      }
    }

    return text.slice(start, at);
  };

  /**
   * The value after `=`: quoted up to its closing quote, else to the end of
   * line.
   */
  const valueAt = (): string => {
    const quote = text[at];

    if (quote !== undefined && QUOTES.has(quote)) {
      let close = at + 1;

      while (
        close < text.length &&
        (text[close] !== quote || text[close - 1] === "\\")
      ) {
        close += 1;
      }

      if (close < text.length) {
        const value = text.slice(at + 1, close);

        line += value.split("\n").length - 1;
        at = close + 1;
        skipLine();

        return value;
      }
    }

    const start = at;

    skipLine();

    return text
      .slice(start, at)
      .replace(/(?:^|\s)#.*$/, "")
      .trim();
  };

  while (at < text.length) {
    skipBlanks();

    const char = text[at];

    if (char === "\n") {
      at += 1;
      line += 1;
      continue;
    }

    if (char === "#") {
      skipLine();
      continue;
    }

    let key = wordAt();

    if (key === "export" && isBlank(text[at])) {
      skipBlanks();
      key = wordAt();
    }

    skipBlanks();

    if (key === "" || text[at] !== "=") {
      skipLine();
      continue;
    }

    at += 1;
    skipBlanks();

    const first = line;

    entries.push({ key, value: valueAt(), line: first });
  }

  return entries;
}
