import type { ESTree } from "@oxlint/plugins";

import { type Rule, defineRule } from "@oxlint/plugins";

import { signatureVisitor } from "../shared/signatures.ts";
import {
  annotatedParameters,
  unwrapParenthesizedType,
} from "../shared/type-nodes.ts";

function isObjectKeyword(type: ESTree.TSType): boolean {
  const unwrapped = unwrapParenthesizedType(type);
  if (unwrapped.type === "TSObjectKeyword") return true;
  return (
    unwrapped.type === "TSUnionType" && unwrapped.types.some(isObjectKeyword)
  );
}

/**
 * Ban the broad `object` type on a parameter, alone or in a union. Composite
 * types that only mention it (`object[]`, `{ meta: object }`) stay allowed.
 */
export const noObjectParametersRule: Rule = defineRule({
  meta: {
    type: "problem",
    docs: {
      description:
        "Disallow parameters typed as `object`; accept a named owner type.",
    },
    messages: {
      objectParameter:
        "This parameter uses the broad `object` type. Accept a named owner type; parse external input at its boundary before calling this function.",
    },
  },
  createOnce(context) {
    return signatureVisitor((node) => {
      for (const { annotation } of annotatedParameters(node.params)) {
        if (isObjectKeyword(annotation)) {
          context.report({ node: annotation, messageId: "objectParameter" });
        }
      }
    });
  },
});
