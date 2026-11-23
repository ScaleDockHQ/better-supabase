import type { Node } from "oxc-parser";

/** `a.b` for a non-computed member expression of identifiers, else undefined. */
export function text(node: Node): string | undefined {
  if (node.type === "Identifier") {
    return node.name;
  }

  if (
    node.type === "MemberExpression" &&
    !node.computed &&
    node.property.type === "Identifier"
  ) {
    const object = text(node.object);

    return object === undefined ? undefined : `${object}.${node.property.name}`;
  }

  return undefined;
}

/** `node` without the wrappers that only carry a type or parentheses. */
export function unwrap(node: Node): Node {
  if (
    node.type === "TSSatisfiesExpression" ||
    node.type === "TSAsExpression" ||
    node.type === "TSNonNullExpression" ||
    node.type === "TSTypeAssertion" ||
    node.type === "ParenthesizedExpression"
  ) {
    return unwrap(node.expression);
  }

  return node;
}

/** The name an object key or a member names, when it is not computed. */
export function propertyName(property: Node): string | undefined {
  if (property.type !== "Property" || property.computed) {
    return undefined;
  }

  const { key } = property;

  if (key.type === "Identifier") {
    return key.name;
  }

  if (key.type === "Literal") {
    return String(key.value);
  }

  return undefined;
}
