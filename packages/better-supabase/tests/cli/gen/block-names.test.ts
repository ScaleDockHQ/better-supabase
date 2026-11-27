import { describe, expect, it } from "vitest";

import { nameConstantLines } from "../../../src/cli/gen/block-names.ts";
import { blockConfigEntries } from "../../../src/cli/gen/blocks.ts";
import { resolveConfig } from "../../../src/config/index.ts";

type Config = Parameters<typeof nameConstantLines>[0];

type Entries = Parameters<typeof nameConstantLines>[1];

describe("nameConstantLines", () => {
  it("writes bucket paths as functions and escapes template characters", () => {
    const config = {
      ...resolveConfig({}, "/project"),
      buckets: {
        "user-files": { path: ["a`b/{id}", "c\\d/{id}/{id}"] },
        plain: { path: "fixed/name" },
      },
    } as unknown as Config;

    const { lines } = nameConstantLines(config, {});

    const userFiles = lines.find((line) => line.startsWith("  userFiles:"));

    expect(userFiles).toMatch(
      /^ {2}userFiles: \[\(v: \{ readonly id: string \}\) => `a\\`b\/\$\{String\(v\.id\)\}`, /u,
    );
    expect(userFiles).toMatch(
      /`c\\\\d\/\$\{String\(v\.id\)\}\/\$\{String\(v\.id\)\}`\],$/u,
    );
    expect(lines).toContain('  plain: () => "fixed/name",');
  });

  it("writes no role constants when permissions use another model", () => {
    const config = {
      ...resolveConfig({}, "/project"),
      blocks: { permissions: { model: "provider" } },
    } as unknown as Config;

    const { lines } = nameConstantLines(config, {
      permissions: { options: {} },
    } as unknown as Entries);

    expect(lines.some((line) => line.includes("roles"))).toBe(false);
  });

  it("names a renamed instance's events type in PascalCase", () => {
    const config = resolveConfig(
      {
        blocks: {
          tasks: {},
          "support-tickets": {
            block: "tasks",
            entities: { task: "ticket", project: "support_project" },
          },
        },
      },
      "/project",
    );

    const { lines } = nameConstantLines(config, blockConfigEntries(config));

    expect(lines).toContainEqual(
      expect.stringMatching(
        /^export type BlockEvents = .*SupportTicketsEvents/u,
      ),
    );
  });
});
