import { describe, expect, it } from "vitest";

import type { Executor } from "../../../src/core/executor.ts";
import type { InsertOp, Operation, SelectOp } from "../../../src/ir/types.ts";
import type { SchemaMeta } from "../../../src/schema/types.ts";

import { membershipsExtension } from "../../../src/blocks/memberships/index.ts";
import { defineSupabase } from "../../../src/core/define.ts";
import { ok } from "../../../src/core/result.ts";
import { defineSchema } from "../../../src/schema/define.ts";

/**
 * The app's own `client_rows` table that a `tables.<name>` entry enriched, or a
 * block adopted: its tenant column is the app's `company_id`, nullable while a
 * backfill fills the rows it had before.
 */
const meta: SchemaMeta = {
  version: 1,
  casing: "camel",
  enums: {},
  functions: {},
  tables: {
    clientRows: {
      key: "clientRows",
      name: "client_rows",
      schema: "public",
      kind: "table",
      columns: {
        id: { db: "id", type: "uuid", nullable: false, hasDefault: true },
        companyId: {
          db: "company_id",
          type: "uuid",
          nullable: true,
          hasDefault: false,
        },
        name: { db: "name", type: "text", nullable: false, hasDefault: false },
      },
      primaryKey: ["id"],
      uniqueKeys: {},
      relations: {},
      flags: { tenant: "companyId" },
    },
  },
};

interface ClientRows {
  list(args: object): { orThrow(): Promise<unknown> };
  create(row: object): { orThrow(): Promise<unknown> };
}

function connect() {
  const ops: Operation[] = [];

  const executor: Executor = {
    name: "recording",
    async execute(op) {
      ops.push(op);

      return ok({ rows: [], count: null });
    },
  };

  // SAFETY: the meta above declares `clientRows` with these methods.
  const db = defineSupabase(defineSchema(meta))
    .use(membershipsExtension())
    .connect(executor, { claims: { tenant_id: "org-1" } }) as unknown as {
    clientRows: ClientRows;
  };

  return { db, ops };
}

describe("membershipsExtension over the app's own table", () => {
  it("filters reads on the tenant column the table's flags name", async () => {
    const { db, ops } = connect();

    await db.clientRows.list({}).orThrow();

    expect(JSON.stringify((ops[0] as SelectOp).where)).toContain(
      '"column":"company_id"',
    );
    expect(JSON.stringify((ops[0] as SelectOp).where)).toContain('"org-1"');
  });

  it("fills the tenant column on insert, though the database lets it be null", async () => {
    const { db, ops } = connect();

    await db.clientRows.create({ name: "Acme" }).orThrow();

    expect((ops[0] as InsertOp).rows[0]).toMatchObject({
      name: "Acme",
      company_id: "org-1",
    });
  });
});
