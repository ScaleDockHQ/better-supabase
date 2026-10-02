import { type Rule, defineRule } from "@oxlint/plugins";

import { signatureVisitor } from "../shared/signatures.ts";
import {
  annotatedParameters,
  unwrapParenthesizedType,
} from "../shared/type-nodes.ts";

/**
 * Ban parameters typed as a bare `unknown`, which push parsing onto every
 * caller. A parameter named `cause` is exempt: error causes carry an
 * unparsed value on purpose.
 */
export const noUnknownParametersRule: Rule = defineRule({
  meta: {
    type: "problem",
    docs: {
      description:
        "Disallow parameters typed as a bare `unknown`; accept a named domain type and parse at the I/O boundary.",
    },
    messages: {
      unknownParameter:
        "This parameter leaves input unparsed. Accept a named domain type; run the expected schema or parser at the I/O boundary before calling this function.",
    },
  },
  createOnce(context) {
    return signatureVisitor((node) => {
      for (const { name, annotation } of annotatedParameters(node.params)) {
        if (name === "cause") continue;
        if (unwrapParenthesizedType(annotation).type === "TSUnknownKeyword") {
          context.report({ node: annotation, messageId: "unknownParameter" });
        }
      }
    });
  },
});
