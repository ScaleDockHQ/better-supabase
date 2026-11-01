/**
 * The 0.47 codemod for block client calls that passed several positional
 * arguments and now pass one object (ADR 0177). The table is
 * `codemod-object-inputs-data.ts`. A call is rewritten only when its receiver
 * names the block or the method's own sub-client, and when exactly one
 * signature fits the arguments; every other candidate is listed for review.
 */

import type { CodemodResult, ReviewLine } from "./codemod.ts";

import { OBJECT_INPUT_ROWS } from "./codemod-object-inputs-data.ts";
import { closingIndex, mask } from "./sql/config-edit.ts";

interface Param {
  readonly name: string;
  readonly optional: boolean;
  /** An options object whose keys are merged into the input. */
  readonly merged: boolean;
}

interface Signature {
  readonly block: string;
  /** The sub-client names before the method, such as `["runs"]`. */
  readonly receiver: readonly string[];
  readonly method: string;
  readonly params: readonly Param[];
}

/** A call the codemod found, with its new spelling when it can write one. */
export interface ObjectInputCall {
  readonly start: number;
  readonly end: number;
  readonly line: number;
  readonly method: string;
  /** The rewritten argument list; `undefined` when the call needs a person. */
  readonly input: string | undefined;
  readonly reason: string;
}

function parseParam(text: string): Param {
  if (text.startsWith("...")) {
    return { name: text.slice(3), optional: true, merged: true };
  }

  return text.endsWith("?")
    ? { name: text.slice(0, -1), optional: true, merged: false }
    : { name: text, optional: false, merged: false };
}

function parseRow(row: string): Signature {
  const [block = "", path = "", ...params] = row.split(" ");
  const segments = path.split(".");

  return {
    block,
    receiver: segments.slice(0, -1),
    method: segments.at(-1) ?? path,
    params: params.map(parseParam),
  };
}

const BY_METHOD: ReadonlyMap<string, readonly Signature[]> = (() => {
  const map = new Map<string, Signature[]>();

  for (const row of OBJECT_INPUT_ROWS) {
    const signature = parseRow(row);
    const list = map.get(signature.method) ?? [];
    list.push(signature);
    map.set(signature.method, list);
  }

  return map;
})();

/** How many rows the table holds. */
export const OBJECT_INPUT_COUNT: number = OBJECT_INPUT_ROWS.length;

const CALL = /(\?\.|\.)\s*([A-Za-z_$][\w$]*)\s*\(/g;

/** The expression before a `.`, as dotted identifiers. */
function receiverOf(masked: string, dot: number): readonly string[] {
  const head = masked.slice(Math.max(0, dot - 120), dot);

  const chain =
    /(?:[A-Za-z_$][\w$]*(?:\s*\([^()]*\))?\s*(?:\?\.|\.|!\.)\s*)*[A-Za-z_$][\w$]*(?:\([^()]*\))?!?\s*$/u.exec(
      head,
    )?.[0] ?? "";

  return chain
    .replaceAll(/\([^()]*\)/g, "")
    .split(/\s*(?:\?\.|\.)\s*/u)
    .map((part) => part.replaceAll(/[!\s]/g, ""))
    .filter((part) => part.length > 0);
}

const normal = (value: string): string =>
  value.replaceAll(/[^a-z0-9]/gi, "").toLowerCase();

/** Whether the receiver's names point at the signature's block or sub-client. */
function receiverFits(
  signature: Signature,
  receiver: readonly string[],
): boolean {
  const { receiver: wanted } = signature;

  if (wanted.length > 0) {
    const tail = receiver.slice(-wanted.length);

    return (
      tail.length === wanted.length && tail.every((n, i) => n === wanted[i])
    );
  }

  const block = normal(signature.block);

  return receiver.some((name) => {
    const each = normal(name);

    return each.length > 0 && (each.includes(block) || each === "blocks");
  });
}

/** Splits the text between a call's parentheses at its top-level commas. */
function splitArguments(
  masked: string,
  from: number,
  to: number,
): { start: number; end: number }[] | undefined {
  const parts: { start: number; end: number }[] = [];
  let depth = 0;
  let angle = 0;
  let start = from;

  for (let index = from; index < to; index += 1) {
    const char = masked[index]!;

    if (char === '"' || char === "'" || char === "`") {
      index = masked.indexOf(char, index + 1);
    } else if ("([{".includes(char)) {
      depth += 1;
    } else if (")]}".includes(char)) {
      depth -= 1;
    } else if (char === "<" && depth === 0) {
      angle += 1;
    } else if (char === ">" && depth === 0 && masked[index - 1] !== "=") {
      angle -= 1;
    } else if (char === "," && depth === 0) {
      parts.push({ start, end: index });
      start = index + 1;
    }
  }

  if (angle !== 0 || depth !== 0) {
    return undefined;
  }

  if (masked.slice(start, to).trim().length > 0) {
    parts.push({ start, end: to });
  }

  return parts;
}

const isObjectLiteral = (text: string): boolean =>
  text.startsWith("{") && text.endsWith("}");

function objectInput(
  signature: Signature,
  args: readonly string[],
): string | undefined {
  const entries: string[] = [];

  for (const [index, param] of signature.params.entries()) {
    const arg = args[index]?.trim();

    if (arg === undefined || (param.optional && arg === "undefined")) {
      continue;
    }

    if (param.merged) {
      if (isObjectLiteral(arg)) {
        const inner = arg.slice(1, -1).trim();

        if (inner.length > 0) {
          entries.push(inner.replace(/,$/, ""));
        }
      } else {
        entries.push(`...${arg}`);
      }
    } else {
      entries.push(arg === param.name ? arg : `${param.name}: ${arg}`);
    }
  }

  return entries.length === 0 ? undefined : `{ ${entries.join(", ")} }`;
}

function fits(signature: Signature, count: number): boolean {
  const required = signature.params.filter((param) => !param.optional).length;

  return count >= required && count <= signature.params.length;
}

const lineOf = (text: string, index: number): number =>
  text.slice(0, index).split("\n").length;

const INPUT_NAME =
  /^(?:input|options|opts|query|args|params|payload|request|patch|data|body|filter|draft)$/;

/**
 * A single argument that is the old first positional one: anything but an
 * object literal or a variable named like an input, so a second run leaves
 * rewritten calls alone.
 */
function clearlyPositional(arg: string): boolean {
  return !arg.startsWith("{") && !INPUT_NAME.test(arg);
}

/**
 * Method names an app's own tables share (`db.tasks.update(id, patch)` is a
 * repository call), so the codemod lists these for review and never rewrites
 * them.
 */
const REPOSITORY_VERBS = new Set([
  "count",
  "create",
  "delete",
  "find",
  "get",
  "insert",
  "list",
  "publish",
  "remove",
  "select",
  "update",
  "upsert",
]);

/** Every call in `text` that still uses a block method's positional form. */
export function findObjectInputCalls(text: string): ObjectInputCall[] {
  const masked = mask(text);
  const found: ObjectInputCall[] = [];

  for (const match of masked.matchAll(CALL)) {
    const method = match[2] ?? "";
    const signatures = BY_METHOD.get(method);

    if (signatures === undefined) {
      continue;
    }

    const open = match.index + match[0].length - 1;
    const close = closingIndex(masked, open);

    if (close === -1) {
      continue;
    }

    const parts = splitArguments(masked, open + 1, close);
    const receiver = receiverOf(masked, match.index);
    const line = lineOf(text, match.index);

    if (parts === undefined) {
      continue;
    }

    const args = parts.map((part) => text.slice(part.start, part.end));

    const candidates = signatures.filter(
      (signature) =>
        (args.length >= 2 || signature.params.length >= 2) &&
        fits(signature, args.length),
    );

    if (candidates.length === 0) {
      continue;
    }

    const single = args.length === 1;

    const named = candidates.filter((signature) =>
      receiverFits(signature, receiver),
    );

    const [only] = named;

    const certain =
      only !== undefined &&
      !REPOSITORY_VERBS.has(method) &&
      new Set(named.map((signature) => objectInput(signature, args))).size ===
        1;

    // One argument is the new form unless it is clearly the old first one.
    if (single && !(certain && clearlyPositional(args[0]!.trim()))) {
      continue;
    }

    const input = certain ? objectInput(only, args) : undefined;

    found.push({
      start: open,
      end: close + 1,
      line,
      method,
      input,
      reason:
        input === undefined
          ? `\`.${method}(...)\` may be a block client method that took positional arguments and now takes one object (\`{ ${(candidates[0]?.params ?? []).map((param) => param.name).join(", ")} }\`); see the 0.46 to 0.47 guide`
          : "",
    });
  }

  return found;
}

/**
 * Rewrites the calls the table identifies and lists the other candidates. The
 * last rewritable call goes first, so an inner call is spelled before the call
 * that holds it.
 */
export function rewriteObjectInputCalls(source: string): CodemodResult {
  let text = source;

  for (let guard = 0; guard < 10_000; guard += 1) {
    const calls = findObjectInputCalls(text);
    const last = calls.findLast((call) => call.input !== undefined);

    if (last?.input === undefined) {
      break;
    }

    text = `${text.slice(0, last.start)}(${last.input})${text.slice(last.end)}`;
  }

  const review = findObjectInputCalls(text).map((call): ReviewLine => ({
    line: call.line,
    message: call.reason,
  }));

  return { text, review };
}
