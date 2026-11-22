import type { Node } from "oxc-parser";

import { walk } from "oxc-walker";

import type { NamingRename } from "./codemod-naming.ts";
import type { ReviewLine } from "./codemod.ts";

import { rewriteSource } from "./config-document/index.ts";

/** A rewrite's new text and the places it could not follow. */
export interface Rewritten {
  readonly text: string;
  readonly review: readonly ReviewLine[];
}

const camel = (name: string): string =>
  name.replaceAll(/-([a-z])/g, (_all, letter: string) => letter.toUpperCase());

/** The string a non-computed key or a string literal holds. */
function keyText(node: Node): string | undefined {
  if (node.type === "Identifier") {
    return node.name;
  }

  return node.type === "Literal" && typeof node.value === "string"
    ? node.value
    : undefined;
}

/** `to` written the way `at` was: quotes stay around a quoted key. */
function asWritten(text: string, node: Node, to: string): string {
  return node.type === "Literal"
    ? `${text[node.start]}${to}${text[node.start]}`
    : to;
}

/**
 * `text` with each property or argument name of the `argument` rows renamed: `{
 * workItemId: id }`, `result.workItemId`, `result["workItemId"]` and the
 * shorthand `{ workItemId }`, which keeps its local name (`{ taskId: workItemId
 * }`). A key whose value is the new name collapses to a shorthand (`{
 * workItemId: taskId }` is `{ taskId }`). Keys of object literals, patterns,
 * type literals and interfaces count, plus a member access. Import and export
 * lists, comments and strings stay as they are. A file that does not parse is
 * listed, not skipped.
 */
export function renameArguments(
  text: string,
  renames: readonly NamingRename[],
): Rewritten {
  const names = new Map(
    renames
      .filter((rename) => rename.kind === "argument")
      .map((rename) => [rename.from, rename.to]),
  );

  if (names.size === 0) {
    return { text, review: [] };
  }

  return rewriteSource(text, ({ program, text: source, edit }) => {
    const renamed = (node: Node): string | undefined => {
      const name = keyText(node);

      return name === undefined ? undefined : names.get(name);
    };

    walk(program, {
      enter(node) {
        if (node.type === "MemberExpression") {
          const to = renamed(node.property);

          if (
            to !== undefined &&
            (node.computed
              ? node.property.type === "Literal"
              : node.property.type === "Identifier")
          ) {
            edit.overwrite(
              node.property.start,
              node.property.end,
              asWritten(source, node.property, to),
            );
          }

          return;
        }

        if (
          (node.type === "TSPropertySignature" ||
            node.type === "TSMethodSignature") &&
          !node.computed
        ) {
          const to = renamed(node.key);

          if (to !== undefined) {
            edit.overwrite(
              node.key.start,
              node.key.end,
              asWritten(source, node.key, to),
            );
          }

          return;
        }

        if (node.type !== "Property" || node.computed) {
          return;
        }

        const to = renamed(node.key);

        if (to === undefined) {
          return;
        }

        const from = keyText(node.key)!;

        if (node.shorthand) {
          if (to !== from) {
            edit.overwrite(node.key.start, node.key.end, `${to}: ${from}`);
          }
        } else if (
          !node.method &&
          node.kind === "init" &&
          node.value.type === "Identifier" &&
          node.value.name === to
        ) {
          edit.overwrite(node.start, node.end, to);
        } else {
          edit.overwrite(
            node.key.start,
            node.key.end,
            asWritten(source, node.key, to),
          );
        }
      },
    });
  });
}

/** `blocks`, `blockConfig` or a member with that name (`config.blocks`). */
function isBlocksObject(node: Node): boolean {
  const name =
    node.type === "Identifier"
      ? node.name
      : node.type === "MemberExpression" &&
          !node.computed &&
          node.property.type === "Identifier"
        ? node.property.name
        : undefined;

  return name === "blocks" || name === "blockConfig";
}

/** The literal key of `blocks["name"]` or `blockConfig["name"]`, when it is one. */
function blockKey(node: Node): { name: string; at: Node } | undefined {
  if (
    node.type !== "MemberExpression" ||
    !node.computed ||
    !isBlocksObject(node.object) ||
    node.property.type !== "Literal" ||
    typeof node.property.value !== "string"
  ) {
    return undefined;
  }

  return { name: node.property.value, at: node.property };
}

/** The `blocks["name"]` a call or member chain starts from, when it does. */
function rootBlockKey(node: Node): { name: string; at: Node } | undefined {
  let at: Node = node;

  for (;;) {
    const found = blockKey(at);

    if (found !== undefined) {
      return found;
    }

    if (at.type === "CallExpression") {
      at = at.callee;
    } else if (at.type === "MemberExpression") {
      at = at.object;
    } else {
      return undefined;
    }
  }
}

/**
 * `text` with the block keys of the `blocks.<name>` rows renamed where code
 * reads them: `blocks["time-tracking"]`, `blockConfig["time-tracking"]`,
 * `db.$blocks.timeTracking` and the key of a `defineBlocks` entry that reads
 * the block (`"time-tracking": blocks["time-tracking"]`). The config key itself
 * is renamed by the config document. Strings and comments that only mention a
 * name stay.
 */
export function renameBlockReferences(
  text: string,
  renames: readonly NamingRename[],
): Rewritten {
  const pairs = renames.flatMap((rename) => {
    const from = /^blocks\.([^.]+)$/.exec(rename.from)?.[1];
    const to = /^blocks\.([^.]+)$/.exec(rename.to)?.[1];

    return rename.kind === "configKey" && from !== undefined && to !== undefined
      ? [{ from, to }]
      : [];
  });

  if (pairs.length === 0) {
    return { text, review: [] };
  }

  return rewriteSource(text, ({ program, text: source, edit }) => {
    walk(program, {
      enter(node) {
        const read = blockKey(node);

        if (read !== undefined) {
          const pair = pairs.find((each) => each.from === read.name);

          if (pair !== undefined) {
            edit.overwrite(
              read.at.start,
              read.at.end,
              `${source[read.at.start]}${pair.to}${source[read.at.start]}`,
            );
          }

          return;
        }

        if (
          node.type === "MemberExpression" &&
          !node.computed &&
          node.property.type === "Identifier" &&
          node.object.type === "MemberExpression" &&
          !node.object.computed &&
          node.object.property.type === "Identifier" &&
          node.object.property.name === "$blocks"
        ) {
          const pair = pairs.find(
            (each) => camel(each.from) === node.property.name,
          );

          if (pair !== undefined) {
            edit.overwrite(
              node.property.start,
              node.property.end,
              camel(pair.to),
            );
          }

          return;
        }

        if (
          node.type === "Property" &&
          !node.computed &&
          node.key.type === "Literal" &&
          typeof node.key.value === "string"
        ) {
          const key = rootBlockKey(node.value);
          const name = node.key.value;

          const pair = pairs.find(
            (each) =>
              each.from === name &&
              (key?.name === each.from || key?.name === each.to),
          );

          if (pair !== undefined) {
            edit.overwrite(
              node.key.start,
              node.key.end,
              `${source[node.key.start]}${pair.to}${source[node.key.start]}`,
            );
          }
        }
      },
    });
  });
}
