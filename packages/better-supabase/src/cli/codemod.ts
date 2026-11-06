/**
 * Source rewrites for `better-supabase codemod`. A small scanner masks strings,
 * template literals and comments, so renames only touch code; there is no
 * parser dependency, so each transform is a narrow, mechanical rename.
 */

import type { CliCallMigration } from "./codemod-calls.ts";
import type { ConfigEdit } from "./sql/config-edit.ts";

import { codeRanges } from "./code-ranges.ts";
import {
  CLI_CALL_FILE,
  cliCallHints,
  rewriteCliCalls,
  SHELL_FILE,
} from "./codemod-calls.ts";
import { DESIGN_FILE_NAME, designFileResult } from "./codemod-design-file.ts";
import { namingCodemod } from "./codemod-naming.ts";
import { reportReadMany } from "./codemod-read-many.ts";
import { linesMatching } from "./codemod-review.ts";
import { renameSubpaths } from "./codemod-subpaths.ts";

/**
 * `better-supabase.config.*`, the files a codemod's `configFile` edit applies
 * to.
 */
export const CONFIG_FILE: RegExp =
  /(?:^|[\\/])better-supabase\.config\.(?:ts|mts|cts|js|mjs|cjs|json)$/;

export interface Codemod {
  readonly name: string;
  readonly description: string;
  /**
   * Exported names, renamed in imports from `better-supabase` and where the
   * import is used.
   */
  readonly imports?: Readonly<Record<string, string>>;
  /** `better-supabase/<subpath>` import specifiers, renamed. */
  readonly subpaths?: Readonly<Record<string, string>>;
  /**
   * Exported names renamed only in imports from one subpath (`plugins/rules`),
   * before `subpaths` renames it, for names another subpath also exports.
   */
  readonly subpathImports?: Readonly<
    Record<string, Readonly<Record<string, string>>>
  >;
  /**
   * Local bindings, renamed where a file declares or imports them and imports
   * from `better-supabase` or a `supabase` module.
   */
  readonly bindings?: Readonly<Record<string, string>>;
  /** Member names, renamed after a `.` anywhere in code. */
  readonly members?: readonly MemberRename[];
  /** JSX props on one component. */
  readonly props?: readonly PropRename[];
  /** Keys of the options object a named call takes, at its top level. */
  readonly options?: readonly OptionRename[];
  /** Option keys added where a default changed, to keep the old behavior. */
  readonly pins?: readonly OptionPin[];
  /**
   * Whole string literals, such as event types, renamed in strings, templates
   * and comments.
   */
  readonly strings?: Readonly<Record<string, string>>;
  /** A rewrite of every source file, after the renames above. */
  readonly source?: (text: string) => {
    readonly text: string;
    readonly review: readonly ReviewLine[];
  };
  /** Changes too ambiguous to rewrite; matching lines are listed for review. */
  readonly review?: readonly ReviewHint[];
  /**
   * SQL for a hand migration the codemod writes next to the app's own, or
   * `undefined` when nothing needs renaming.
   */
  readonly migration?: () => string | undefined;
  /** A rewrite of `better-supabase.config.*`; a refusal is listed for review. */
  readonly configFile?: (source: string, json: boolean) => CodemodConfigEdit;
  /** A rewrite of `supabase/schemas/*.sql`; without it, SQL files are skipped. */
  readonly sqlFile?: (source: string) => CodemodResult;
  /** A rewrite of a design file; a refusal is listed for review. */
  readonly designFile?: (source: string) => CodemodConfigEdit;
  /**
   * Renamed CLI calls, rewritten in `package.json` and workflows and listed in
   * other shell files.
   */
  readonly cliCalls?: CliCallMigration;
  /**
   * CLI calls left as they are, listed for review in scripts, workflows and
   * shell files.
   */
  readonly cliReview?: readonly ReviewHint[];
}

export interface ReviewLine {
  readonly line: number;
  readonly message: string;
}

/** A config rewrite, with the lines it changed that need a look. */
export type CodemodConfigEdit =
  | ConfigEdit
  | {
      readonly ok: true;
      readonly text: string;
      readonly review: readonly ReviewLine[];
    };

export interface MemberRename {
  readonly from: string;
  readonly to: string;
  /** Skip a member followed by `(`, when the old name is still a method. */
  readonly notCalled?: boolean;
}

export interface PropRename {
  readonly component: string;
  readonly from: string;
  readonly to: string;
}

export interface OptionRename {
  readonly call: string;
  readonly from: string;
  readonly to: string;
}

export interface OptionPin {
  readonly call: string;
  /** 0-based position of the options object among the call's arguments. */
  readonly argument: number;
  readonly key: string;
  /** The code written as the key's value. */
  readonly value: string;
  /** Keys whose presence means the call needs no pin. */
  readonly unless?: readonly string[];
  /**
   * Pins only in files this matches; other calls without the key are listed for
   * review.
   */
  readonly when: RegExp;
  readonly message: string;
}

export interface ReviewHint {
  readonly pattern: RegExp;
  readonly message: string;
}

export const CODEMODS: Readonly<Record<string, Codemod>> = {
  naming: namingCodemod(),
  "read-many": {
    name: "read-many",
    description: "List Promise.all groups of reads that db.$many can load",
    source: reportReadMany,
  },
};

const SUPABASE_IMPORT =
  /\bfrom\s*["'](?:better-supabase(?:\/[\w./-]*)?|[^"']*supabase[^"']*)["']/;

/**
 * Renames bindings a file declares, destructures or imports, in files that
 * import from `better-supabase` or a `supabase` module.
 */
function renameBindings(
  text: string,
  bindings: Readonly<Record<string, string>>,
): string {
  const ranges = codeRanges(text);

  if (
    codeMatches(text, new RegExp(SUPABASE_IMPORT, "g"), ranges).length === 0
  ) {
    return text;
  }

  const renames = new Map(
    Object.entries(bindings).filter(([from]) => {
      const name = escapeRegExp(from);

      const declared = new RegExp(
        `\\b(?:const|let|var|function)\\s+${name}(?![\\w$])|[{,]\\s*(?:type\\s+)?${name}\\s*(?:[,}]|as\\b)|\\(\\s*${name}\\s*[:,)]`,
        "g",
      );

      return codeMatches(text, declared, ranges).length > 0;
    }),
  );

  return renameIdentifiers(text, renames);
}

interface Edit {
  readonly start: number;
  readonly end: number;
  readonly text: string;
}

function applyEdits(text: string, edits: readonly Edit[]): string {
  let out = "";
  let cursor = 0;

  for (const edit of edits.toSorted((a, b) => a.start - b.start)) {
    if (edit.start < cursor) {
      continue;
    }

    out += text.slice(cursor, edit.start) + edit.text;
    cursor = edit.end;
  }

  return out + text.slice(cursor);
}

const escapeRegExp = (value: string): string =>
  value.replaceAll(/[.*+?^${}()|[\]\\]/g, "\\$&");

function inCode(ranges: readonly [number, number][], index: number): boolean {
  let low = 0;
  let high = ranges.length - 1;

  while (low <= high) {
    const middle = Math.floor((low + high) / 2);
    const [start, end] = ranges[middle]!;

    if (index < start) {
      high = middle - 1;
    } else if (index >= end) {
      low = middle + 1;
    } else {
      return true;
    }
  }

  return false;
}

const OPENING = "({[";
const CLOSING = ")}]";

/** Matches of `pattern` that start in code. */
function codeMatches(
  text: string,
  pattern: RegExp,
  ranges: readonly [number, number][],
): RegExpExecArray[] {
  return [...text.matchAll(pattern)].filter((match) =>
    inCode(ranges, match.index),
  );
}

const IMPORT =
  /\b(import|export)\s+(type\s+)?\{([^}]*)\}\s*from\s*(["'])better-supabase(?:\/([\w./-]*))?\4/g;

/** Renames imported names, from every subpath or only from `subpath`. */
function renameImports(
  text: string,
  renames: Readonly<Record<string, string>>,
  subpath?: string,
): { text: string; locals: Set<string> } {
  const ranges = codeRanges(text);
  const locals = new Set<string>();
  const edits: Edit[] = [];

  for (const match of codeMatches(text, IMPORT, ranges)) {
    if (subpath !== undefined && match[5] !== subpath) {
      continue;
    }

    const list = match[3]!;
    const listStart = match.index + match[0].indexOf("{") + 1;

    const renamed = list.replaceAll(
      /(\btype\s+)?([\w$]+)(\s+as\s+[\w$]+)?/g,
      (spec, type: string | undefined, name: string, alias?: string) => {
        const to = renames[name];

        if (to === undefined) {
          return spec;
        }

        if (alias === undefined && match[1] === "import") {
          locals.add(name);
        }

        return `${type ?? ""}${to}${alias ?? ""}`;
      },
    );

    if (renamed !== list) {
      edits.push({
        start: listStart,
        end: listStart + list.length,
        text: renamed,
      });
    }
  }

  return { text: applyEdits(text, edits), locals };
}

function renameIdentifiers(
  text: string,
  renames: ReadonlyMap<string, string>,
): string {
  if (renames.size === 0) {
    return text;
  }

  const ranges = codeRanges(text);
  const names = [...renames.keys()].map(escapeRegExp).join("|");
  const pattern = new RegExp(`(?<![\\w$.])(?:${names})(?![\\w$])`, "g");

  return applyEdits(
    text,
    codeMatches(text, pattern, ranges).map((match) => ({
      start: match.index,
      end: match.index + match[0].length,
      text: renames.get(match[0])!,
    })),
  );
}

function renameStrings(
  text: string,
  strings: Readonly<Record<string, string>>,
): string {
  const names = Object.keys(strings).map(escapeRegExp).join("|");

  if (names === "") {
    return text;
  }

  const ranges = codeRanges(text);
  const pattern = new RegExp(`(["'\`])(${names})\\1`, "g");

  return applyEdits(
    text,
    [...text.matchAll(pattern)]
      .filter((match) => !inCode(ranges, match.index + 1))
      .map((match) => ({
        start: match.index + 1,
        end: match.index + 1 + match[2]!.length,
        text: strings[match[2]!]!,
      })),
  );
}

function renameMembers(text: string, members: readonly MemberRename[]): string {
  const ranges = codeRanges(text);

  const edits = members.flatMap((member) =>
    codeMatches(
      text,
      new RegExp(
        `\\.${escapeRegExp(member.from)}(?![\\w$])${member.notCalled === true ? "(?!\\s*\\()" : ""}`,
        "g",
      ),
      ranges,
    ).map((match) => ({
      start: match.index,
      end: match.index + match[0].length,
      text: `.${member.to}`,
    })),
  );

  return applyEdits(text, edits);
}

function renameProps(text: string, props: readonly PropRename[]): string {
  const ranges = codeRanges(text);
  const edits: Edit[] = [];

  for (const prop of props) {
    const tag = new RegExp(`<${escapeRegExp(prop.component)}(?![\\w$.])`, "g");

    for (const match of codeMatches(text, tag, ranges)) {
      let depth = 0;

      for (
        let index = match.index + match[0].length;
        index < text.length;
        index += 1
      ) {
        if (!inCode(ranges, index)) {
          continue;
        }

        const char = text[index]!;

        if (char === "{") {
          depth += 1;
        } else if (char === "}") {
          depth -= 1;
        } else if (char === ">" && depth === 0) {
          break;
        }

        if (
          depth === 0 &&
          /\s/.test(text[index - 1] ?? "") &&
          text.startsWith(`${prop.from}=`, index)
        ) {
          edits.push({
            start: index,
            end: index + prop.from.length,
            text: prop.to,
          });
        }
      }
    }
  }

  return applyEdits(text, edits);
}

/** The index after the bracket that closes the one at `open`, in code only. */
function closing(
  text: string,
  open: number,
  ranges: readonly [number, number][],
): number {
  let depth = 0;

  for (let index = open; index < text.length; index += 1) {
    if (!inCode(ranges, index)) {
      continue;
    }

    const char = text[index]!;

    if (OPENING.includes(char)) {
      depth += 1;
    } else if (CLOSING.includes(char)) {
      depth -= 1;

      if (depth === 0) {
        return index + 1;
      }
    }
  }

  return text.length;
}

/**
 * Calls `visit(index, depth)` for each code character from `open` to its
 * closing bracket.
 */
function walkBrackets(
  text: string,
  open: number,
  ranges: readonly [number, number][],
  visit: (index: number, depth: number, char: string) => void,
): void {
  const end = closing(text, open, ranges);
  let depth = 0;

  for (let index = open; index < end; index += 1) {
    if (!inCode(ranges, index)) {
      continue;
    }

    const char = text[index]!;

    if (OPENING.includes(char)) {
      depth += 1;
    } else if (CLOSING.includes(char)) {
      depth -= 1;
    }

    visit(index, depth, char);
  }
}

/** Where `key` is a top-level key of the object literal at `open`. */
function topLevelKeys(
  text: string,
  open: number,
  key: string,
  ranges: readonly [number, number][],
): { readonly index: number; readonly shorthand: boolean }[] {
  const keys: { index: number; shorthand: boolean }[] = [];
  let previous = "";
  walkBrackets(text, open, ranges, (index, depth, char) => {
    if (
      depth === 1 &&
      (previous === "{" || previous === ",") &&
      text.startsWith(key, index) &&
      !/[\w$]/.test(text[index + key.length] ?? "")
    ) {
      const after = /^\s*(\S)/.exec(text.slice(index + key.length))?.[1];

      if (after === ":") {
        keys.push({ index, shorthand: false });
      } else if (after === "," || after === "}") {
        keys.push({ index, shorthand: true });
      }
    }

    if (depth === 1 && !/\s/.test(char)) {
      previous = char;
    }
  });

  return keys;
}

function renameOptions(text: string, options: readonly OptionRename[]): string {
  const ranges = codeRanges(text);
  const edits: Edit[] = [];

  for (const option of options) {
    const call = new RegExp(
      `(?<![\\w$.])${escapeRegExp(option.call)}\\s*(?:<[^>]*>)?\\s*\\(`,
      "g",
    );

    for (const match of codeMatches(text, call, ranges)) {
      const objects: number[] = [];
      walkBrackets(
        text,
        match.index + match[0].length - 1,
        ranges,
        (index, depth, char) => {
          if (depth === 2 && char === "{") {
            objects.push(index);
          }
        },
      );

      for (const object of objects) {
        for (const { index, shorthand } of topLevelKeys(
          text,
          object,
          option.from,
          ranges,
        )) {
          edits.push({
            start: index,
            end: index + option.from.length,
            text: shorthand ? `${option.to}: ${option.from}` : option.to,
          });
        }
      }
    }
  }

  return applyEdits(text, edits);
}

interface PinTarget {
  /** Where the call starts, for the review line. */
  readonly call: number;
  /** The edit that adds the key, or `undefined` when only a review fits. */
  readonly edit: Edit | undefined;
}

/** The arguments of the call whose `(` is at `open`: start and end of each. */
function callArguments(
  text: string,
  open: number,
  ranges: readonly [number, number][],
): { start: number; end: number }[] {
  const args: { start: number; end: number }[] = [];
  let start = open + 1;
  const end = closing(text, open, ranges) - 1;

  walkBrackets(text, open, ranges, (index, depth, char) => {
    if (depth === 1 && char === ",") {
      args.push({ start, end: index });
      start = index + 1;
    }
  });

  if (text.slice(start, end).trim() !== "") {
    args.push({ start, end });
  }

  return args;
}

/**
 * Calls of `pin.call` whose options object lacks `pin.key`, with the insertion
 * when one is safe.
 */
function pinTargets(text: string, pin: OptionPin): PinTarget[] {
  const ranges = codeRanges(text);

  const call = new RegExp(
    `(?<![\\w$.])${escapeRegExp(pin.call)}\\s*(?:<[^>]*>)?\\s*\\(`,
    "g",
  );

  const targets: PinTarget[] = [];
  const entry = `${pin.key}: ${pin.value}`;

  for (const match of codeMatches(text, call, ranges)) {
    const open = match.index + match[0].length - 1;
    const args = callArguments(text, open, ranges);
    const arg = args[pin.argument];

    if (arg === undefined) {
      if (args.length !== pin.argument) {
        targets.push({ call: match.index, edit: undefined });
        continue;
      }

      const last = args.at(-1);
      const at = last === undefined ? open + 1 : last.end;
      const trailing = text[at] === ",";

      targets.push({
        call: match.index,
        edit: trailing
          ? { start: at + 1, end: at + 1, text: ` { ${entry} }` }
          : { start: at, end: at, text: `, { ${entry} }` },
      });
      continue;
    }

    const offset = text.slice(arg.start, arg.end).search(/\S/);
    const object = arg.start + offset;

    if (text[object] !== "{") {
      targets.push({ call: match.index, edit: undefined });
      continue;
    }

    const keys = [pin.key, ...(pin.unless ?? [])];

    if (
      keys.some((key) => topLevelKeys(text, object, key, ranges).length > 0)
    ) {
      continue;
    }

    const spreads: number[] = [];
    walkBrackets(text, object, ranges, (index, depth) => {
      if (depth === 1 && text.startsWith("...", index)) {
        spreads.push(index);
      }
    });

    if (spreads.length > 0) {
      targets.push({ call: match.index, edit: undefined });
      continue;
    }

    const body = text.slice(object + 1, closing(text, object, ranges) - 1);
    const first = /^[ \t]*\n([ \t]*)\S/.exec(body);

    targets.push({
      call: match.index,
      edit:
        body.trim() === ""
          ? {
              start: object,
              end: object + body.length + 2,
              text: `{ ${entry} }`,
            }
          : first
            ? {
                start: object + 1,
                end: object + 1,
                text: `\n${first[1]!}${entry},`,
              }
            : { start: object + 1, end: object + 1, text: ` ${entry},` },
    });
  }

  return targets;
}

function pinOptions(
  text: string,
  pins: readonly OptionPin[],
): { text: string; review: { line: number; message: string }[] } {
  let out = text;

  for (const pin of pins) {
    if (pin.when.test(out)) {
      out = applyEdits(
        out,
        pinTargets(out, pin).flatMap((target) =>
          target.edit === undefined ? [] : [target.edit],
        ),
      );
    }
  }

  const review = pins.flatMap((pin) =>
    pinTargets(out, pin).map((target) => ({
      line: out.slice(0, target.call).split("\n").length,
      message: pin.message,
    })),
  );

  return { text: out, review };
}

export interface CodemodResult {
  readonly text: string;
  /** 1-based lines that need a manual change, with the reason. */
  readonly review: readonly ReviewLine[];
}

/** Applies one codemod to a source file. */
export function applyCodemod(
  codemod: Codemod,
  source: string,
  file?: string,
): CodemodResult {
  if (
    file !== undefined &&
    (CLI_CALL_FILE.test(file) || SHELL_FILE.test(file))
  ) {
    const hints = linesMatching(source, codemod.cliReview ?? []);

    if (!codemod.cliCalls) {
      return { text: source, review: hints };
    }

    return CLI_CALL_FILE.test(file)
      ? { text: rewriteCliCalls(source, codemod.cliCalls), review: hints }
      : {
          text: source,
          review: [...cliCallHints(source, codemod.cliCalls), ...hints],
        };
  }

  if (file?.endsWith(".sql") === true) {
    return codemod.sqlFile?.(source) ?? { text: source, review: [] };
  }

  if (file !== undefined && DESIGN_FILE_NAME.test(file)) {
    return designFileResult(source, codemod.designFile);
  }

  let text = source;
  const refused: { line: number; message: string }[] = [];

  if (codemod.configFile && file !== undefined && CONFIG_FILE.test(file)) {
    const json = file.endsWith(".json");
    const edit = codemod.configFile(source, json);

    if (edit.ok) {
      text = edit.text;
      refused.push(...("review" in edit ? edit.review : []));
    } else {
      refused.push({
        line: 1,
        message: `The config wasn't rewritten: ${edit.reason}`,
      });
    }

    if (json) {
      return { text, review: refused };
    }
  }

  for (const [subpath, renames] of Object.entries(
    codemod.subpathImports ?? {},
  )) {
    const imported = renameImports(text, renames, subpath);
    text = renameIdentifiers(
      imported.text,
      new Map([...imported.locals].map((name) => [name, renames[name]!])),
    );
  }

  if (codemod.subpaths) {
    text = renameSubpaths(text, codemod.subpaths);
  }

  if (codemod.imports) {
    const imported = renameImports(text, codemod.imports);
    text = renameIdentifiers(
      imported.text,
      new Map(
        [...imported.locals].map((name) => [name, codemod.imports![name]!]),
      ),
    );
  }

  if (codemod.bindings) {
    text = renameBindings(text, codemod.bindings);
  }

  if (codemod.members) {
    text = renameMembers(text, codemod.members);
  }

  if (codemod.props) {
    text = renameProps(text, codemod.props);
  }

  if (codemod.options) {
    text = renameOptions(text, codemod.options);
  }

  if (codemod.strings) {
    text = renameStrings(text, codemod.strings);
  }

  if (codemod.source) {
    const rewritten = codemod.source(text);
    text = rewritten.text;
    refused.push(...rewritten.review);
  }

  if (codemod.pins) {
    const pinned = pinOptions(text, codemod.pins);
    text = pinned.text;
    refused.push(...pinned.review);
  }

  return {
    text,
    review: [...refused, ...linesMatching(text, codemod.review ?? [])],
  };
}
