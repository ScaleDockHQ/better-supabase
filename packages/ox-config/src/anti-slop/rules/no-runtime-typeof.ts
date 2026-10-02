import type { ESTree, Options } from "@oxlint/plugins";

import { type Rule, defineRule } from "@oxlint/plugins";

function enclosingFunction(
  node: ESTree.Node,
): ESTree.Function | ESTree.ArrowFunctionExpression | undefined {
  let current: ESTree.Node | null = node.parent;
  while (current) {
    if (
      current.type === "FunctionDeclaration" ||
      current.type === "FunctionExpression" ||
      current.type === "ArrowFunctionExpression"
    ) {
      return current;
    }
    current = current.parent;
  }
  return undefined;
}

function isInTypeGuard(node: ESTree.Node): boolean {
  return (
    enclosingFunction(node)?.returnType?.typeAnnotation.type ===
    "TSTypePredicate"
  );
}

function allowsTypeGuards(options: Readonly<Options>): boolean {
  const [first] = options;
  return (
    first instanceof Object &&
    !Array.isArray(first) &&
    first["allowInTypeGuards"] === true
  );
}

/**
 * Ban runtime `typeof` checks, which narrow a representation without
 * establishing a contract. Type queries (`type T = typeof x`) are a different
 * node and stay allowed. `allowInTypeGuards: true` exempts a check whose
 * nearest function returns a type predicate.
 */
export const noRuntimeTypeofRule: Rule = defineRule({
  meta: {
    type: "problem",
    docs: {
      description:
        "Disallow runtime `typeof` checks; parse input at its I/O boundary, then branch on the domain value.",
    },
    schema: [
      {
        type: "object",
        properties: { allowInTypeGuards: { type: "boolean" } },
        additionalProperties: false,
      },
    ],
    messages: {
      runtimeTypeof:
        "A `typeof` check narrows a representation without establishing its contract. Parse input at its I/O boundary, then branch on the domain value.",
    },
  },
  createOnce(context) {
    return {
      UnaryExpression(node) {
        if (node.operator !== "typeof") return;
        if (allowsTypeGuards(context.options) && isInTypeGuard(node)) return;
        context.report({ node, messageId: "runtimeTypeof" });
      },
    };
  },
});
