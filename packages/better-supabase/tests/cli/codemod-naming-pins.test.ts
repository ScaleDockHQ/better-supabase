import { describe, expect, it } from "vitest";

import {
  columnPins,
  renameSqlColumns,
  withColumnPins,
  withHistoryPins,
} from "../../src/cli/codemod-naming-pins.ts";
import { NAMING_RENAMES } from "../../src/cli/codemod-naming.ts";

const driveTable = { "public.drive_nodes": "table" } as const;
const drive = { tables: { nodes: "public.drive_nodes" } };

describe("columnPins", () => {
  it("pins the old name of a column an app table of the block still has", () => {
    const pins = columnPins({ blocks: { drive } }, NAMING_RENAMES, driveTable, {
      "public.drive_nodes": ["id", "tenant_id", "deleted_at"],
    });

    expect(pins.pins).toContainEqual({
      block: "drive",
      module: "drive",
      table: "nodes",
      column: "deletedAt",
      name: "deleted_at",
      physical: "public.drive_nodes",
    });
    expect(pins.review).toEqual([]);
  });

  it("pins nothing for a table that has the new name or sets the column", () => {
    expect(
      columnPins({ blocks: { drive } }, NAMING_RENAMES, driveTable, {
        "public.drive_nodes": ["archived_at"],
      }).pins,
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
      ).pins,
    ).toEqual([]);
  });

  it("pins a state-machine history actor and a hiring scorecard column", () => {
    const history = columnPins(
      {
        blocks: {
          "state-machine": {
            options: {
              machines: {
                quote: { history: { table: "public.quote_history" } },
              },
            },
          },
        },
      },
      NAMING_RENAMES,
      {},
      { "public.quote_history": ["id", "actor_user_id"] },
    );

    expect(history.history).toEqual([
      { block: "state-machine", machine: "quote", actor: "actor_user_id" },
    ]);

    const scorecards = columnPins(
      {
        blocks: {
          hiring: { tables: { scorecards: "public.application_scorecards" } },
        },
      },
      NAMING_RENAMES,
      { "public.application_scorecards": "app.sql" },
      { "public.application_scorecards": ["id", "reviewer_user_id"] },
    );

    expect(scorecards.pins).toContainEqual({
      block: "hiring",
      module: "hiring",
      table: "scorecards",
      column: "reviewer",
      name: "reviewer_user_id",
      physical: "public.application_scorecards",
    });
  });

  it("reports a block whose context refuses the config", () => {
    const report = columnPins(
      { blocks: { drive: { tables: { notATable: "public.x" } } } },
      NAMING_RENAMES,
      {},
      {},
    );

    expect(report.pins).toEqual([]);
    expect(report.review[0]).toContain("blocks.drive");
    expect(report.review[0]).toContain(
      "Column pins for this block were left out",
    );
  });
});

describe("withColumnPins", () => {
  const pin = {
    block: "drive",
    module: "drive",
    table: "nodes",
    column: "deletedAt",
    name: "deleted_at",
    physical: "public.drive_nodes",
  };

  it("adds the pin to an existing columns object, a table or a block", () => {
    const withTable = withColumnPins(
      'export default { blocks: { drive: { columns: { nodes: { name: "title" } } } } };',
      [pin],
    );

    expect(withTable.text).toContain('deletedAt: "deleted_at"');
    expect(withTable.missed).toEqual([]);

    expect(
      withColumnPins(
        "export default { blocks: { drive: { columns: { other: {} } } } };",
        [pin],
      ).text,
    ).toContain('deletedAt: "deleted_at"');

    expect(
      withColumnPins("export default { blocks: { drive: {} } };", [pin]).text,
    ).toContain('deletedAt: "deleted_at"');
  });

  it("writes the pin inside blocks, at the next line's indent", () => {
    const text = withColumnPins(
      `export default {
  blocks: {
    drive: {
      tables: {},
    },
  },
  const drive = { deletedAt: "keep" };
};
`,
      [pin],
    ).text;

    expect(text).toContain('          deletedAt: "deleted_at",');
    expect(text).toContain('const drive = { deletedAt: "keep" }');
  });

  it("writes a history actor pin on its own line", () => {
    const text = withHistoryPins(
      `export default {
  blocks: {
    "state-machine": {
      options: {
        machines: {
          quote: {
            history: {
              table: "public.quote_history",
            },
          },
        },
      },
    },
  },
};
`,
      [{ block: "state-machine", machine: "quote", actor: "actor_user_id" }],
    ).text;

    expect(text).toContain('actor: "actor_user_id"');
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

  it("renames a qualified column, an audit list and not a value or a dollar body", () => {
    const qualified = renameSqlColumns(
      "select n.deleted_at from better_supabase.drive_nodes n;\nupdate better_supabase.drive_nodes set name = deleted_at;\nselect better_supabase.audit('better_supabase.drive_nodes', ignore => '{deleted_at, id}');\n",
      NAMING_RENAMES,
    );

    expect(qualified).toContain("n.archived_at");
    expect(qualified).toContain("set name = deleted_at");
    expect(qualified).toContain("'{archived_at, id}'");

    const body =
      "do $$ begin update better_supabase.drive_nodes set deleted_at = now(); end $$;\n";

    expect(renameSqlColumns(body, NAMING_RENAMES)).toBe(body);
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
