/**
 * Oxlint JS plugin (ADR 0103): block modules emit policies through `policy()`
 * and `renderPolicy()`, never as hand-written `create policy` text.
 */
const PATTERN = /create\s+policy/iu;

interface AstNode {
  readonly type: string;
}

interface Context {
  report(problem: { node: AstNode; message: string }): void;
}

interface StringNode extends AstNode {
  readonly value: string | number | boolean | bigint | RegExp | null;
}

function check(context: Context, node: AstNode, text: string): void {
  // A `-- create policy` line documents a recipe; it is not emitted as a policy.
  const code = text
    .split("\n")
    .filter((line) => !line.trimStart().startsWith("--"));

  if (PATTERN.test(code.join("\n"))) {
    context.report({
      node,
      message:
        "Raw `create policy` in a block module; build a Policy with policy() and render it with renderPolicy() (ADR 0103).",
    });
  }
}

export default {
  meta: { name: "block-policies" },
  rules: {
    "no-raw-policy": {
      create(context: Context) {
        return {
          TemplateElement(node: AstNode & { value: { raw: string } }) {
            check(context, node, node.value.raw);
          },
          Literal(node: StringNode) {
            check(context, node, String(node.value));
          },
        };
      },
    },
  },
};
