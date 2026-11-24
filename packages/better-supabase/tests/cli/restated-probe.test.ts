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

describe("probeRestated on sameTenant elements", () => {
  it("reports a repeated sameTenant element by its index", async () => {
    const entry = {
      table: "tasks",
      column: "project_id",
      references: "projects",
    };

    const entries = await probeRestated(
      resolveConfig(
        {
          blocks: { memberships: { options: { sameTenant: [entry, entry] } } },
        },
        "/project",
      ),
    );

    expect(entries.map((each) => [each.path, each.reason])).toEqual([
      [
        "blocks.memberships.options.sameTenant[0]",
        "equals the entry the block derives from the schema",
      ],
      [
        "blocks.memberships.options.sameTenant[1]",
        "equals the entry the block derives from the schema",
      ],
    ]);
  });
});

describe("probeRestated by kind", () => {
  it.each([
    [
      {
        blocks: { invitations: { permissions: { invite: "members.invite" } } },
      },
      [
        [
          "permission",
          "blocks.invitations.permissions.invite",
          "names the key the block would use anyway",
        ],
      ],
    ],
    [
      { blocks: { tags: { api: false } } },
      [
        [
          "api",
          "blocks.tags.api",
          "equals the exposure the block gets without it",
        ],
      ],
    ],
    [
      {
        blocks: { tags: { api: "api" }, memberships: { api: "api" } },
        sql: { api: "api" },
      },
      [],
    ],
    [
      {
        recordTypes: {
          task: { table: "public.tasks", idType: "uuid", cascade: true },
        },
        blocks: { tags: { on: { task: {} } } },
      },
      [
        [
          "recordType",
          "recordTypes.task.cascade",
          "is the value the block derives without it",
        ],
      ],
    ],
    [
      {
        blocks: {
          memberships: {
            tables: { memberships: "better_supabase.memberships" },
            hooks: { schema: "public" },
            columns: {
              memberships: {
                tenant: "organization_id",
                user: "member_id",
                role: "team_role",
                lastUsedAt: null,
              },
            },
          },
        },
      },
      [
        [
          "hook",
          "blocks.memberships.callbacks.schema",
          "names the hook function the block looks up anyway",
        ],
        [
          "table",
          "blocks.memberships.tables.memberships",
          "names the table or column the catalog gives without it",
        ],
        [
          "column",
          "blocks.memberships.columns.memberships.tenant",
          "names the table or column the catalog gives without it",
        ],
      ],
    ],
  ])("reports %j", async (input, expected) => {
    const entries = await probeRestated(
      resolveConfig(input as never, "/project"),
    );

    expect(
      entries.map((entry) => [entry.kind, entry.path, entry.reason]),
    ).toEqual(expected);
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

  it("keeps an identity mapping only when the probe renders the same files without it", () => {
    const identity = (path: string) => ({
      kind: "identity" as const,
      path,
      reason: "names the default column",
      value: "last_used_at",
    });

    const column = (path: string) => ({
      kind: "column" as const,
      path,
      reason: "names the table or column the catalog gives without it",
      value: undefined,
    });

    const same = "blocks.memberships.columns.memberships.lastUsedAt";
    const changes = "blocks.memberships.columns.memberships.disabledAt";

    expect(
      mergeRestated([identity(same), identity(changes)], [column(same)]),
    ).toEqual([identity(same)]);
  });

  it("writes hook paths under callbacks, the key the config file uses", async () => {
    const entries = await probeRestated(
      resolveConfig(
        {
          blocks: {
            organizations: {
              callbacks: {
                functions: {
                  after_organization_create: "after_organization_create",
                },
              },
            },
          },
        },
        "/project",
      ),
    );

    expect(entries.map((entry) => entry.path)).toContain(
      "blocks.organizations.callbacks.functions.after_organization_create",
    );
  });
});
