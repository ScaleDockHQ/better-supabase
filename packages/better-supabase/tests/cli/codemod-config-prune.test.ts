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

describe("codemod config --prune numbering entries", () => {
  const NUMBERING = `export default {
  blocks: [
    {
      block: "numbering",
      options: {
        entities: {
          widget: { format: "{n}", period: "none", table: "public.widgets", column: "number" },
          ticket: { format: "T-{n}", period: "none", table: "public.tickets", column: "number" },
        },
      },
    },
  ],
};
`;

  it("removes format, period and column that equal the defaults and keeps the rest", async () => {
    const root = mkdtempSync(join(tmpdir(), "bsb-prune-num-"));

    mkdirSync(join(root, "supabase"), { recursive: true });

    const file = join(root, "better-supabase.config.ts");

    writeFileSync(file, NUMBERING);

    const config = resolveConfig(
      {
        blocks: {
          numbering: {
            options: {
              entities: {
                widget: {
                  format: "{n}",
                  period: "none",
                  table: "public.widgets",
                  column: "number",
                },
                ticket: {
                  format: "T-{n}",
                  period: "none",
                  table: "public.tickets",
                  column: "number",
                },
              },
            },
          },
        },
      },
      root,
    );

    await runCodemod(config, { _: ["config"], prune: true }, undefined, file);

    const text = readFileSync(file, "utf-8");

    expect(text).not.toContain('format: "{n}"');
    expect(text).toContain('format: "T-{n}"');
    expect(text).not.toContain('column: "number"');
    expect(text).not.toContain('period: "none"');
  });
});

describe("codemod config --prune sql.api", () => {
  const API = `export default {
  blocks: [
    { block: "tags", api: "api" },
    { block: "comments", api: { schema: "api" } },
    { block: "reactions", api: "api" },
    { block: "tasks" },
  ],
};
`;

  function apiProject(text: string): {
    file: string;
    config: ReturnType<typeof resolveConfig>;
  } {
    const root = mkdtempSync(join(tmpdir(), "bsb-prune-api-"));

    mkdirSync(join(root, "supabase"), { recursive: true });

    const file = join(root, "better-supabase.config.ts");

    writeFileSync(file, text);

    return {
      file,
      config: resolveConfig(
        {
          blocks: {
            tags: { api: "api" },
            comments: { api: { schema: "api" } },
            reactions: { api: "api" },
            tasks: {},
          },
        },
        root,
      ),
    };
  }

  it("sets sql.api, drops the repeated entries and turns off the block without one", async () => {
    const { config, file } = apiProject(API);

    await runCodemod(config, { _: ["config"], prune: true }, undefined, file);

    const text = readFileSync(file, "utf-8");

    expect(text).toMatch(/database:\s*\{\s*sql:\s*\{\s*api: "api"/);
    expect(text).not.toContain('api: "api" }');
    expect(text).toMatch(/block: "tasks",\s*api: false/);
  });

  it("writes nothing with --check", async () => {
    const { config, file } = apiProject(API);

    await runCodemod(
      config,
      { _: ["config"], prune: true, check: true },
      undefined,
      file,
    );

    expect(readFileSync(file, "utf-8")).toBe(API);
  });
});
