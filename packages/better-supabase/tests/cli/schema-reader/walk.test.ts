import { PgParser } from "@supabase/pg-parser";
import { describe, expect, it } from "vitest";

import {
  installedNodeFields,
  pgParserVersion,
} from "../../../scripts/gen-pg-node-fields.ts";
import {
  NODE_FIELDS,
  PG_PARSER_VERSION,
} from "../../../src/cli/schema-reader/node-fields.generated.ts";
import { blocksWrites } from "../../../src/cli/schema-reader/view-shape.ts";
import { columnRefs, walk } from "../../../src/cli/schema-reader/walk.ts";

const parser = new PgParser({ version: 17 });

async function tree(sql: string): Promise<unknown> {
  const { tree: parsed, error } = await parser.parse(sql);

  if (error !== undefined) {
    throw new Error(error.message);
  }

  return parsed;
}

async function query(sql: string): Promise<unknown> {
  const parsed = await tree(`create view v as ${sql}`);
  let found: unknown;

  walk(
    parsed,
    {
      ViewStmt(view) {
        found = view.query;

        return false;
      },
    },
    "ParseResult",
  );

  return found;
}

describe("NODE_FIELDS", () => {
  it("matches the installed @supabase/pg-parser declarations", async () => {
    expect(PG_PARSER_VERSION).toBe(await pgParserVersion());
    expect(NODE_FIELDS).toStrictEqual(await installedNodeFields());
  });
});

describe("walk", () => {
  it("reads the tag of an untagged message field from its declared type", async () => {
    const parsed = await tree(
      "create policy p on public.notes using (owner = auth.uid());",
    );

    const seen: string[] = [];

    walk(
      parsed,
      {
        RangeVar(range, path) {
          seen.push(`${path.key}:${range.schemaname}.${range.relname}`);
        },
      },
      "ParseResult",
    );

    expect(seen).toStrictEqual(["table:public.notes"]);
  });

  it("gives each node its parent, field and position", async () => {
    const parsed = await tree("select a, b from t;");
    const seen: string[] = [];

    walk(
      parsed,
      {
        ResTarget(_, path) {
          seen.push(`${path.parent?.tag}.${path.key}[${path.index}]`);
        },
      },
      "ParseResult",
    );

    expect(seen).toStrictEqual([
      "SelectStmt.targetList[0]",
      "SelectStmt.targetList[1]",
    ]);
  });

  it("skips the children of a node whose visitor returns false", async () => {
    const parsed = await tree("select (select a from t) as x;");
    const refs: string[] = [];

    walk(
      parsed,
      {
        SubLink: () => false,
        ColumnRef() {
          refs.push("ref");
        },
      },
      "ParseResult",
    );

    expect(refs).toStrictEqual([]);
  });
});

describe("columnRefs", () => {
  it("lists every column once, in source order", async () => {
    const parsed = await tree(
      "select 1 where t.price > 0 and quantity > price;",
    );

    let where: unknown;

    walk(
      parsed,
      {
        SelectStmt(select) {
          where = select.whereClause;
        },
      },
      "ParseResult",
    );

    expect(columnRefs(where)).toStrictEqual(["price", "quantity"]);
  });
});

describe("blocksWrites", () => {
  it("allows a plain projection", async () => {
    expect(blocksWrites(await query("select id, title from notes"))).toBe(
      false,
    );
  });

  it.each([
    "select distinct id from notes",
    "select owner, count(*) from notes group by owner",
    "select id from notes limit 10",
    "select id from notes union select id from archive",
    "select n.id from notes n join users u on u.id = n.owner",
    "select id, row_number() over () from notes",
    "select id from notes where id in (select id from a group by id)",
  ])("blocks %s", async (sql) => {
    expect(blocksWrites(await query(sql))).toBe(true);
  });
});
