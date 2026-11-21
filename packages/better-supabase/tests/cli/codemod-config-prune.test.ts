import { mkdirSync, mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { describe, expect, it } from "vitest";

import { runCodemod } from "../../src/cli/commands/codemod.ts";
import { resolveConfig } from "../../src/config/index.ts";

const TEXT = `export default {
  blocks: [
    { block: "tags", columns: { tags: {} } },
    { block: "memberships", columns: { memberships: { role: "team_role" } } },
  ],
};
`;

function project(): {
  root: string;
  file: string;
  config: ReturnType<typeof resolveConfig>;
} {
  const root = mkdtempSync(join(tmpdir(), "bsb-prune-"));

  mkdirSync(join(root, "supabase"), { recursive: true });

  const file = join(root, "better-supabase.config.ts");

  writeFileSync(file, TEXT);

  return {
    root,
    file,
    config: resolveConfig(
      {
        blocks: {
          tags: { columns: { tags: {} } },
          memberships: { columns: { memberships: { role: "team_role" } } },
        },
      },
      root,
    ),
  };
}

describe("codemod config --prune", () => {
  it("removes an entry whose removal leaves the render unchanged", async () => {
    const { config, file } = project();

    await runCodemod(config, { _: ["config"], prune: true }, undefined, file);

    const text = readFileSync(file, "utf-8");

    expect(text).not.toContain("columns: { tags");
    expect(text).toMatch(/block: "tags"/);
  });

  it("keeps an entry that differs from its default", async () => {
    const { config, file } = project();

    await runCodemod(config, { _: ["config"], prune: true }, undefined, file);

    expect(readFileSync(file, "utf-8")).toContain('role: "team_role"');
  });

  it("writes nothing with --check", async () => {
    const { config, file } = project();

    await runCodemod(
      config,
      { _: ["config"], prune: true, check: true },
      undefined,
      file,
    );

    expect(readFileSync(file, "utf-8")).toBe(TEXT);
  });
});
