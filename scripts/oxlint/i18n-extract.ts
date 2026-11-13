/**
 * Oxlint JS plugin for apps that extract messages with next-intl's
 * `useExtracted` and `getExtracted` (EX-1602). The extractor reads a `t(...)`
 * call only when `t` comes from one of them in the same file, so a helper that
 * takes the translator as a parameter ships labels that read `MISSING_MESSAGE`.
 * Build the labels in the component, or return keys and translate them there.
 */
const TRANSLATORS = new Set(["t"]);

interface AstNode {
  readonly type: string;
}

interface IdentifierNode extends AstNode {
  readonly type: "Identifier";
  readonly name: string;
}

interface PropertyNode extends AstNode {
  readonly type: "Property";
  readonly value: AstNode;
}

interface AssignmentNode extends AstNode {
  readonly type: "AssignmentPattern";
  readonly left: AstNode;
}

interface ObjectPatternNode extends AstNode {
  readonly type: "ObjectPattern";
  readonly properties: readonly AstNode[];
}

interface FunctionNode extends AstNode {
  readonly params: readonly AstNode[];
}

interface Context {
  report(problem: { node: AstNode; message: string }): void;
}

const MESSAGE =
  "The translator is a parameter here, so the message extractor skips its t(...) calls and the labels read MISSING_MESSAGE. Call useExtracted() or getExtracted() in this file, or return keys and translate them in the component (EX-1602).";

const isIdentifier = (node: AstNode): node is IdentifierNode =>
  node.type === "Identifier";

const isProperty = (node: AstNode): node is PropertyNode =>
  node.type === "Property";

const isAssignment = (node: AstNode): node is AssignmentNode =>
  node.type === "AssignmentPattern";

const isObjectPattern = (node: AstNode): node is ObjectPatternNode =>
  node.type === "ObjectPattern";

/** The identifiers a parameter binds: `t`, `{ t }`, `t = x` or `{ t: t }`. */
function bound(node: AstNode): readonly IdentifierNode[] {
  if (isIdentifier(node)) {
    return [node];
  }

  if (isAssignment(node)) {
    return bound(node.left);
  }

  if (isObjectPattern(node)) {
    return node.properties.flatMap((property) =>
      isProperty(property) ? bound(property.value) : [],
    );
  }

  return [];
}

function checkParams(context: Context, node: FunctionNode): void {
  for (const identifier of node.params.flatMap(bound)) {
    if (TRANSLATORS.has(identifier.name)) {
      context.report({ node: identifier, message: MESSAGE });
    }
  }
}

export default {
  meta: { name: "i18n-extract" },
  rules: {
    "no-translator-parameter": {
      create(context: Context) {
        const visit = (node: FunctionNode): void => {
          checkParams(context, node);
        };

        return {
          FunctionDeclaration: visit,
          FunctionExpression: visit,
          ArrowFunctionExpression: visit,
        };
      },
    },
  },
};
