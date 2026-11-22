import { describe, expect, it } from "vitest";

import { mergeRestated, probeRestated } from "../../src/cli/restated-probe.ts";
import { resolveConfig } from "../../src/config/index.ts";

const config = (claimFormat: string) =>
  resolveConfig(
    { blocks: { memberships: { options: { claimFormat } }, tags: {} } },
    "/project",
  );

describe("probeRestated", () => {
  it("reports an option equal to its default", async () => {
    const entries = await probeRestated(config("array"));

    expect(entries.map((entry) => entry.path)).toContain(
      "blocks.memberships.options.claimFormat",
    );
  });

  it("keeps an option that changes the render", async () => {
    const entries = await probeRestated(config("map"));

    expect(entries.map((entry) => entry.path)).not.toContain(
      "blocks.memberships.options.claimFormat",
    );
  });

  it("stops at once when the budget is spent", async () => {
    expect(await probeRestated(config("array"), { budgetMs: -1 })).toEqual([]);
  });

  it("keeps sameTenant entries the render needs", async () => {
    const entries = await probeRestated(
      resolveConfig(
        {
          blocks: {
            memberships: {
              options: {
                sameTenant: [
                  {
                    table: "tasks",
                    column: "project_id",
                    references: "projects",
                  },
                  { table: "notes", column: "task_id", references: "tasks" },
                ],
              },
            },
          },
        },
        "/project",
      ),
    );

    expect(entries.some((entry) => entry.path.includes("sameTenant"))).toBe(
      false,
    );
  });
});

describe("mergeRestated", () => {
  it("keeps structural entries and drops probed ones on the same path", () => {
    const entry = (path: string, reason: string) => ({
      kind: "option" as const,
      path,
      reason,
      value: undefined,
    });

    expect(
      mergeRestated(
        [entry("a", "structural")],
        [entry("a", "probed"), entry("b", "probed")],
      ),
    ).toEqual([entry("a", "structural"), entry("b", "probed")]);
  });
});
