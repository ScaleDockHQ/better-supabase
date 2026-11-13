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

  it("pins no tenant column that sql.tenantColumn already names", () => {
    const blocks = { outbox: { tables: { events: "public.workflow_events" } } };
    const own = { "public.workflow_events": "table" } as const;

    const columns = {
      "public.workflow_events": ["id", "organization_id", "created_at"],
    };

    expect(
      columnPins({ blocks }, NAMING_RENAMES, own, columns).pins,
    ).toContainEqual(expect.objectContaining({ column: "tenant" }));
    expect(
      columnPins(
        { blocks, sql: { tenantColumn: "organization_id" } },
        NAMING_RENAMES,
        own,
        columns,
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

    const instance = columnPins(
      {
        blocks: {},
        instances: {
          "hiring-eu": {
            name: "hiring-eu",
            block: "hiring",
            uses: {},
            config: { tables: { scorecards: "public.eu_scorecards" } },
          },
        },
      },
      NAMING_RENAMES,
      { "public.eu_scorecards": "app.sql" },
      { "public.eu_scorecards": ["id", "reviewer_user_id"] },
    );

    expect(instance.review).toEqual([]);
    expect(instance.pins).toContainEqual({
      block: "hiring-eu",
      module: "hiring",
      table: "scorecards",
      column: "reviewer",
      name: "reviewer_user_id",
      physical: "public.eu_scorecards",
    });
  });

  it("pins a block whose config still carries options 0.58 removed", () => {
    const report = columnPins(
      {
        blocks: {
          drive: {
            ...drive,
            options: { extraColumns: { label: "text" }, uniqueNumber: false },
          },
          tags: undefined,
        },
        instances: {
          files: {
            name: "files",
            block: "drive",
            config: { ...drive, options: { nodeExtraColumns: {} } },
          },
        },
      } as never,
      NAMING_RENAMES,
      driveTable,
      { "public.drive_nodes": ["id", "tenant_id", "deleted_at"] },
    );

    expect(report.review).toEqual([]);
    expect(report.pins.map((pin) => pin.block)).toEqual(["drive", "files"]);
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

  it("skips a history entry that is not a table, and one that already names an actor", () => {
    const machines = {
      blocks: {
        "state-machine": {
          options: {
            machines: {
              quote: { history: { table: "public.quote_history" } },
              bare: { history: "public.quote_history" },
              numbered: { history: { table: 1 } },
              set: {
                history: { table: "public.quote_history", actor: "actor_id" },
              },
            },
          },
        },
      },
    };

    const columns = { "public.quote_history": ["actor_user_id", "actor_id"] };

    expect(columnPins(machines, NAMING_RENAMES, {}, columns).history).toEqual(
      [],
    );
    expect(
      columnPins(
        { blocks: { "state-machine": { options: { machines: "no" } } } },
        NAMING_RENAMES,
        {},
        columns,
      ).history,
    ).toEqual([]);
    expect(
      columnPins(
        { blocks: { "state-machine": { options: {} } } },
        NAMING_RENAMES,
        {},
        columns,
      ).history,
    ).toEqual([]);
    expect(
      columnPins({ blocks: { missing: {} } }, NAMING_RENAMES, {}, {}).pins,
    ).toEqual([]);

    const missed = withHistoryPins(
      "export default { blocks: { drive: {} } };",
      [{ block: "state-machine", machine: "quote", actor: "actor_user_id" }],
    );

    expect(missed.missed).toHaveLength(1);
    expect(missed.text).not.toContain("actor_user_id");

    const present = withHistoryPins(
      `export default { blocks: { "state-machine": { options: { machines: { quote: { history: { actor: "actor_id" } } } } } } };`,
      [{ block: "state-machine", machine: "quote", actor: "actor_user_id" }],
    );

    expect(present.missed).toEqual([]);
    expect(present.text).toContain('actor: "actor_id"');
    expect(present.text).not.toContain("actor_user_id");

    const around = withColumnPins(
      `const columns = { nodes: {} };
export default { blocks: { drive: { tables: {} } } };
const columns = { nodes: {} };
`,
      [pin],
    );

    expect(around.text).toContain('deletedAt: "deleted_at"');
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

    expect(
      renameSqlColumns(
        "update better_supabase.drive_nodes set deleted_at = now();\n",
        NAMING_RENAMES,
        {
          global: new Set(["tenant_id"]),
          byTable: new Map([
            ["better_supabase.drive_nodes", new Set(["deleted_at"])],
          ]),
        },
      ),
    ).toContain("deleted_at");
  });

  it("leaves a dollar tag, a broken audit call and an unqualified table alone", () => {
    const open =
      "select 1 from better_supabase.drive_nodes; do $$ begin update better_supabase.drive_nodes set deleted_at = now(); end $$;\nselect $;\n";

    const tag = "select $tag$ deleted_at from better_supabase.drive_nodes;\n";

    const renamed = renameSqlColumns(open, NAMING_RENAMES);

    expect(renamed).toContain("do $$");
    expect(renamed).toContain("set deleted_at = now()");
    expect(renameSqlColumns(tag, NAMING_RENAMES)).toContain("$tag$");

    const broken =
      "select better_supabase.audit('better_supabase.drive_nodes' from better_supabase.drive_nodes;\n";

    expect(renameSqlColumns(broken, NAMING_RENAMES)).toContain("audit(");

    const other =
      "select better_supabase.audit('public.other', ignore => '{deleted_at}');\nselect «9» from better_supabase.drive_nodes;\n";

    expect(renameSqlColumns(other, NAMING_RENAMES)).toContain("'{deleted_at}'");
    expect(renameSqlColumns(other, NAMING_RENAMES)).not.toContain("«9»");

    expect(
      renameSqlColumns(
        "update better_supabase.drive_nodes set deleted_at = now();\n",
        [
          {
            kind: "column",
            from: "deleted_at",
            to: "archived_at",
            table: "drive_nodes",
            since: "0.58.0",
          },
        ],
      ),
    ).toContain("deleted_at");
  });
});
