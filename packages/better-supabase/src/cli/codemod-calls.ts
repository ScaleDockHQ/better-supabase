/**
 * CLI calls in scripts, for codemods that rename commands or flags. Calls in
 * `package.json` and GitHub workflows are rewritten; calls in other shell
 * files are listed for review, since their quoting and variables vary more.
 */

/** Rewrites the words after the bin, or returns `undefined` when nothing moved. */
export type CliCallMigration = (
  argv: readonly string[],
) => readonly string[] | undefined;

/** Files whose CLI calls a codemod rewrites. */
export const CLI_CALL_FILE: RegExp =
  /(?:^|[\\/])(?:package\.json|\.github[\\/]workflows[\\/][^\\/]+\.ya?ml)$/;

/** Other files that run shell commands; their CLI calls are listed for review. */
export const SHELL_FILE: RegExp =
  /(?:^|[\\/])(?:[^\\/]+\.(?:sh|bash|zsh|ya?ml)|Makefile|justfile|Dockerfile)$/;

/** The bin, with an optional `@version`, followed by its arguments. */
const BIN = /(?<![\w.@-])(?:better-supabase|bsb)(?:@[\w.^~-]+)?(?=[ \t])/g;

/** Where a call's arguments end: a line break, a shell operator, a closing quote or a comment. */
const CALL_END = /\r?\n|&&|\|\||[;|)`]|\\?"|\s#/;

/** `pnpm --filter better-supabase <script>` names the package, not the bin. */
const PACKAGE_FILTER = /(?:--filter|-F)[= ]$/;

interface CliCall {
  /** Offset of the first argument. */
  readonly start: number;
  readonly end: number;
  readonly bin: string;
  readonly to: readonly string[];
}

function cliCalls(text: string, migrate: CliCallMigration): CliCall[] {
  const calls: CliCall[] = [];

  for (const match of text.matchAll(BIN)) {
    if (PACKAGE_FILTER.test(text.slice(0, match.index))) {
      continue;
    }

    const start = match.index + match[0].length;
    const tail = text.slice(start);
    const end = start + (CALL_END.exec(tail)?.index ?? tail.length);
    const words = text.slice(start, end).trim().split(/\s+/u);
    const to = words[0] === "" ? undefined : migrate(words);

    if (to) {
      calls.push({ start, end, bin: match[0], to });
    }
  }

  return calls;
}

/** `text` with every moved CLI call spelled the new way. */
export function rewriteCliCalls(
  text: string,
  migrate: CliCallMigration,
): string {
  let out = "";
  let cursor = 0;

  for (const call of cliCalls(text, migrate)) {
    const original = text.slice(call.start, call.end);
    const trailing = /\s*$/u.exec(original)?.[0] ?? "";
    out += `${text.slice(cursor, call.start)} ${call.to.join(" ")}${trailing}`;
    cursor = call.end;
  }

  return out + text.slice(cursor);
}

/** One review line per moved CLI call, with the new spelling. */
export function cliCallHints(
  text: string,
  migrate: CliCallMigration,
): { line: number; message: string }[] {
  return cliCalls(text, migrate).map((call) => ({
    line: text.slice(0, call.start).split("\n").length,
    message: `This call uses a renamed command or flag: run \`${call.bin} ${call.to.join(" ")}\``,
  }));
}
