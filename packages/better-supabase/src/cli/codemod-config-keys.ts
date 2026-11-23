import type { Node } from "oxc-parser";

import type { NamingRename } from "./codemod-naming.ts";
import type { PathSegment } from "./config-document/index.ts";

import { isSorted } from "./codemod-sort-keys.ts";
import { ConfigDocument, propertyName } from "./config-document/index.ts";

interface ReviewLine {
  readonly line: number;
  readonly message: string;
}

const IDENTIFIER = /^[A-Za-z_$][\w$]*$/;

/** The key a `from` path ends in and its parent path, for a same-parent rename. */
function parts(path: string): {
  readonly parent: string;
  readonly key: string;
} {
  const at = path.lastIndexOf(".");

  return at === -1
    ? { parent: "", key: path }
    : { parent: path.slice(0, at), key: path.slice(at + 1) };
}

/**
 * Renames the config keys in `rows` (kind `configKey`) inside each
 * `defineConfig(...)` call of `text`. The tree gives the path of every key, so
 * `gen: { output }` becomes `gen: { file }` while `blocks.tasks.output` and the
 * same name in a string, a comment or another object stay. A row whose `to` has
 * another parent (a key that moved) is not rewritten; it is reported for the
 * author to move. An object whose keys were sorted stays sorted.
 */
export function renameConfigKeys(
  text: string,
  rows: readonly NamingRename[],
): { readonly text: string; readonly review: readonly ReviewLine[] } {
  const wanted = rows.filter((row) => row.kind === "configKey");

  if (wanted.length === 0 || !text.includes("defineConfig")) {
    return { text, review: [] };
  }

  const document = ConfigDocument.parse(text);
  const review: ReviewLine[] = [];
  const toSort: { call: number; path: PathSegment[] }[] = [];

  const lineOf = (offset: number): number =>
    text.slice(0, offset).split("\n").length;

  document.rewrite(({ edit }) => {
    const visit = (
      node: Node,
      names: readonly string[],
      location: { call: number; path: PathSegment[] },
    ): void => {
      if (node.type === "ArrayExpression") {
        for (const [index, element] of node.elements.entries()) {
          if (element !== null && element.type !== "SpreadElement") {
            visit(element, [...names, "*"], {
              call: location.call,
              path: [...location.path, index],
            });
          }
        }

        return;
      }

      if (node.type !== "ObjectExpression") {
        return;
      }

      const before: string[] = [];
      const after: string[] = [];

      for (const property of node.properties) {
        const name = propertyName(property);

        if (property.type !== "Property" || name === undefined) {
          continue;
        }

        const full = [...names, name].join(".");
        const row = wanted.find((each) => each.from === full);
        let written = name;

        if (row !== undefined) {
          const target = parts(row.to);

          if (target.parent === parts(row.from).parent) {
            written = target.key;
            const { key } = property;

            const quote =
              key.type === "Literal" ? text.charAt(key.start) : undefined;

            edit.overwrite(
              key.start,
              key.end,
              quote === undefined
                ? IDENTIFIER.test(target.key)
                  ? target.key
                  : JSON.stringify(target.key)
                : `${quote}${target.key}${quote}`,
            );
          } else {
            review.push({
              line: lineOf(property.start),
              message: `${row.from} moved to ${row.to}; move the key by hand.`,
            });
          }
        }

        before.push(name);
        after.push(written);
        visit(property.value, [...names, name], {
          call: location.call,
          path: [...location.path, written],
        });
      }

      // A rename can break the order a config's keys were in; keep it.
      if (
        before.some((name, index) => name !== after[index]) &&
        isSorted(before) &&
        !isSorted(after)
      ) {
        toSort.push(location);
      }
    };

    for (const [call, object] of document.defineConfigCalls().entries()) {
      visit(object, [], { call, path: [] });
    }
  });

  for (const target of toSort) {
    document.sortKeys(target.path, target.call);
  }

  return { text: document.text, review };
}
