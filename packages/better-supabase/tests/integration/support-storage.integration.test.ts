import { createClient } from "@supabase/supabase-js";
import { Pool } from "pg";
import { afterAll, beforeAll, describe, expect, it } from "vitest";

import { createPostgres } from "../../src/postgres/pool.ts";
import { supportStorage } from "../../src/server/support-storage.ts";
import { defineBucket, fromStorageError } from "../../src/storage/index.ts";
import { signLocalJwt } from "../../src/testing/local-key.ts";

const url = process.env["SUPABASE_URL"] ?? "http://127.0.0.1:55421";
const dbUrl =
  process.env["SUPABASE_DB_URL"] ??
  "postgresql://postgres:postgres@127.0.0.1:55422/postgres";
const publishableKey =
  process.env["SUPABASE_PUBLISHABLE_KEY"] ??
  "sb_publishable_ACJWlzQHlZjBrEguHvfOxg_3BJgxAaH";
const secretKey =
  process.env["SUPABASE_SECRET_KEY"] ??
  "sb_secret_N7UND0UgjKTVK-Uodkm0Hg_xSvEMPvz";

const ACME = "00000000-0000-4000-8000-000000000001";
const OTHER = "00000000-0000-4000-8000-000000000002";
const USER = "00000000-0000-4000-8000-0000000000ff";
const RUN = `s${String(Date.now())}`;

async function reachable(): Promise<boolean> {
  try {
    const response = await fetch(`${url}/storage/v1/status`, {
      signal: AbortSignal.timeout(1000),
    });
    return response.ok;
  } catch {
    return false;
  }
}

const live = await reachable();

const files = defineBucket({
  id: "bs-it-support",
  path: "{organizationId}/{...rest}",
  policy: "tenant",
});

const claims = { sub: USER, role: "authenticated", tenant_id: ACME };
const text = (value: string) => new Blob([value], { type: "text/plain" });

describe.skipIf(!live)("support storage against the local stack", () => {
  const supabase = createClient(url, publishableKey, {
    accessToken: () => signLocalJwt(claims),
  });
  const service = createClient(url, secretKey, {
    auth: { persistSession: false },
  });
  const postgres = createPostgres({ connectionString: dbUrl, max: 2 });
  const pool = new Pool({ connectionString: dbUrl, max: 1 });
  const storage = supportStorage({
    admin: service.storage,
    sql: postgres.asUser(claims, { readOnly: true }),
  });
  const asUser = supabase.storage.from(files.id);
  const asTarget = storage.from(files.id);
  const own = [
    "a.txt",
    "B.txt",
    "b-lower.txt",
    "nested/c.txt",
    "nested/deeper/d.txt",
    "z.txt",
  ].map((name) => `${ACME}/${RUN}/${name}`);
  const hidden = `${OTHER}/${RUN}/secret.txt`;

  beforeAll(async () => {
    await pool.query(files.sql());
    const admin = service.storage.from(files.id);
    for (const path of [...own, hidden]) {
      const { error } = await admin.upload(path, text(path), { upsert: true });
      if (error) throw error;
    }
  });
  afterAll(async () => {
    await service.storage.from(files.id).remove([...own, hidden]);
    await postgres.end();
    await pool.end();
  });

  const names = (data: readonly { readonly name: string }[] | null) =>
    (data ?? []).map((entry) => entry.name);

  it("lists each page as Storage lists it for the target", async () => {
    for (const [prefix, options] of [
      [`${ACME}/${RUN}`, {}],
      [`${ACME}/${RUN}/`, { limit: 2 }],
      [`${ACME}/${RUN}`, { limit: 2, offset: 2 }],
      [`${ACME}/${RUN}`, { search: "b" }],
      [`${ACME}/${RUN}`, { sortBy: { column: "created_at", order: "desc" } }],
      [`${ACME}/${RUN}/nested`, {}],
      [`${OTHER}/${RUN}`, {}],
    ] as const) {
      const expected = await asUser.list(prefix, options);
      const actual = await asTarget.list(prefix, options);
      expect(actual.error).toBeNull();
      expect(names(actual.data)).toEqual(names(expected.data));
      expect(actual.data?.map((entry) => entry.id)).toEqual(
        expected.data?.map((entry) => entry.id),
      );
    }
  });

  it("pages listV2 as Storage pages it for the target", async () => {
    for (const options of [
      { prefix: `${ACME}/${RUN}/`, with_delimiter: true },
      { prefix: `${ACME}/${RUN}/`, with_delimiter: true, limit: 2 },
      { prefix: `${ACME}/${RUN}/`, limit: 3 },
      {
        prefix: `${ACME}/${RUN}/`,
        limit: 2,
        sortBy: { column: "created_at" as const, order: "desc" as const },
      },
    ]) {
      let cursor: string | undefined;
      do {
        const page = { ...options, ...(cursor ? { cursor } : {}) };
        const expected = await asUser.listV2(page);
        const actual = await asTarget.listV2(page);
        expect(actual.error).toBeNull();
        expect(names(actual.data?.objects ?? null)).toEqual(
          names(expected.data?.objects ?? null),
        );
        expect(names(actual.data?.folders ?? null)).toEqual(
          names(expected.data?.folders ?? null),
        );
        expect(actual.data?.hasNext).toBe(expected.data?.hasNext);
        cursor = expected.data?.nextCursor;
      } while (cursor);
    }
  });

  it("reads, checks and signs only the target's objects", async () => {
    const [first] = own;
    expect(await asTarget.exists(first!)).toEqual({ data: true, error: null });
    expect(await asTarget.exists(hidden)).toEqual({ data: false, error: null });
    const info = await asTarget.info(first!);
    expect(info.data).toMatchObject({
      name: first,
      bucketId: files.id,
      contentType: "text/plain",
    });
    expect(await (await asTarget.download(`/${first!}`)).data?.text()).toBe(
      first,
    );
    expect(
      fromStorageError((await asTarget.download(hidden)).error),
    ).toMatchObject({ kind: "not_found" });
    const signed = await asTarget.createSignedUrls([first!, hidden], 60);
    expect(signed.data?.map((entry) => entry.signedUrl === null)).toEqual([
      false,
      true,
    ]);
    expect(await (await fetch(signed.data![0]!.signedUrl!)).text()).toBe(first);

    const bucket = files.connect(storage);
    const listed = await bucket.list({ organizationId: ACME }).orThrow();
    expect(
      listed
        .map((object) => object.path)
        .filter((path) => path.startsWith(`${ACME}/${RUN}/`))
        .sort(),
    ).toEqual([...own].sort());
    expect(
      (await bucket.upload(`${ACME}/${RUN}/new.txt`, "x")).error,
    ).toMatchObject({ kind: "forbidden", code: "SUPPORT_READ_ONLY" });
  });
});
