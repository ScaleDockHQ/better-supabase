import type { Obj } from "./ast.ts";
import type { CommentFact, CommentTarget } from "./facts.ts";

import { bodyOf, list, str, strings, unwrap } from "./ast.ts";

/** How a file's names resolve: the search path and the source's type text. */
export interface Naming {
  readonly names: (parts: readonly string[]) => string;
  readonly signature: (types: readonly unknown[]) => string;
}

const COMMENT_TARGETS: Readonly<Record<string, CommentTarget>> = {
  OBJECT_TABLE: "table",
  OBJECT_COLUMN: "column",
  OBJECT_VIEW: "view",
  OBJECT_MATVIEW: "view",
  OBJECT_FUNCTION: "function",
  OBJECT_PROCEDURE: "function",
  OBJECT_TYPE: "type",
  OBJECT_DOMAIN: "type",
  OBJECT_SCHEMA: "schema",
};

export function commentOf(
  naming: Naming,
  comment: Obj,
  line: number,
): CommentFact | undefined {
  const target = COMMENT_TARGETS[str(comment["objtype"]) ?? ""] ?? "other";
  const text = str(comment["comment"]);

  if (text === undefined) {
    return undefined;
  }

  const unwrapped = unwrap(comment["object"]);

  if (unwrapped?.[0] === "ObjectWithArgs") {
    return {
      target,
      name: naming.names(strings(unwrapped[1]["objname"])),
      signature: naming.signature(
        list(unwrapped[1]["objargs"]).map((arg) => bodyOf(arg, "TypeName")),
      ),
      text,
      line,
    };
  }

  const names =
    unwrapped?.[0] === "List"
      ? strings(unwrapped[1]["items"])
      : unwrapped?.[0] === "TypeName"
        ? strings(unwrapped[1]["names"])
        : unwrapped?.[0] === "String"
          ? [str(unwrapped[1]["sval"]) ?? ""]
          : [];

  const name =
    target === "column"
      ? `${naming.names(names.slice(0, -1))}.${names.at(-1) ?? ""}`
      : target === "schema"
        ? (names[0] ?? "")
        : naming.names(names);

  return { target, name, signature: undefined, text, line };
}
