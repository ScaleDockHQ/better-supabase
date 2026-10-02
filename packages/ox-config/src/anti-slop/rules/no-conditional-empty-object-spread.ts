import type { ESTree } from "@oxlint/plugins";

import { type Rule, defineRule } from "@oxlint/plugins";

function unwrapParentheses(expression: ESTree.Expression): ESTree.Expression {
  let current = expression;
  while (current.type === "ParenthesizedExpression") {
    current = current.expression;
  }
  return current;
}

function isEmptyObject(expression: ESTree.Expression): boolean {
  return (
    expression.type === "ObjectExpression" && expression.properties.length === 0
  );
}

/**
 * Ban `{ ...(cond ? { a } : {}) }`, which hides property omission inside a
 * ternary. Build the object in steps so the omission is a visible statement.
 */
export const noConditionalEmptyObjectSpreadRule: Rule = defineRule({
  meta: {
    type: "problem",
    docs: {
      description:
        "Disallow spreading a conditional with an empty object branch into an object literal.",
    },
    messages: {
      conditionalSpread:
        "This conditional spread hides property omission behind an empty object. Build the object in separate statements and add the property only when present.",
    },
  },
  createOnce(context) {
    return {
      SpreadElement(node) {
        if (node.parent.type !== "ObjectExpression") return;
        const argument = unwrapParentheses(node.argument);
        if (argument.type !== "ConditionalExpression") return;
        if (
          isEmptyObject(argument.consequent) ||
          isEmptyObject(argument.alternate)
        ) {
          context.report({ node, messageId: "conditionalSpread" });
        }
      },
    };
  },
});
