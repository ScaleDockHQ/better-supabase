/**
 * The 0.47 entity key renames: a key in `blocks.<name>.entities` now equals the
 * entity's singular (`work_item` is `task`). The edit is textual, like
 * `config-block-on.ts`, so comments and formatting survive.
 */

import type { CodemodConfigEdit, ReviewLine } from "../codemod.ts";

import { ENTITY_KEY_RENAMES } from "../../index.ts";
import { blockOf } from "./config-block-on.ts";
import { mask, properties } from "./config-edit.ts";

const ENTITIES = /(?:\bentities|"entities"|'entities')\s*:\s*\{/g;

const lineOf = (source: string, index: number): number =>
  source.slice(0, index).split("\n").length;

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

/** `source` with the old entity keys of every block entry renamed. */
function renameEntityKeysInSource(source: string): {
  readonly text: string;
  readonly review: readonly ReviewLine[];
} {
  const code = mask(source);
  const edits: { start: number; end: number; text: string }[] = [];
  const review: ReviewLine[] = [];

  for (const match of source.matchAll(ENTITIES)) {
    if (code[match.index] === " ") {
      continue;
    }

    const open = match.index + match[0].length - 1;
    const entryOpen = enclosingObject(code, match.index);

    if (entryOpen === undefined) {
      continue;
    }

    const block = blockOf(
      source,
      entryOpen,
      properties(source, code, entryOpen) ?? [],
    );

    const keys = block === undefined ? undefined : ENTITY_KEY_RENAMES[block];
    const entities = properties(source, code, open) ?? [];

    for (const entity of entities) {
      const next =
        entity.key === undefined || keys === undefined
          ? undefined
          : Object.hasOwn(keys, entity.key)
            ? keys[entity.key]
            : undefined;

      if (next === undefined || entity.key === undefined) {
        continue;
      }

      if (entities.some((other) => other.key === next)) {
        review.push({
          line: lineOf(source, entity.start),
          message: `blocks.${String(block)}.entities sets both ${entity.key} and ${next}, its new key: keep ${next}`,
        });
        continue;
      }

      const quote = source[entity.start];
      const quoted = quote === '"' || quote === "'";

      edits.push({
        start: entity.start,
        end: entity.start + entity.key.length + (quoted ? 2 : 0),
        text: quoted ? `${quote}${next}${quote}` : next,
      });
    }
  }

  let text = source;

  for (const edit of edits.toSorted((a, b) => b.start - a.start)) {
    text = text.slice(0, edit.start) + edit.text + text.slice(edit.end);
  }

  return { text, review };
}

/** `edit` with the old entity keys of every block renamed. */
export function withEntityKeysRenamed(
  edit: CodemodConfigEdit,
): CodemodConfigEdit {
  if (!edit.ok) {
    return edit;
  }

  const earlier = "review" in edit ? edit.review : [];
  const { text, review } = renameEntityKeysInSource(edit.text);

  return { ok: true, text, review: [...earlier, ...review] };
}
