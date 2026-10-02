import type { ESTree } from "@oxlint/plugins";

/** Peel parentheses off a type, and nothing else. */
export function unwrapParenthesizedType(type: ESTree.TSType): ESTree.TSType {
  let current = type;
  while (current.type === "TSParenthesizedType") {
    current = current.typeAnnotation;
  }
  return current;
}

/** Peel parentheses, assertions, `satisfies` and `!` off an expression. */
export function unwrapExpression(
  expression: ESTree.Expression,
): ESTree.Expression {
  let current = expression;
  while (
    current.type === "ParenthesizedExpression" ||
    current.type === "TSAsExpression" ||
    current.type === "TSSatisfiesExpression" ||
    current.type === "TSNonNullExpression" ||
    current.type === "TSTypeAssertion"
  ) {
    current = current.expression;
  }
  return current;
}

/** The plain name of a type reference, or `undefined` for a qualified one. */
export function typeReferenceName(
  type: ESTree.TSTypeReference,
): string | undefined {
  return type.typeName.type === "Identifier" ? type.typeName.name : undefined;
}

/** Built-in wrappers that keep the shape of the type they wrap. */
export const transparentWrappers: ReadonlySet<string> = new Set([
  "Readonly",
  "Partial",
  "Required",
  "NonNullable",
]);

/** A parameter with its binding name and its annotation, when written. */
export interface AnnotatedParameter {
  readonly name: string | undefined;
  readonly annotation: ESTree.TSType;
}

function annotatedPattern(
  pattern: ESTree.ParamPattern | ESTree.BindingPattern,
): AnnotatedParameter | undefined {
  switch (pattern.type) {
    case "TSParameterProperty":
      return annotatedPattern(pattern.parameter);
    case "AssignmentPattern":
      return annotatedPattern(pattern.left);
    case "Identifier":
      return pattern.typeAnnotation
        ? {
            name: pattern.name,
            annotation: pattern.typeAnnotation.typeAnnotation,
          }
        : undefined;
    case "RestElement": {
      const name =
        pattern.argument.type === "Identifier"
          ? pattern.argument.name
          : undefined;
      return pattern.typeAnnotation
        ? { name, annotation: pattern.typeAnnotation.typeAnnotation }
        : undefined;
    }
    case "ObjectPattern":
    case "ArrayPattern":
      return pattern.typeAnnotation
        ? { name: undefined, annotation: pattern.typeAnnotation.typeAnnotation }
        : undefined;
    default: {
      const exhaustive: never = pattern;
      return exhaustive;
    }
  }
}

/** Every annotated parameter of a parameter list, `this` included. */
export function annotatedParameters(
  params: readonly ESTree.ParamPattern[],
): AnnotatedParameter[] {
  return params.flatMap((param) => {
    const annotated = annotatedPattern(param);
    return annotated ? [annotated] : [];
  });
}
