const SHELL_SAFE = /^[\w@%+=:,./-]+$/;

/** `value` as one shell word: unchanged when it is safe, else in single quotes. */
export function shellQuote(value: string): string {
  return SHELL_SAFE.test(value) ? value : `'${value.replaceAll("'", `'\\''`)}'`;
}

/** `words` as one command line a person or an agent can paste. */
export const commandLine = (words: readonly string[]): string =>
  words.map(shellQuote).join(" ");

/**
 * A command line as its words, undoing `shellQuote`: single quotes group a
 * word, and `'\\''` is a quote inside one.
 */
export function splitCommandLine(line: string): string[] {
  const words: string[] = [];
  let word = "";
  let quoted = false;
  let started = false;

  for (let index = 0; index < line.length; index += 1) {
    const char = line[index] ?? "";

    if (quoted) {
      if (char === "'") {
        quoted = false;
      } else {
        word += char;
      }
    } else if (char === "'") {
      quoted = true;
      started = true;
    } else if (char === "\\" && line[index + 1] === "'") {
      word += "'";
      index += 1;
    } else if (/\s/.test(char)) {
      if (started || word !== "") {
        words.push(word);
        word = "";
        started = false;
      }
    } else {
      word += char;
    }
  }

  if (started || word !== "") {
    words.push(word);
  }

  return words;
}
