import { describe, expect, it } from "vitest";

import type { BlockScope } from "../../src/config/blocks.ts";
import type { BlockSqlLayout } from "../../src/sql/module-types.ts";

import { BLOCK_SCOPES } from "../../src/config/blocks.ts";
import { SQL_MODULES } from "../../src/sql/registry.ts";
import { renderBlocks } from "../../src/sql/render.ts";

// What a convention (`sql.scope`, `blocks.memberships.entities`) changes in
// each module's SQL, as properties of the rendered text. The default output
// is pinned in render-golden.test.ts.

const TENANT_POLICY = "bsb_tenant_scope_";

const HELPER = {
  organization: "member_organization_ids",
  workspace: "member_workspace_ids",
};

const count = (text: string, part: string): number =>
  text.split(part).length - 1;

const NAMES = Object.keys(SQL_MODULES);

interface Convention {
  readonly name: string;
  readonly applies: (module: string) => boolean;
  readonly layout: BlockSqlLayout;
  readonly check: (variant: string, base: string, module: string) => void;
}

const runsIn = (module: string, scope: BlockScope): boolean =>
  (SQL_MODULES[module]?.scopes ?? BLOCK_SCOPES).includes(scope);

const CONVENTIONS: readonly Convention[] = [
  {
    name: "scope-user",
    applies: (module) => runsIn(module, "user"),
    layout: { scope: "user" },
    check: (variant) => {
      expect(variant).not.toContain(TENANT_POLICY);
    },
  },
  {
    name: "scope-none",
    applies: (module) => runsIn(module, "none"),
    layout: { scope: "none" },
    check: (variant) => {
      expect(variant).not.toContain(TENANT_POLICY);
    },
  },
  {
    name: "naming-workspace",
    applies: () => true,
    layout: {
      modules: { memberships: { entities: { organization: "workspace" } } },
    },
    // memberships defines the helper itself and keeps two legacy names.
    check: (variant, base, module) => {
      if (module === "memberships") {
        return;
      }

      expect(variant).not.toContain(HELPER.organization);
      expect(count(variant, HELPER.workspace)).toBe(
        count(base, HELPER.organization),
      );
    },
  },
];

function render(module: string, layout: BlockSqlLayout): string {
  let files;

  try {
    files = renderBlocks([module], layout);
  } catch (cause) {
    return `-- ==== throws\n-- ${cause instanceof Error ? cause.message : String(cause)}\n`;
  }

  return files
    .filter((file) => file.module === module)
    .map((file) => `-- ==== ${file.kind} ${file.path}\n${file.contents}`)
    .join("\n");
}

describe.each(CONVENTIONS)("SQL module output with $name", (convention) => {
  const changed = NAMES.filter(
    (module) =>
      module !== "pgtap" &&
      convention.applies(module) &&
      render(module, convention.layout) !== render(module, {}),
  );

  it("changes the SQL of at least one module", () => {
    expect(changed.length).toBeGreaterThan(0);
  });

  it.each(changed)("%s follows the convention", (module) => {
    const variant = render(module, convention.layout);

    expect(variant).not.toContain("-- ==== throws");
    convention.check(variant, render(module, {}), module);
  });
});
