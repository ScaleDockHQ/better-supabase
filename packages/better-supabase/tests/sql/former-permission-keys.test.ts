import { describe, expect, it } from "vitest";

import { namingCodemod } from "../../src/cli/codemod-naming.ts";
import { applyCodemod } from "../../src/cli/codemod.ts";
import { renderBlocks } from "../../src/sql/render.ts";

describe("former permission keys", () => {
  it("refuses an old action key and names the new one", () => {
    expect(() =>
      renderBlocks(["audit"], {
        modules: { audit: { permissions: { view: "audit.view" } } },
      }),
    ).toThrow(/permissions\.view: renamed to "read".*codemod naming/su);
  });

  it("accepts the new key", () => {
    expect(() =>
      renderBlocks(["audit"], {
        modules: { audit: { permissions: { read: "audit.read" } } },
      }),
    ).not.toThrow();
  });

  it("renames the keys in the config with codemod naming", () => {
    const { text } = applyCodemod(
      namingCodemod(),
      `import { defineConfig } from "better-supabase/config";
export default defineConfig({
  blocks: {
    audit: { permissions: { view: "a.view", viewAll: "a.all" } },
    "webhooks-out": { permissions: { view: "w.view" } },
    tasks: { permissions: { view: "keep" } },
  },
});
`,
    );

    expect(text).toContain(
      'audit: { permissions: { read: "a.view", readAll: "a.all" } }',
    );
    expect(text).toContain(
      '"webhooks-out": { permissions: { read: "w.view" } }',
    );
    expect(text).toContain('tasks: { permissions: { view: "keep" } }');
  });
});

describe("the removed uniqueNumber option", () => {
  it("is refused with a way out", () => {
    expect(() =>
      renderBlocks(["invoices"], {
        modules: { invoices: { options: { uniqueNumber: true } } },
      }),
    ).toThrow(/uniqueNumber was removed.*distinct `identifier`/su);
  });
});
