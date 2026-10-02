import type { ESTree } from "@oxlint/plugins";

import { type Rule, defineRule } from "@oxlint/plugins";

import { unwrapParenthesizedType } from "../shared/type-nodes.ts";

function topLevelAliases(
  program: ESTree.Program,
): ESTree.TSTypeAliasDeclaration[] {
  return program.body.flatMap((statement) => {
    if (statement.type === "TSTypeAliasDeclaration") return [statement];
    if (
      statement.type === "ExportNamedDeclaration" &&
      statement.declaration?.type === "TSTypeAliasDeclaration"
    ) {
      return [statement.declaration];
    }
    return [];
  });
}

/** The alias a bare, non-generic reference names, or `undefined`. */
function bareReferenceName(type: ESTree.TSType): string | undefined {
  const unwrapped = unwrapParenthesizedType(type);
  return unwrapped.type === "TSTypeReference" &&
    unwrapped.typeName.type === "Identifier" &&
    unwrapped.typeArguments === null
    ? unwrapped.typeName.name
    : undefined;
}

/**
 * Ban a top-level type alias that resolves to `unknown`, directly or through
 * a chain of bare aliases. It hides the top type behind a domain-sounding
 * name, so readers believe the value was parsed. Generic aliases are not
 * resolved through.
 */
export const noUnknownTypeAliasesRule: Rule = defineRule({
  meta: {
    type: "problem",
    docs: {
      description:
        "Disallow type aliases that resolve to `unknown`; keep `unknown` visible at the parsing boundary.",
    },
    messages: {
      unknownAlias:
        "This type alias hides `unknown`. Keep `unknown` explicit at the parsing boundary or on an allowed `cause` field; otherwise use the parsed owner type.",
    },
  },
  createOnce(context) {
    return {
      Program(program) {
        const aliases = topLevelAliases(program);
        const plain = new Map<string, ESTree.TSType>();
        for (const alias of aliases) {
          if (alias.typeParameters === null) {
            plain.set(alias.id.name, alias.typeAnnotation);
          }
        }

        const resolvesToUnknown = (type: ESTree.TSType): boolean => {
          const seen = new Set<string>();
          let current: ESTree.TSType | undefined = type;
          while (current) {
            if (unwrapParenthesizedType(current).type === "TSUnknownKeyword") {
              return true;
            }
            const name = bareReferenceName(current);
            if (name === undefined || seen.has(name)) return false;
            seen.add(name);
            current = plain.get(name);
          }
          return false;
        };

        for (const alias of aliases) {
          if (resolvesToUnknown(alias.typeAnnotation)) {
            context.report({ node: alias, messageId: "unknownAlias" });
          }
        }
      },
    };
  },
});
