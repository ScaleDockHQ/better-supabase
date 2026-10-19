const SHELL_SAFE = /^[\w@%+=:,./-]+$/;

/** `value` as one shell word: unchanged when it is safe, else in single quotes. */
export function shellQuote(value: string): string {
  return SHELL_SAFE.test(value) ? value : `'${value.replaceAll("'", `'\\''`)}'`;
}

/** `words` as one command line a person or an agent can paste. */
export const commandLine = (words: readonly string[]): string =>
  words.map(shellQuote).join(" ");
