import { describe, expect, it } from "vitest";

import { blocksList } from "../../src/cli/codemod-blocks-list.ts";

const wrap = (blocks: string): string =>
  `import { defineConfig } from "better-supabase";\n\nexport default defineConfig({\n  preset: "saas",\n  blocks: ${blocks},\n});\n`;

describe("blocks-list codemod", () => {
  it("leaves a source file that is not a config alone, even one that is not valid TypeScript", () => {
    const jsx = 'export const View = () => <div className="a">x</div>;\n';

    expect(blocksList(jsx).text).toBe(jsx);
  });

  it("turns empty entries into names and configured ones into objects", () => {
    const out = blocksList(
      wrap(`{
    tenant: {},
    numbering: {
      options: { format: "{n}" },
    },
    labels: { block: "tags", on: ["task"] },
  }`),
    );

    expect(out.review).toEqual([]);
    expect(out.text).toContain('"tenant",');
    expect(out.text).toContain('{\n      block: "numbering",\n      options');
    expect(out.text).toContain('{ name: "labels", block: "tags"');
    expect(out.text).not.toContain("tenant: {}");
    expect(out.text).toContain("blocks: [");
  });

  it("keeps comments and leaves a list alone", () => {
    const kept = blocksList(wrap(`{\n    // the base\n    tenant: {},\n  }`));

    expect(kept.text).toContain("// the base");
    expect(blocksList(wrap(`["tenant"]`)).text).toBe(wrap(`["tenant"]`));
  });

  it("reports a spread instead of guessing", () => {
    const input = wrap(`{ ...shared, tenant: {} }`);
    const out = blocksList(input);

    expect(out.text).toBe(input);
    expect(out.review).toHaveLength(1);
  });
});
