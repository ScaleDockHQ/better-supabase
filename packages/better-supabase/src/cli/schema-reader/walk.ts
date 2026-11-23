import type { Node } from "@supabase/pg-parser/17/types";

import type { Obj } from "./ast.ts";

import { obj, strings } from "./ast.ts";
import { NODE_FIELDS } from "./node-fields.generated.ts";

/** A node type name: `ColumnRef`, `SelectStmt`, `RangeVar`. */
export type NodeTag = Node extends infer Each
  ? Each extends Readonly<Record<infer Tag, unknown>>
    ? Tag & string
    : never
  : never;

/** The body of a `tag` node, as the parser's types declare it. */
type NodeBody<Tag extends NodeTag> = Extract<
  Node,
  Readonly<Record<Tag, unknown>>
>[Tag];

/** Where a visited node sits in the tree. */
interface NodePath {
  readonly tag: string;
  readonly node: Obj;
  readonly parent: NodePath | undefined;
  /** The field of `parent` the node is in. */
  readonly key: string | undefined;
  /** The position in that field when the field is a list. */
  readonly index: number | undefined;
}

/** Functions per node type. One that returns `false` skips the node's children. */
export type Visitor = {
  readonly [Tag in NodeTag]?: (
    node: NodeBody<Tag>,
    path: NodePath,
  ) => boolean | undefined | void;
};

type Visit = (node: Obj, path: NodePath) => boolean | undefined | void;

const TAG = /^[A-Z]/;

/** The `[tag, body]` of a one-key `{ Tag: body }` value. */
function tagged(value: Obj): readonly [string, Obj] | undefined {
  const keys = Object.keys(value);

  return keys.length === 1 && TAG.test(keys[0]!)
    ? [keys[0]!, obj(value[keys[0]!])]
    : undefined;
}

function visit(
  tag: string,
  node: Obj,
  visitor: Visitor,
  parent: NodePath | undefined,
  key: string | undefined,
  index: number | undefined,
): void {
  const path: NodePath = { tag, node, parent, key, index };
  // SAFETY: `visitor[tag]` takes the body of a `tag` node, which `node` is.
  const each = (visitor as Readonly<Record<string, Visit | undefined>>)[tag];

  if (each?.(node, path) === false) {
    return;
  }

  for (const [field, type, isList] of NODE_FIELDS[tag] ?? []) {
    const value = node[field];

    if (isList && Array.isArray(value)) {
      for (const [at, item] of value.entries()) {
        child(item, type, visitor, path, field, at);
      }
    } else if (!isList) {
      child(value, type, visitor, path, field, undefined);
    }
  }
}

function child(
  value: unknown,
  type: string,
  visitor: Visitor,
  parent: NodePath | undefined,
  key: string | undefined,
  index: number | undefined,
): void {
  if (typeof value !== "object" || value === null || Array.isArray(value)) {
    return;
  }

  // SAFETY: `value` is a non-null, non-array object, checked above.
  const body = value as Obj;
  const wrapped = tagged(body);

  if (wrapped !== undefined && (type === "Node" || wrapped[0] === type)) {
    visit(wrapped[0], wrapped[1], visitor, parent, key, index);
  } else if (type !== "Node") {
    visit(type, body, visitor, parent, key, index);
  }
}

/**
 * Visits every node under `root` in source order, parents first. `root` is a
 * wrapped node (`{ SelectStmt: {...} }`), a list of them, or, with `tag`, the
 * bare body of a `tag` node (`parse()`'s tree is a bare `ParseResult`). A field
 * whose declared type is a message (`CreatePolicyStmt.table`, a `RangeVar`)
 * holds the body without its tag; the walker reads the tag from the type.
 *
 * @param root - The tree to walk.
 * @param visitor - The functions to call, per node type.
 * @param tag - The node type of `root` when it is a bare body.
 */
export function walk(root: unknown, visitor: Visitor, tag?: NodeTag): void {
  if (Array.isArray(root)) {
    for (const item of root) {
      child(item, "Node", visitor, undefined, undefined, undefined);
    }

    return;
  }

  child(root, tag ?? "Node", visitor, undefined, undefined, undefined);
}

/** Every column a tree names, in source order, without repeats. */
export function columnRefs(node: unknown): readonly string[] {
  const found: string[] = [];

  walk(node, {
    ColumnRef(ref) {
      const last = strings(ref.fields).at(-1);

      if (last !== undefined && !found.includes(last)) {
        found.push(last);
      }
    },
  });

  return found;
}
