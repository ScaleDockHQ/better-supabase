import type { Node } from "oxc-parser";

import { walk } from "oxc-walker";

import type { Codemod, ReviewLine } from "./codemod.ts";

import { ConfigDocument, propertyName } from "./config-document/index.ts";

const same = (name: string): string => name.replaceAll("-", "_");

/** The registered type names, and the alias each one writes. */
function registered(
  document: ConfigDocument,
): ReadonlyMap<string, string | undefined> {
  const names = new Map<string, string | undefined>();
  const found = document.locate(["recordTypes"]);

  if (found?.value.type !== "ObjectExpression") {
    return names;
  }

  for (const property of found.value.properties) {
    const name =
      property.type === "Property" ? propertyName(property) : undefined;

    if (property.type !== "Property" || name === undefined) {
      continue;
    }

    const alias =
      property.value.type === "ObjectExpression"
        ? property.value.properties.find(
            (each) =>
              each.type === "Property" && propertyName(each) === "alias",
          )
        : undefined;

    names.set(
      name,
      alias?.type === "Property" &&
        alias.value.type === "Literal" &&
        typeof alias.value.value === "string"
        ? alias.value.value
        : undefined,
    );
  }

  return names;
}

/**
 * The names in `blocks.<block>.on` that differ from a registered record type
 * only by `-` and `_`, or that are its alias, written as the registered name.
 */
export function recordTypes(text: string): {
  readonly text: string;
  readonly review: readonly ReviewLine[];
} {
  const document = ConfigDocument.parse(text);
  const types = registered(document);
  const blocks = document.locate(["blocks"]);

  if (types.size === 0 || blocks === undefined) {
    return { text, review: [] };
  }

  const target = new Map<string, string>();

  for (const [name, alias] of types) {
    target.set(same(name), name);

    if (alias !== undefined) {
      target.set(alias, name);
    }
  }

  const fix = (name: string): string => {
    if (types.has(name)) {
      return name;
    }

    return target.get(name) ?? target.get(same(name)) ?? name;
  };

  document.rewrite(({ edit }) => {
    const rename = (inside: Node): void => {
      walk(inside, {
        enter(node: Node, parent: Node | null) {
          if (node.type === "Literal" && typeof node.value === "string") {
            edit.overwrite(node.start + 1, node.end - 1, fix(node.value));
          } else if (
            node.type === "Identifier" &&
            parent?.type === "Property" &&
            parent.key === node &&
            !parent.computed &&
            !parent.shorthand
          ) {
            edit.overwrite(node.start, node.end, fix(node.name));
          }
        },
      });
    };

    walk(blocks.value, {
      enter(node: Node) {
        if (
          node.type === "Property" &&
          !node.computed &&
          propertyName(node) === "on" &&
          (node.value.type === "ArrayExpression" ||
            node.value.type === "ObjectExpression")
        ) {
          rename(node.value);
          this.skip();
        }
      },
    });
  });

  return { text: document.text, review: [] };
}

export function recordTypesCodemod(): Codemod {
  return {
    name: "record-types",
    description:
      "Write the names in blocks.<name>.on as the record types in recordTypes, where they differ by - and _ or are an alias",
    source: recordTypes,
  };
}
