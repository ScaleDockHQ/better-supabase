import { createClient } from "@supabase/supabase-js";
import { afterAll, beforeAll, describe, expect, it } from "vitest";

import { defineSupabase } from "../../src/core/define.ts";
import { schema } from "../fixtures/generated-camel.ts";
import { openPg } from "../fixtures/pg.ts";

const url = process.env["SUPABASE_URL"] ?? "http://127.0.0.1:55421";
const secretKey =
  process.env["SUPABASE_SECRET_KEY"] ??
  "sb_secret_N7UND0UgjKTVK-Uodkm0Hg_xSvEMPvz";
const dbUrl =
  process.env["SUPABASE_DB_URL"] ??
  "postgresql://postgres:postgres@127.0.0.1:55422/postgres";

const GLOBEX = "00000000-0000-4000-8000-000000000002";
const PREFIX = `cap-${Date.now()}-`;

const source = await openPg(dbUrl);

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
  });

  afterAll(async () => {
    await admin.tags.deleteMany({
      where: { name: { startsWith: PREFIX } },
    });
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
});
