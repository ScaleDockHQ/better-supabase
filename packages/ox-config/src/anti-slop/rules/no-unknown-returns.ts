import type { ESTree } from "@oxlint/plugins";

import { type Rule, defineRule } from "@oxlint/plugins";

import { signatureVisitor } from "../shared/signatures.ts";
import {
  typeReferenceName,
  unwrapParenthesizedType,
} from "../shared/type-nodes.ts";

const promiseNames: ReadonlySet<string> = new Set(["Promise", "PromiseLike"]);

function isUnknownContract(type: ESTree.TSType): boolean {
  const unwrapped = unwrapParenthesizedType(type);
  if (unwrapped.type === "TSUnknownKeyword") return true;
  if (unwrapped.type === "TSUnionType") {
    return unwrapped.types.some(isUnknownContract);
  }
  if (unwrapped.type !== "TSTypeReference") return false;
  const name = typeReferenceName(unwrapped);
  const [resolved] = unwrapped.typeArguments?.params ?? [];
  return (
    name !== undefined &&
    promiseNames.has(name) &&
    resolved !== undefined &&
    isUnknownContract(resolved)
  );
}

/**
 * Ban an explicit `unknown` return contract, including a union with
 * `unknown` and `Promise<unknown>`.
 */
export const noUnknownReturnsRule: Rule = defineRule({
  meta: {
    type: "problem",
    docs: {
      description:
        "Disallow `unknown` return types; parse at the boundary and return a named domain type.",
    },
    messages: {
      unknownReturn:
        "This function exposes `unknown` to its caller. Parse the value at its boundary and return a named domain type.",
    },
  },
  createOnce(context) {
    return signatureVisitor((node) => {
      const returnType = node.returnType?.typeAnnotation;
      if (returnType && isUnknownContract(returnType)) {
        context.report({ node: returnType, messageId: "unknownReturn" });
      }
    });
  },
});
