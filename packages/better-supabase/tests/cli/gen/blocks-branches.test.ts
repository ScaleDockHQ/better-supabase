import { describe, expect, it } from "vitest";

import {
  blockConfigEntries,
  schemaExtensions,
} from "../../../src/cli/gen/blocks.ts";
import { resolveConfig } from "../../../src/config/resolve.ts";

describe("schemaExtensions arguments", () => {
  it("passes the tenant options to the memberships extension", () => {
    const config = resolveConfig({ blocks: ["memberships"] }, "/project");

    const extensions = schemaExtensions({
      blockNames: config.blockNames,
      extensions: {
        ...config.extensions,
        tenant: { column: "org", onMissing: "skip", header: "x-org" },
      },
    });

    expect(extensions).toContainEqual({
      export: expect.stringContaining("embership"),
      subpath: "blocks/memberships",
      args: '{ onMissing: "skip", header: "x-org" }',
    });
  });

  it("gives the memberships extension no argument without tenant options", () => {
    const config = resolveConfig({ blocks: ["memberships"] }, "/project");

    expect(
      schemaExtensions({
        blockNames: config.blockNames,
        extensions: { ...config.extensions, tenant: undefined },
      }).find((each) => each.subpath === "blocks/memberships")?.args,
    ).toBe("");
  });

  it("falls back to the client stamp when the config carries no blocks", () => {
    const config = resolveConfig({ blocks: { "updated-at": {} } }, "/project");

    expect(
      schemaExtensions({
        blockNames: config.blockNames,
        extensions: config.extensions,
      }),
    ).toEqual([
      expect.objectContaining({ subpath: "blocks/updated-at", args: "" }),
    ]);
  });
});

describe("tenant column of a block's tables", () => {
  it("ignores a table the block turns off and a column it maps to null", () => {
    const off = blockConfigEntries(
      resolveConfig(
        {
          blocks: { quotes: { tables: { taxLines: null } } },
          database: { sql: { tenantColumn: "organization_id" } },
        },
        "/project",
      ),
    );

    expect(off["quotes"]?.names?.tenantColumn).toBe("organization_id");

    const nulled = blockConfigEntries(
      resolveConfig(
        { blocks: { quotes: { columns: { taxLines: { tenant: null } } } } },
        "/project",
      ),
    );

    expect(nulled["quotes"]).toBeDefined();
  });

  it("keeps the default when the tenant columns disagree", () => {
    const entries = blockConfigEntries(
      resolveConfig(
        {
          blocks: {
            quotes: {
              columns: {
                quotes: { tenant: "org_id" },
                lines: { tenant: "team_id" },
              },
            },
          },
        },
        "/project",
      ),
    );

    expect(entries["quotes"]?.names?.tenantColumn).toBeUndefined();
  });
});
