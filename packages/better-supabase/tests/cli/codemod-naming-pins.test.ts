import { describe, expect, it } from "vitest";

import {
  columnPins,
  renameSqlColumns,
  withColumnPins,
} from "../../src/cli/codemod-naming-pins.ts";
import { NAMING_RENAMES } from "../../src/cli/codemod-naming.ts";

const driveTable = { "public.drive_nodes": "table" } as const;
const drive = { tables: { nodes: "public.drive_nodes" } };

describe("columnPins", () => {
  it("pins the old name of a column an app table of the block still has", () => {
    const pins = columnPins({ blocks: { drive } }, NAMING_RENAMES, driveTable, {
      "public.drive_nodes": ["id", "tenant_id", "deleted_at"],
    });

    expect(pins).toContainEqual({
      block: "drive",
      table: "nodes",
      column: "deletedAt",
      name: "deleted_at",
    });
  });

  it("pins nothing for a table that has the new name or sets the column", () => {
    expect(
      columnPins({ blocks: { drive } }, NAMING_RENAMES, driveTable, {
        "public.drive_nodes": ["archived_at"],
      }),
    ).toEqual([]);

    expect(
      columnPins(
        {
          blocks: {
            drive: {
              ...drive,
              columns: { nodes: { deletedAt: "deleted_at" } },
            },
          },
        },
        NAMING_RENAMES,
        driveTable,
        { "public.drive_nodes": ["deleted_at"] },
      ),
    ).toEqual([]);
  });
});

describe("withColumnPins", () => {
  const pin = {
    block: "drive",
    table: "nodes",
    column: "deletedAt",
    name: "deleted_at",
  };

  it("adds the pin to an existing columns object, a table or a block", () => {
    const withTable = withColumnPins(
      'export default { blocks: { drive: { columns: { nodes: { name: "title" } } } } };',
      [pin],
    );

    expect(withTable.text).toContain('nodes: { deletedAt: "deleted_at",');
    expect(withTable.missed).toEqual([]);

    expect(
      withColumnPins(
        "export default { blocks: { drive: { columns: { other: {} } } } };",
        [pin],
      ).text,
    ).toContain('columns: { nodes: { deletedAt: "deleted_at" },');

    expect(
      withColumnPins("export default { blocks: { drive: {} } };", [pin]).text,
    ).toContain('drive: { columns: { nodes: { deletedAt: "deleted_at" } },');
  });

  it("reports a pin whose block it can't find", () => {
    expect(
      withColumnPins("export default { blocks: { drive: true } };", [pin])
        .missed,
    ).toEqual([pin]);
  });
});

describe("renameSqlColumns", () => {
  it("renames the columns of a better_supabase table in a seed", () => {
    const out = renameSqlColumns(
      "insert into better_supabase.drive_nodes (id, deleted_at) values (1, null);\nupdate better_supabase.drive_nodes set deleted_at = now() where id = 1;\n",
      NAMING_RENAMES,
    );

    expect(out).not.toContain("deleted_at");
    expect(out).toContain("(id, archived_at)");
    expect(out).toContain("set archived_at = now()");
  });

  it("leaves the app's own tables, string literals and tenant columns alone", () => {
    const own = "update public.documents set deleted_at = now();\n";
    expect(renameSqlColumns(own, NAMING_RENAMES)).toBe(own);

    const literal =
      "insert into better_supabase.drive_nodes (name) values ('deleted_at');\n";

    expect(renameSqlColumns(literal, NAMING_RENAMES)).toBe(literal);

    expect(
      renameSqlColumns(
        "update better_supabase.drive_nodes set deleted_at = now();\n",
        NAMING_RENAMES,
        new Set(["deleted_at"]),
      ),
    ).toContain("deleted_at");
  });
});
