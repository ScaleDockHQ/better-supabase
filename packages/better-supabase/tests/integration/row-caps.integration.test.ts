import { createClient } from "@supabase/supabase-js";
import { afterAll, beforeAll, describe, expect, it } from "vitest";

import type { IntrospectionSource } from "../../src/cli/introspect/source.ts";

import { introspect } from "../../src/cli/introspect/index.ts";
import { pgSource } from "../../src/cli/introspect/source.ts";
import { defineSupabase } from "../../src/core/define.ts";
import { schema } from "../fixtures/generated-camel.ts";

const url = process.env["SUPABASE_URL"] ?? "http://127.0.0.1:55421";
const secretKey =
  process.env["SUPABASE_SECRET_KEY"] ??
  "sb_secret_N7UND0UgjKTVK-Uodkm0Hg_xSvEMPvz";
const dbUrl =
  process.env["SUPABASE_DB_URL"] ??
  "postgresql://postgres:postgres@127.0.0.1:55422/postgres";

const GLOBEX = "00000000-0000-4000-8000-000000000002";
const PREFIX = `cap-${Date.now()}-`;
const SCHEMA = `bs_caps_${Date.now()}`;

async function open(): Promise<IntrospectionSource | undefined> {
  try {
    const source = await pgSource(dbUrl);
    await source.queryable.query("select 1");
    return source;
  } catch {
    return undefined;
  }
}

const source = await open();

describe.skipIf(!source)("row caps against the local stack", () => {
  const db = source!;
  const sb = defineSupabase(schema, {
    maxRows: 1000,
    logger: { debug() {}, info() {}, warn() {}, error() {} },
  });
  const admin = sb.connect(
    createClient(url, secretKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    }),
  );

  beforeAll(async () => {
    await admin.tags
      .createMany(
        Array.from({ length: 1001 }, (_, index) => ({
          organizationId: GLOBEX,
          name: `${PREFIX}${String(index).padStart(4, "0")}`,
        })),
        { returning: false },
      )
      .orThrow();
    await db.queryable.query(`
      create schema ${SCHEMA};
      create table ${SCHEMA}.events (id bigint primary key);
      create table ${SCHEMA}.settings (id bigint primary key);
      insert into ${SCHEMA}.events select generate_series(1, 10000);
      insert into ${SCHEMA}.settings values (1);
      analyze ${SCHEMA}.events;
      analyze ${SCHEMA}.settings;
    `);
  });

  afterAll(async () => {
    await admin.tags.deleteMany({
      where: { name: { startsWith: PREFIX } },
    });
    await db.queryable.query(`drop schema if exists ${SCHEMA} cascade`);
    await db.close();
  });

  it("marks a read cut short by db-max-rows as truncated", async () => {
    const seen: boolean[] = [];
    const off = sb.on("query", (event) => seen.push(event.truncated));
    const capped = await admin.tags
      .findMany({
        select: ["id", "name"],
        where: { name: { startsWith: PREFIX } },
      })
      .orThrow();
    const page = await admin.tags
      .findMany({
        select: ["id"],
        where: { name: { startsWith: PREFIX } },
        limit: 1000,
      })
      .orThrow();
    off();
    expect(capped).toHaveLength(1000);
    expect(page).toHaveLength(1000);
    expect(seen).toEqual([true, false]);
  });

  it("orders by the primary key so repeated reads agree", async () => {
    const read = () =>
      admin.tags
        .findMany({ select: ["id"], where: { name: { startsWith: PREFIX } } })
        .orThrow();
    const first = await read();
    const ids = first.map((row) => row.id);
    expect(ids).toEqual([...ids].sort());
    expect((await read()).map((row) => row.id)).toEqual(ids);
  });

  it("marks tables Postgres estimates at 10,000 rows or more as large", async () => {
    const snapshot = await introspect(db.queryable, [SCHEMA]);
    const flags = Object.fromEntries(
      snapshot.extras.tables.map((table) => [table.name, table.large]),
    );
    expect(flags).toEqual({ events: true, settings: undefined });
  });
});
