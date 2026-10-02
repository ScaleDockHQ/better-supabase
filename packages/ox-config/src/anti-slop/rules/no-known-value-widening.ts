import type { ESTree } from "@oxlint/plugins";

import { type Rule, defineRule } from "@oxlint/plugins";

import {
  transparentWrappers,
  typeReferenceName,
  unwrapExpression,
  unwrapParenthesizedType,
} from "../shared/type-nodes.ts";

const knownValueTypes: ReadonlySet<string> = new Set([
  "ObjectExpression",
  "ArrayExpression",
  "ArrowFunctionExpression",
  "FunctionExpression",
  "ClassExpression",
  "NewExpression",
  "UnaryExpression",
  "Literal",
  "TemplateLiteral",
]);

/** A value a reader can see in full without leaving the expression. */
function isKnownValue(expression: ESTree.Expression): boolean {
  return knownValueTypes.has(unwrapExpression(expression).type);
}

function isEmptyObject(expression: ESTree.Expression): boolean {
  const unwrapped = unwrapExpression(expression);
  return (
    unwrapped.type === "ObjectExpression" && unwrapped.properties.length === 0
  );
}

function hasIndexSignature(type: ESTree.TSTypeLiteral): boolean {
  return type.members.some((member) => member.type === "TSIndexSignature");
}

function isDictionary(type: ESTree.TSType): boolean {
  return (
    (type.type === "TSTypeReference" && typeReferenceName(type) === "Record") ||
    type.type === "TSMappedType" ||
    (type.type === "TSTypeLiteral" && hasIndexSignature(type))
  );
}

/**
 * Whether `type`, under parentheses and `Readonly`-style wrappers, is a
 * target too broad for a known value. `{}` seeding a dictionary is the
 * ordinary accumulator and stays allowed.
 */
function isBroadTarget(type: ESTree.TSType, value: ESTree.Expression): boolean {
  const unwrapped = unwrapParenthesizedType(type);
  if (
    unwrapped.type === "TSUnknownKeyword" ||
    unwrapped.type === "TSObjectKeyword"
  ) {
    return true;
  }
  if (isDictionary(unwrapped)) return !isEmptyObject(value);
  if (unwrapped.type === "TSTypeLiteral") return unwrapped.members.length > 0;
  if (unwrapped.type !== "TSTypeReference") return false;
  const name = typeReferenceName(unwrapped);
  const [inner] = unwrapped.typeArguments?.params ?? [];
  return (
    name !== undefined &&
    transparentWrappers.has(name) &&
    inner !== undefined &&
    isBroadTarget(inner, value)
  );
}

function widens(type: ESTree.TSType, value: ESTree.Expression): boolean {
  return isKnownValue(value) && isBroadTarget(type, value);
}

type Assertion = ESTree.TSAsExpression | ESTree.TSTypeAssertion;

function isInnerAssertion(node: Assertion): boolean {
  let parent = node.parent;
  while (parent.type === "ParenthesizedExpression") parent = parent.parent;
  return parent.type === "TSAsExpression" || parent.type === "TSTypeAssertion";
}

function enclosingReturnType(node: ESTree.Node): ESTree.TSType | undefined {
  let current: ESTree.Node | null = node.parent;
  while (current) {
    if (
      current.type === "FunctionDeclaration" ||
      current.type === "FunctionExpression" ||
      current.type === "ArrowFunctionExpression"
    ) {
      return current.returnType?.typeAnnotation;
    }
    current = current.parent;
  }
  return undefined;
}

/**
 * Ban an explicit broad or anonymous type on a value whose shape is already
 * known at the same site: an annotated binding or class property, an
 * assertion, or a return. Keep inference, or check with `satisfies`.
 */
export const noKnownValueWideningRule: Rule = defineRule({
  meta: {
    type: "problem",
    docs: {
      description:
        "Disallow widening a known value to an explicit broad type; keep inference or use `satisfies`.",
    },
    messages: {
      widening:
        "The explicit broad type on this known value discards type evidence. Keep inference, validate with `satisfies`, or use a named owner contract.",
    },
  },
  createOnce(context) {
    const checkAssertion = (node: Assertion) => {
      if (isInnerAssertion(node)) return;
      if (widens(node.typeAnnotation, node.expression)) {
        context.report({ node, messageId: "widening" });
      }
    };

    const checkProperty = (
      node: ESTree.PropertyDefinition | ESTree.AccessorProperty,
    ) => {
      const type = node.typeAnnotation?.typeAnnotation;
      if (type && node.value && widens(type, node.value)) {
        context.report({ node, messageId: "widening" });
      }
    };

    return {
      VariableDeclarator(node) {
        if (node.id.type !== "Identifier" || !node.init) return;
        const type = node.id.typeAnnotation?.typeAnnotation;
        if (type && widens(type, node.init)) {
          context.report({ node, messageId: "widening" });
        }
      },
      PropertyDefinition: checkProperty,
      AccessorProperty: checkProperty,
      TSAsExpression: checkAssertion,
      TSTypeAssertion: checkAssertion,
      ReturnStatement(node) {
        const type = enclosingReturnType(node);
        if (type && node.argument && widens(type, node.argument)) {
          context.report({ node, messageId: "widening" });
        }
      },
      ArrowFunctionExpression(node) {
        const type = node.returnType?.typeAnnotation;
        if (
          node.expression &&
          node.body.type !== "BlockStatement" &&
          type &&
          widens(type, node.body)
        ) {
          context.report({ node, messageId: "widening" });
        }
      },
    };
  },
});
