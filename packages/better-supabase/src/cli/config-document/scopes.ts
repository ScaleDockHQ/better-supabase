import type { Node, Program } from "oxc-parser";

import { ScopeTracker, isReferenceIdentifier, walk } from "oxc-walker";

/**
 * The names of top-level bindings the module uses: a reference that the scope
 * tracker resolves to the root scope, an `export { name }` and a type
 * reference. A shadowing local is not a use of the top-level name.
 */
export function referencedBindings(program: Program): ReadonlySet<string> {
  const used = new Set<string>();
  const scopeTracker = new ScopeTracker();

  walk(program, {
    scopeTracker,
    enter(node: Node, parent: Node | null): void {
      if (node.type === "ExportSpecifier" && node.local.type === "Identifier") {
        used.add(node.local.name);
      }

      if (
        node.type === "Identifier" &&
        parent !== null &&
        isReferenceIdentifier(node, parent)
      ) {
        const declaration = scopeTracker.getDeclaration(node.name, {
          mode: "all",
        });

        if (declaration === null || declaration.scope === "") {
          used.add(node.name);
        }
      }

      if (
        node.type === "ExportDefaultDeclaration" &&
        node.declaration.type === "Identifier"
      ) {
        used.add(node.declaration.name);
      }
    },
  });

  return used;
}
