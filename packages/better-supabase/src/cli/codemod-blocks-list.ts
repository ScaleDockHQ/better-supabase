import type { Codemod, ReviewLine } from "./codemod.ts";

import { ConfigDocument, propertyName } from "./config-document/index.ts";

const lineOf = (text: string, index: number): number =>
  text.slice(0, index).split("\n").length;

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
  // The codemod runs on every source file; only a file that calls defineConfig can hold blocks.
  if (!text.includes("defineConfig")) {
    return { text, review: [] };
  }

  const document = ConfigDocument.parse(text);
  const located = document.locate(["blocks"]);

  if (located?.value.type !== "ObjectExpression") {
    return { text, review: [] };
  }

  const object = located.value;
  const entries: { start: number; end: number; next: string }[] = [];

  for (const property of object.properties) {
    const name =
      property.type === "Property" ? propertyName(property) : undefined;

    if (
      property.type !== "Property" ||
      name === undefined ||
      property.value.type !== "ObjectExpression" ||
      property.shorthand ||
      property.method
    ) {
      return {
        text,
        review: [
          {
            line: lineOf(text, object.start),
            message:
              "blocks has an entry the codemod can't read (a spread or a computed key). Convert it to a list by hand.",
          },
        ],
      };
    }

    const { value } = property;
    const empty = value.properties.length === 0;

    const hasBlock = value.properties.some(
      (each) => each.type === "Property" && propertyName(each) === "block",
    );

    entries.push({
      start: property.start,
      end: property.end,
      next: empty
        ? JSON.stringify(name)
        : withLeadProperty(
            text.slice(value.start, value.end),
            hasBlock
              ? `name: ${JSON.stringify(name)}`
              : `block: ${JSON.stringify(name)}`,
          ),
    });
  }

  document.rewrite(({ edit }) => {
    for (const entry of entries) {
      edit.overwrite(entry.start, entry.end, entry.next);
    }

    edit.overwrite(object.start, object.start + 1, "[");
    edit.overwrite(object.end - 1, object.end, "]");

    const last = object.properties.at(-1);

    if (
      last !== undefined &&
      text.slice(object.start, object.end).includes("\n") &&
      !/^\s*,/.test(text.slice(last.end, object.end - 1))
    ) {
      edit.appendLeft(last.end, ",");
    }
  });

  return { text: document.text, review: [] };
}

export function blocksListCodemod(): Codemod {
  return {
    name: "blocks-list",
    description:
      "Rewrite `blocks: { name: { ... } }` as a list of names and { block, name?, ... } objects",
    source: blocksList,
  };
}
