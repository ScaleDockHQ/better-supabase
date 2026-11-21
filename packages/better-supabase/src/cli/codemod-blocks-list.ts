import type { Codemod, ReviewLine } from "./codemod.ts";

import { topLevelValue } from "./codemod-prune.ts";
import { KEY, LEADING_COMMENTS, segments } from "./codemod-sort-keys.ts";

const lineOf = (text: string, index: number): number =>
  text.slice(0, index).split("\n").length;

const BLOCK_KEY = /(?:^|[{,\s])(?:block|"block"|'block')\s*:/;

/** `{ ...inner }` with `lead` as its first property. */
function withLeadProperty(object: string, lead: string): string {
  const rest = object.slice(1);
  const indent = /^[^\S\n]*\n([^\S\n]*)/.exec(rest);

  return indent === null
    ? `{ ${lead},${rest.startsWith(" ") ? "" : " "}${rest}`
    : `{\n${indent[1]!}${lead},${rest}`;
}

interface Rewritten {
  readonly text: string;
  readonly review: readonly ReviewLine[];
}

/**
 * `blocks: { name: {...} }` as the list `[ "name", { block: "name", ... } ]`.
 * An entry that already sets `block` keeps it and gains `name`. A body with a
 * spread or a computed key stays as written and gets a review line.
 */
export function blocksList(text: string): Rewritten {
  const located = topLevelValue(text, "blocks");

  if (located === undefined) {
    return { text, review: [] };
  }

  const value = text.slice(located.start, located.end);
  const trimmed = value.trim();

  if (!trimmed.startsWith("{") || !trimmed.endsWith("}")) {
    return { text, review: [] };
  }

  const offset = value.indexOf("{");
  const inner = trimmed.slice(1, -1);
  const parts = segments(inner);
  const trailing = parts.at(-1)!.trim() === "" ? parts.pop()! : undefined;
  const out: string[] = [];

  for (const part of parts) {
    const core = part.trim();
    const comments = LEADING_COMMENTS.exec(core)![0];
    const entry = core.slice(comments.length);
    const key = KEY.exec(entry);
    const name = key === null ? undefined : (key[1] ?? key[2] ?? key[3]);

    const body = key === null ? undefined : entry.slice(key[0].length).trim();

    if (name === undefined || body === undefined || !body.startsWith("{")) {
      return {
        text,
        review: [
          {
            line: lineOf(text, located.start + offset),
            message:
              "blocks has an entry the codemod can't read (a spread or a computed key). Convert it to a list by hand.",
          },
        ],
      };
    }

    const empty = body.replaceAll(/[\s{}]/g, "") === "";
    const hasBlock = BLOCK_KEY.test(body);

    const next = empty
      ? JSON.stringify(name)
      : withLeadProperty(
          body,
          hasBlock
            ? `name: ${JSON.stringify(name)}`
            : `block: ${JSON.stringify(name)}`,
        );

    out.push(
      `${/^\s*/.exec(part)![0]}${comments}${next}${/\s*$/.exec(part)![0]}`,
    );
  }

  const list = `[${out.join(",")}${out.length > 0 ? "," : ""}${trailing ?? ""}]`;

  return {
    text:
      text.slice(0, located.start + offset) +
      list +
      text.slice(located.start + value.lastIndexOf("}") + 1),
    review: [],
  };
}

export function blocksListCodemod(): Codemod {
  return {
    name: "blocks-list",
    description:
      "Rewrite `blocks: { name: { ... } }` as a list of names and { block, name?, ... } objects",
    source: blocksList,
  };
}
