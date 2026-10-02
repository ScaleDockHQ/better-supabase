import type { ESTree } from "@oxlint/plugins";

import { type Rule, defineRule } from "@oxlint/plugins";

const shapePattern = /shape/iu;

/**
 * Ban "shape" in identifiers. It names a symbol after its structure instead
 * of its domain role. Strings, comments and JSX text are not checked.
 */
export const noShapeInSymbolNamesRule: Rule = defineRule({
  meta: {
    type: "problem",
    docs: {
      description:
        "Disallow 'shape' in symbol names; name the symbol for its domain role.",
    },
    messages: {
      shapeName:
        "Rename `{{name}}` for its domain role; 'shape' describes structure rather than ownership.",
    },
  },
  createOnce(context) {
    const check = (node: ESTree.Node & { readonly name: string }) => {
      if (!shapePattern.test(node.name)) return;
      context.report({
        node,
        messageId: "shapeName",
        data: { name: node.name },
      });
    };
    return {
      Identifier: check,
      PrivateIdentifier: check,
      JSXIdentifier: check,
    };
  },
});
