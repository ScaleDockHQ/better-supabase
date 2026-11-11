/**
 * Source scanning shared by the code checks: brackets and statements in code
 * with strings and comments blanked, and line-independent finding targets.
 */
import { codeRanges } from "../code-ranges.ts";

export const OPEN: ReadonlySet<string> = new Set(["(", "[", "{"]);
export const CLOSE: ReadonlySet<string> = new Set([")", "]", "}"]);

/** `text` with strings, template literals and comments blanked, offsets kept. */
export function codeOnly(text: string): string {
  let out = "";
  let last = 0;
  const blank = (part: string): string => part.replaceAll(/[^\n]/g, " ");

  for (const [start, end] of codeRanges(text)) {
    out += blank(text.slice(last, start)) + text.slice(start, end);
    last = end;
  }

  return out + blank(text.slice(last));
}

/** The index of the bracket that closes the one at `open`. */
export function closeOf(code: string, open: number): number {
  let depth = 0;

  for (let index = open; index < code.length; index += 1) {
    const char = code.charAt(index);

    if (OPEN.has(char)) {
      depth += 1;
    } else if (CLOSE.has(char)) {
      depth -= 1;

      if (depth === 0) {
        return index;
      }
    }
  }

  return code.length;
}

/** The end of the statement or expression that starts at `from`. */
export function statementEnd(code: string, from: number): number {
  let depth = 0;

  for (let index = from; index < code.length; index += 1) {
    const char = code.charAt(index);

    if (OPEN.has(char)) {
      depth += 1;
    } else if (CLOSE.has(char)) {
      if (depth === 0) {
        return index;
      }

      depth -= 1;
    } else if ((char === ";" || char === ",") && depth === 0) {
      return index;
    }
  }

  return code.length;
}

/** A named function and its body, for target keys. */
interface NamedFunction {
  readonly name: string;
  readonly start: number;
  readonly end: number;
  /**
   * `const reorder = tenantAction(..., async () => {...})`: the call's
   * arguments, used when no function names the code.
   */
  readonly wrapped?: true;
}

const WRAPPED_CALL =
  /(?<![\w$.])([\w$]+)\s*=\s*(?:await\s+)?[\w$.]+\s*(?:<[^>()]*>)?\s*\(/g;

const FUNCTION_HEAD =
  /(?<![\w$.])(?:function\s*\*?\s*([\w$]+)\s*(?:<[^>()]*>)?\s*\(|([\w$]+)\s*(?:[:=]\s*(?:[\w$.]+\s*(?:<[^>()]*>)?\s*\(\s*)*(?:async\s+)?(?:function\b[^(]*\(|(?:<[^>()]*>)?\s*\(|[\w$]+\s*=>)|(?:<[^>()]*>)?\s*\())/g;

const NOT_A_FUNCTION = new Set([
  "if",
  "for",
  "while",
  "switch",
  "catch",
  "return",
  "await",
  "typeof",
  "new",
  "super",
  "function",
]);

/**
 * Where the return type annotation that may start at `from` ends: at the body
 * `{` or the `=>`. `Promise<{ a: string }>` and `{ a: string }` are types.
 */
function returnTypeEnd(code: string, from: number): number {
  let index = from;

  while (/\s/.test(code.charAt(index))) {
    index += 1;
  }

  if (code.charAt(index) !== ":") {
    return index;
  }

  let angle = 0;
  let expectType = true;

  for (index += 1; index < code.length; index += 1) {
    const char = code.charAt(index);

    if (/\s/.test(char)) {
      continue;
    }

    if (char === "=" && code.charAt(index + 1) === ">") {
      if (angle === 0 && !expectType) {
        return index;
      }

      index += 1;
      expectType = true;
    } else if (char === "<") {
      angle += 1;
      expectType = true;
    } else if (char === ">") {
      angle -= 1;
      expectType = false;
    } else if (char === "(" || char === "[") {
      index = closeOf(code, index);
      expectType = false;
    } else if (char === "{") {
      if (angle === 0 && !expectType) {
        return index;
      }

      index = closeOf(code, index);
      expectType = false;
    } else if (char === ";" || char === "=" || char === ")" || char === "}") {
      return -1;
    } else {
      expectType = "|&,:".includes(char);
    }
  }

  return -1;
}

/**
 * Functions, methods and arrow functions bound to a name, with their bodies:
 * `function load(`, `const load = async (`, `load: (`, `load() {`, `const load
 * = cache(async (`.
 */
export function functionsIn(code: string): NamedFunction[] {
  const functions: NamedFunction[] = [];

  for (const match of code.matchAll(FUNCTION_HEAD)) {
    const name = match[1] ?? match[2]!;

    if (NOT_A_FUNCTION.has(name)) {
      continue;
    }

    const head = match[0];
    const last = match.index + head.length - 1;
    const arrowParam = !head.endsWith("(");
    const declared = match[1] !== undefined || /function\b/.test(head);
    const method = !declared && !/[:=]/.test(head);

    const afterParams = arrowParam ? last + 1 : closeOf(code, last) + 1;
    const typeEnd = arrowParam ? afterParams : returnTypeEnd(code, afterParams);

    if (typeEnd === -1) {
      continue;
    }

    let start: number;

    if (arrowParam) {
      start = typeEnd;
    } else if (declared || method) {
      if (code.charAt(typeEnd) !== "{") {
        continue;
      }

      start = typeEnd;
    } else {
      if (!code.startsWith("=>", typeEnd)) {
        continue;
      }

      start = typeEnd + 2;
    }

    const open = /^\s*\{/.test(code.slice(start, start + 200))
      ? code.indexOf("{", start)
      : -1;

    const end = open === -1 ? statementEnd(code, start) : closeOf(code, open);

    functions.push({ name, start, end });
  }

  for (const match of code.matchAll(WRAPPED_CALL)) {
    const open = match.index + match[0].length - 1;

    functions.push({
      name: match[1]!,
      start: open,
      end: closeOf(code, open),
      wrapped: true,
    });
  }

  return functions;
}

/** The innermost named function around `at`, or `<module>`. */
function functionAt(functions: readonly NamedFunction[], at: number): string {
  const inside = functions.filter(
    (candidate) => candidate.start <= at && at < candidate.end,
  );

  const named = inside.filter((candidate) => candidate.wrapped !== true);
  const size = (item: NamedFunction): number => item.end - item.start;

  // The innermost function, or else the outermost wrapper: the export.
  const found =
    named.length > 0
      ? named.reduce((a, b) => (size(b) < size(a) ? b : a))
      : inside.reduce<NamedFunction | undefined>(
          (a, b) => (a === undefined || size(b) > size(a) ? b : a),
          undefined,
        );

  return found?.name ?? "<module>";
}

/**
 * Line-independent targets: `path#function:callee`, with `#2`, `#3` for the
 * second and later call of the same callee in one function. An edit elsewhere
 * in the file keeps them.
 */
export function targetKeys(
  path: string,
  functions: readonly NamedFunction[],
  calls: readonly { readonly start: number; readonly callee: string }[],
): Map<number, string> {
  const seen = new Map<string, number>();
  const keys = new Map<number, string>();

  for (const call of calls.toSorted((a, b) => a.start - b.start)) {
    const key = `${path}#${functionAt(functions, call.start)}:${call.callee}`;
    const count = (seen.get(key) ?? 0) + 1;

    seen.set(key, count);
    keys.set(call.start, count === 1 ? key : `${key}#${String(count)}`);
  }

  return keys;
}
