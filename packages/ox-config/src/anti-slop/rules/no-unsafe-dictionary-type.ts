import type { ESTree } from "@oxlint/plugins";

import { type Rule, defineRule } from "@oxlint/plugins";

import {
  transparentWrappers,
  typeReferenceName,
  unwrapParenthesizedType,
} from "../shared/type-nodes.ts";

/** Names declared or imported as types at the top of the file. */
function declaredTypeNames(program: ESTree.Program): Set<string> {
  const names = new Set<string>();
  for (const statement of program.body) {
    const declaration =
      statement.type === "ExportNamedDeclaration"
        ? statement.declaration
        : statement;
    if (!declaration) continue;
    if (
      declaration.type === "TSTypeAliasDeclaration" ||
      declaration.type === "TSInterfaceDeclaration" ||
      declaration.type === "TSEnumDeclaration"
    ) {
      names.add(declaration.id.name);
    } else if (declaration.type === "ClassDeclaration" && declaration.id) {
      names.add(declaration.id.name);
    } else if (declaration.type === "ImportDeclaration") {
      for (const specifier of declaration.specifiers) {
        names.add(specifier.local.name);
      }
    }
  }
  return names;
}

const escapeHatchTypes: ReadonlySet<string> = new Set([
  "TSUnknownKeyword",
  "TSAnyKeyword",
  "TSObjectKeyword",
]);

function isEffectivelyEmptyLiteral(type: ESTree.TSTypeLiteral): boolean {
  return type.members.every(
    (member) =>
      member.type === "TSPropertySignature" &&
      member.optional &&
      member.typeAnnotation?.typeAnnotation.type === "TSNeverKeyword",
  );
}

/**
 * Ban dictionaries whose value type is `unknown`, `any`, `object` or `{}`
 * (or a union containing one, or one behind `Readonly`-style wrappers):
 * `Record<K, V>`, index signatures and mapped types alike.
 */
export const noUnsafeDictionaryTypeRule: Rule = defineRule({
  meta: {
    type: "problem",
    docs: {
      description:
        "Disallow dictionary types whose values are unknown, any, object or {}.",
    },
    messages: {
      unsafeDictionary:
        "This dictionary's unknown/any/object/{} value type gives callers no concrete value contract. Use an owner/schema-derived value type; parse external payloads before insertion.",
    },
  },
  createOnce(context) {
    let shadowed = new Set<string>();

    const isAny = (type: ESTree.TSType): boolean => {
      const unwrapped = unwrapParenthesizedType(type);
      if (unwrapped.type === "TSAnyKeyword") return true;
      return (
        unwrapped.type === "TSTypeReference" &&
        isWrapper(unwrapped) &&
        wrapperArguments(unwrapped).some(isAny)
      );
    };

    const isWrapper = (type: ESTree.TSTypeReference): boolean => {
      const name = typeReferenceName(type);
      return (
        name !== undefined &&
        transparentWrappers.has(name) &&
        !shadowed.has(name)
      );
    };

    const wrapperArguments = (type: ESTree.TSTypeReference): ESTree.TSType[] =>
      type.typeArguments?.params ?? [];

    const isUnsafeValue = (type: ESTree.TSType): boolean => {
      const unwrapped = unwrapParenthesizedType(type);
      if (escapeHatchTypes.has(unwrapped.type)) return true;
      if (unwrapped.type === "TSTypeLiteral") {
        return isEffectivelyEmptyLiteral(unwrapped);
      }
      if (unwrapped.type === "TSUnionType") {
        return unwrapped.types.some(isUnsafeValue);
      }
      if (unwrapped.type === "TSIntersectionType") {
        return (
          unwrapped.types.every(isUnsafeValue) || unwrapped.types.some(isAny)
        );
      }
      return (
        unwrapped.type === "TSTypeReference" &&
        isWrapper(unwrapped) &&
        wrapperArguments(unwrapped).some(isUnsafeValue)
      );
    };

    const report = (node: ESTree.Node) => {
      context.report({ node, messageId: "unsafeDictionary" });
    };

    return {
      Program(program) {
        shadowed = declaredTypeNames(program);
      },
      TSTypeReference(node) {
        if (typeReferenceName(node) !== "Record" || shadowed.has("Record"))
          return;
        const value = node.typeArguments?.params[1];
        if (value && isUnsafeValue(value)) report(node);
      },
      TSIndexSignature(node) {
        if (isUnsafeValue(node.typeAnnotation.typeAnnotation)) report(node);
      },
      TSMappedType(node) {
        if (node.typeAnnotation && isUnsafeValue(node.typeAnnotation)) {
          report(node);
        }
      },
    };
  },
});
