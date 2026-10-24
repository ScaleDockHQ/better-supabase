/**
 * The 0.15 removal of `ownership: "adopt"`. A block now leaves alone every
 * table the app's schema already has, so the key goes and the block's `tables`
 * and `columns` mappings stay. The edit is textual, like `config-block-on.ts`,
 * so comments and formatting survive.
 */

import type { CodemodConfigEdit, ReviewLine } from "../codemod.ts";

import { mask } from "./config-edit.ts";

const ADOPT =
  /(?:\bownership|"ownership"|'ownership')\s*:\s*(["'])adopt\1[ \t]*,?/g;

const lineOf = (text: string, index: number): number =>
  text.slice(0, index).split("\n").length;

/** `[start, end)` to delete for the property matched at `start..end`. */
function span(text: string, start: number, end: number): [number, number] {
  const lineStart = text.lastIndexOf("\n", start - 1) + 1;
  const newline = text.indexOf("\n", end);
  const lineEnd = newline === -1 ? text.length : newline;

  if (
    text.slice(lineStart, start).trim() === "" &&
    text.slice(end, lineEnd).trim() === ""
  ) {
    const after = newline === -1 ? lineEnd : lineEnd + 1;
    const before = text.slice(0, lineStart).trimEnd();

    return text[end - 1] !== "," && before.endsWith(",")
      ? [before.length - 1, lineEnd]
      : [lineStart, after];
  }

  if (text[end - 1] === ",") {
    return [start, end + (/^[ \t]*/.exec(text.slice(end))?.[0].length ?? 0)];
  }

  const before = text.slice(0, start).trimEnd();

  return before.endsWith(",") ? [before.length - 1, end] : [start, end];
}

/** `source` without its `ownership: "adopt"` keys, and a review line each. */
export function removeAdoptOwnership(
  source: string,
  json: boolean,
): { readonly text: string; readonly review: readonly ReviewLine[] } {
  const code = json ? source : mask(source);
  const spans: [number, number][] = [];
  const review: ReviewLine[] = [];

  for (const match of source.matchAll(ADOPT)) {
    const start = match.index;
    const value = source.indexOf(match[1]!, start + "ownership".length + 1);

    if (!json && (code[start] === " " || code[value] !== match[1])) {
      continue;
    }

    const removed = span(source, start, start + match[0].length);

    const linesBefore = spans
      .map(([from, to]) => source.slice(from, to).split("\n").length - 1)
      .reduce((sum, count) => sum + count, 0);

    review.push({
      line: Math.max(lineOf(source, removed[0]) - linesBefore, 1),
      message:
        'removed ownership: "adopt": the block now leaves alone every table your schema already has and keeps its tables and columns mappings. Run `better-supabase upgrade` to write its SQL over them',
    });
    spans.push(removed);
  }

  let text = source;

  for (const [start, end] of spans.toReversed()) {
    text = text.slice(0, start) + text.slice(end);
  }

  return { text, review };
}

/** `edit` with `ownership: "adopt"` removed from every block. */
export function withoutAdoptOwnership(
  edit: CodemodConfigEdit,
  json: boolean,
): CodemodConfigEdit {
  if (!edit.ok) {
    return edit;
  }

  const earlier = "review" in edit ? edit.review : [];
  const { text, review } = removeAdoptOwnership(edit.text, json);

  return { ok: true, text, review: [...earlier, ...review] };
}
