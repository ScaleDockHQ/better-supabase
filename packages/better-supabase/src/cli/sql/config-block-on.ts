/**
 * The 0.15 move of `blocks.<name>.options.subjects` to `blocks.<name>.on`.
 * Field history's per-type column lists become `{ fields: [...] }`. Like
 * `config-block-names.ts`, the TypeScript edit is textual so comments and
 * formatting survive.
 */

import type { CodemodConfigEdit, ReviewLine } from "../codemod.ts";
import type { ConfigEdit, Property } from "./config-edit.ts";

import { isRecord } from "../guards.ts";
import { closingIndex, indentAt, mask, properties } from "./config-edit.ts";

interface Edit {
  readonly start: number;
  readonly end: number;
  readonly text: string;
}

const OPTIONS = /\boptions\s*:\s*\{/g;
const KEY_BEFORE = /(?:["']([\w-]+)["']|([A-Za-z_$][\w$-]*))\s*:\s*$/;

function applyEdits(source: string, edits: readonly Edit[]): string {
  let text = source;

  for (const edit of edits.toSorted((a, b) => b.start - a.start)) {
    text = text.slice(0, edit.start) + edit.text + text.slice(edit.end);
  }

  return text;
}

/** The `{` of the object literal that holds the code at `index`. */
function enclosingObject(code: string, index: number): number | undefined {
  let depth = 0;

  for (let at = index - 1; at >= 0; at -= 1) {
    const char = code[at];

    if (char === "}" || char === "]" || char === ")") {
      depth += 1;
    } else if (char === "{" || char === "[" || char === "(") {
      if (depth === 0) {
        return char === "{" ? at : undefined;
      }

      depth -= 1;
    }
  }

  return undefined;
}

/** The block an entry installs: its `block` string, or the key it sits under. */
export function blockOf(
  source: string,
  open: number,
  props: readonly Property[],
): string | undefined {
  const block = props.find((prop) => prop.key === "block");

  if (block !== undefined) {
    return /^["']([\w-]+)["']$/.exec(
      source.slice(block.valueStart, block.valueEnd),
    )?.[1];
  }

  const key = KEY_BEFORE.exec(source.slice(0, open));

  return key?.[1] ?? key?.[2];
}

/** `{ deal: ["amount"] }` as `{ deal: { fields: ["amount"] } }`. */
function wrapFields(source: string, code: string, open: number): Edit[] {
  return (properties(source, code, open) ?? []).flatMap((prop) =>
    prop.key !== undefined && code[prop.valueStart] === "["
      ? [
          {
            start: prop.valueStart,
            end: prop.valueEnd,
            text: `{ fields: ${source.slice(prop.valueStart, prop.valueEnd)} }`,
          },
        ]
      : [],
  );
}

/** `text` moved one object level out: two spaces fewer after each newline. */
const outdented = (text: string): string => text.replaceAll(/\n {2}/g, "\n");

/** The edit that removes `props[index]` from its object literal. */
function removal(props: readonly Property[], index: number): Edit {
  const next = props[index + 1];
  const previous = props[index - 1];
  const prop = props[index]!;

  if (next !== undefined) {
    return { start: prop.start, end: next.start, text: "" };
  }

  return {
    start: previous?.valueEnd ?? prop.start,
    end: prop.valueEnd,
    text: "",
  };
}

const lineOf = (source: string, index: number): number =>
  source.slice(0, index).split("\n").length;

/**
 * `source` with every `options.subjects` of a block entry moved to the entry's
 * `on`. An entry that already sets `on` is left and listed for review.
 */
export function moveSubjectsToOnInSource(source: string): {
  readonly text: string;
  readonly review: readonly ReviewLine[];
} {
  const code = mask(source);
  const edits: Edit[] = [];
  const review: ReviewLine[] = [];

  for (const match of code.matchAll(OPTIONS)) {
    const valueOpen = match.index + match[0].length - 1;
    const entryOpen = enclosingObject(code, match.index);

    if (entryOpen === undefined) {
      continue;
    }

    const entry = properties(source, code, entryOpen) ?? [];

    const options = entry.find(
      (prop) => prop.key === "options" && prop.valueStart === valueOpen,
    );

    const inner = properties(source, code, valueOpen) ?? [];
    const index = inner.findIndex((prop) => prop.key === "subjects");

    if (options === undefined || index === -1) {
      continue;
    }

    if (entry.some((prop) => prop.key === "on")) {
      review.push({
        line: lineOf(source, match.index),
        message:
          "options.subjects moved to on, and this block already sets on: merge them into on",
      });
      continue;
    }

    const subjects = inner[index]!;
    const shorthand = subjects.valueStart === subjects.start;

    const wrap =
      !shorthand &&
      code[subjects.valueStart] === "{" &&
      blockOf(source, entryOpen, entry) === "field-history";

    const slice = source.slice(subjects.valueStart, subjects.valueEnd);

    const raw = shorthand
      ? "subjects"
      : wrap
        ? applyEdits(
            slice,
            wrapFields(source, code, subjects.valueStart).map((edit) => ({
              ...edit,
              start: edit.start - subjects.valueStart,
              end: edit.end - subjects.valueStart,
            })),
          )
        : slice;

    const on = `on: ${outdented(raw)}`;

    if (inner.length === 1) {
      edits.push({ start: options.start, end: options.valueEnd, text: on });
      continue;
    }

    const multiline = code
      .slice(entryOpen, closingIndex(code, entryOpen))
      .includes("\n");

    edits.push(
      {
        start: options.start,
        end: options.start,
        text: `${on},${multiline ? `\n${indentAt(source, options.start)}` : " "}`,
      },
      removal(inner, index),
    );
  }

  return { text: applyEdits(source, edits), review };
}

function moveInObject(value: unknown): unknown {
  if (Array.isArray(value)) {
    return value.map(moveInObject);
  }

  if (!isRecord(value)) {
    return value;
  }

  const entries = Object.fromEntries(
    Object.entries(value).map(([key, entry]) => [key, moveInObject(entry)]),
  );

  const options = entries["options"];

  if (
    !isRecord(options) ||
    options["subjects"] === undefined ||
    entries["on"] !== undefined
  ) {
    return entries;
  }

  const { subjects, ...rest } = options;
  const { options: _, ...withoutOptions } = entries;

  return {
    ...withoutOptions,
    on: subjects,
    ...(Object.keys(rest).length > 0 && { options: rest }),
  };
}

/** Field history's `on`, with each column list as `{ fields }`. */
function fieldHistoryOn(config: unknown): unknown {
  if (!isRecord(config) || !isRecord(config["blocks"])) {
    return config;
  }

  const history = config["blocks"]["field-history"];

  if (!isRecord(history) || !isRecord(history["on"])) {
    return config;
  }

  const on = Object.fromEntries(
    Object.entries(history["on"]).map(([type, fields]) => [
      type,
      Array.isArray(fields) ? { fields } : fields,
    ]),
  );

  return {
    ...config,
    blocks: { ...config["blocks"], "field-history": { ...history, on } },
  };
}

/** `edit`, then every `options.subjects` moved to `on`. */
export function withSubjectsOn(
  edit: CodemodConfigEdit | ConfigEdit,
  json: boolean,
): CodemodConfigEdit {
  if (!edit.ok) {
    return edit;
  }

  const before = "review" in edit ? edit.review : [];

  if (!json) {
    const moved = moveSubjectsToOnInSource(edit.text);

    return { ok: true, text: moved.text, review: [...before, ...moved.review] };
  }

  const config: unknown = JSON.parse(edit.text);
  const moved = fieldHistoryOn(moveInObject(config));

  return {
    ok: true,
    text:
      JSON.stringify(moved) === JSON.stringify(config)
        ? edit.text
        : `${JSON.stringify(moved, null, 2)}\n`,
    review: before,
  };
}
