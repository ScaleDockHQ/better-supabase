import { createClient } from "@supabase/supabase-js";
import { Pool } from "pg";
import { afterAll, beforeAll, describe, expect, it } from "vitest";

import { createAttachments } from "../../src/blocks/attachments/index.ts";
import { createPostgres } from "../../src/postgres/pool.ts";
import { supportStorage } from "../../src/server/support-storage.ts";
import { defineBucket, fromStorageError } from "../../src/storage/index.ts";
import { signLocalJwt } from "../../src/testing/local-key.ts";
import { stackDbUrl, stackUrl } from "./stack-env.ts";

const url = stackUrl();
const dbUrl = stackDbUrl();

const publishableKey =
  process.env["SUPABASE_PUBLISHABLE_KEY"] ??
  "sb_publishable_ACJWlzQHlZjBrEguHvfOxg_3BJgxAaH";

const secretKey =
  process.env["SUPABASE_SECRET_KEY"] ??
  "sb_secret_N7UND0UgjKTVK-Uodkm0Hg_xSvEMPvz";

const ACME = "00000000-0000-4000-8000-000000000001";
const OTHER = "00000000-0000-4000-8000-000000000002";
const USER = "00000000-0000-4000-8000-0000000000ff";
const OTHER_USER = "00000000-0000-4000-8000-0000000000fe";
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

      if (error) {
        throw error;
      }
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

const SESSION = {
  id: "11111111-1111-4111-8111-111111111111",
  adminId: "00000000-0000-4000-8000-0000000000ee",
  targetUserId: USER,
};

const plain = defineBucket({
  id: "bs-it-support-plain",
  path: "{organizationId}/{...rest}",
  policy: "tenant",
  allowedMimeTypes: ["text/plain"],
});

const INSERT_ONLY = "bs-it-support-insert-only";

describe.skipIf(!live)("support storage writes against the local stack", () => {
  const supabase = createClient(url, publishableKey, {
    accessToken: () => signLocalJwt(claims),
  });

  const service = createClient(url, secretKey, {
    auth: { persistSession: false },
  });

  const postgres = createPostgres({ connectionString: dbUrl, max: 2 });
  const pool = new Pool({ connectionString: dbUrl, max: 1 });

  const writer = supportStorage({
    admin: service.storage,
    sql: postgres.asUser(claims),
    adminSql: postgres.admin,
    session: SESSION,
    readOnly: false,
  });

  const asTarget = writer.from(files.id);
  const own = (name: string) => `${ACME}/${RUN}/w/${name}`;
  const hidden = `${OTHER}/${RUN}/w/secret.txt`;

  const row = async (bucket: string, name: string) =>
    (
      await pool.query<{
        owner_id: string | null;
        owner: string | null;
        user_metadata: Record<string, unknown> | null;
      }>(
        "select owner_id, owner::text as owner, user_metadata from storage.objects where bucket_id = $1 and name = $2",
        [bucket, name],
      )
    ).rows[0];

  beforeAll(async () => {
    await pool.query(files.sql());
    await pool.query(plain.sql());
    await pool.query(`
insert into storage.buckets (id, name, public) values ('${INSERT_ONLY}', '${INSERT_ONLY}', false)
on conflict (id) do nothing;
drop policy if exists bs_it_insert_only_insert on storage.objects;
create policy bs_it_insert_only_insert on storage.objects for insert to authenticated
  with check (bucket_id = '${INSERT_ONLY}' and owner_id = (select auth.uid())::text);
drop policy if exists bs_it_insert_only_select on storage.objects;
create policy bs_it_insert_only_select on storage.objects for select to authenticated
  using (bucket_id = '${INSERT_ONLY}' and owner_id = (select auth.uid())::text);`);

    const { error } = await service.storage
      .from(files.id)
      .upload(hidden, text(hidden), { upsert: true });

    if (error) {
      throw error;
    }
  });
  afterAll(async () => {
    for (const bucket of [files.id, plain.id, INSERT_ONLY]) {
      const { rows } = await pool.query<{ name: string }>(
        "select name from storage.objects where bucket_id = $1 and name like $2",
        [bucket, `%/${RUN}/w/%`],
      );

      if (rows.length > 0) {
        await service.storage.from(bucket).remove(rows.map((r) => r.name));
      }
    }

    await postgres.end();
    await pool.end();
  });

  it("uploads as the target and records the owner and the session", async () => {
    const path = own("new.txt");

    const reply = await asTarget.upload(path, text("new"), {
      metadata: { note: "from support" },
    });

    expect(reply.error).toBeNull();
    expect(await row(files.id, path)).toEqual({
      owner_id: USER,
      owner: USER,
      user_metadata: {
        note: "from support",
        supportSessionId: SESSION.id,
        supportAdminId: SESSION.adminId,
      },
    });
    expect(await (await asTarget.download(path)).data?.text()).toBe("new");
  });

  it("refuses a path the target may not write and stores nothing", async () => {
    const path = `${OTHER}/${RUN}/w/denied.txt`;
    const reply = await asTarget.upload(path, text("no"));
    expect(reply.error).toMatchObject({ status: 403, code: "AccessDenied" });
    expect(fromStorageError(reply.error).kind).toBe("forbidden");
    expect(await row(files.id, path)).toBeUndefined();
  });

  it("needs the update policy to overwrite, as Storage does", async () => {
    const bucket = writer.from(INSERT_ONLY);
    const path = own("once.txt");
    expect((await bucket.upload(path, text("first"))).error).toBeNull();
    expect(await row(INSERT_ONLY, path)).toMatchObject({ owner_id: USER });

    const overwrite = await bucket.upload(path, text("second"), {
      upsert: true,
    });

    expect(fromStorageError(overwrite.error).kind).toBe("forbidden");

    const direct = await supabase.storage
      .from(INSERT_ONLY)
      .upload(path, text("second"), { upsert: true });

    expect(fromStorageError(direct.error).kind).toBe("forbidden");
    expect(
      fromStorageError((await bucket.update(path, text("x"))).error).kind,
    ).toBe("forbidden");
    expect(
      await (
        await service.storage.from(INSERT_ONLY).download(path)
      ).data?.text(),
    ).toBe("first");
  });

  it("overwrites an object it may update and keeps it the target's", async () => {
    const path = own("upsert.txt");

    const { error } = await service.storage
      .from(files.id)
      .upload(path, text("old"));

    if (error) {
      throw error;
    }

    expect(await row(files.id, path)).toMatchObject({ owner_id: null });
    expect((await asTarget.update(path, text("new"))).error).toBeNull();
    expect(await row(files.id, path)).toMatchObject({
      owner_id: USER,
      user_metadata: { supportSessionId: SESSION.id },
    });
  });

  it("removes only the paths the target may delete", async () => {
    const path = own("remove.txt");
    expect((await asTarget.upload(path, text("bye"))).error).toBeNull();
    const reply = await asTarget.remove([path, hidden]);
    expect(reply.error).toBeNull();
    expect(reply.data?.map((entry) => entry.name)).toEqual([path]);
    expect(await row(files.id, path)).toBeUndefined();
    expect(await row(files.id, hidden)).toBeDefined();
  });

  it("copies and moves as the target", async () => {
    const source = own("source.txt");
    const copied = own("copied.txt");
    const moved = own("moved.txt");
    expect((await asTarget.upload(source, text("data"))).error).toBeNull();
    expect((await asTarget.copy(source, copied)).error).toBeNull();
    expect(await row(files.id, copied)).toMatchObject({
      owner_id: USER,
      user_metadata: { supportSessionId: SESSION.id },
    });
    expect((await asTarget.move(copied, moved)).error).toBeNull();
    expect(await row(files.id, copied)).toBeUndefined();
    expect(await row(files.id, moved)).toMatchObject({ owner_id: USER });
    expect(await (await asTarget.download(moved)).data?.text()).toBe("data");
    expect(
      fromStorageError((await asTarget.copy(hidden, own("stolen.txt"))).error)
        .kind,
    ).toBe("not_found");
    expect(
      fromStorageError(
        (await asTarget.move(source, `${OTHER}/${RUN}/w/out.txt`)).error,
      ).kind,
    ).toBe("forbidden");

    const unowned = own("unowned.txt");
    const claimed = own("claimed.txt");

    const { error } = await service.storage
      .from(files.id)
      .upload(unowned, text("service"));

    if (error) {
      throw error;
    }

    expect(await row(files.id, unowned)).toMatchObject({ owner_id: null });
    expect((await asTarget.move(unowned, claimed)).error).toBeNull();
    expect(await row(files.id, claimed)).toMatchObject({
      owner_id: USER,
      user_metadata: { supportSessionId: SESSION.id },
    });
  });

  it("surfaces the bucket's allowed MIME types", async () => {
    const path = own("image.png");

    const reply = await writer
      .from(plain.id)
      .upload(path, new Blob(["png"], { type: "image/png" }), {
        contentType: "image/png",
      });

    expect(reply.error).not.toBeNull();
    expect(fromStorageError(reply.error).kind).toBe("invalid_input");
    expect(await row(plain.id, path)).toBeUndefined();
  });

  it("reserves an upload, takes the browser's bytes and claims them", async () => {
    const path = own("reserved.txt");
    const bucket = files.connect(writer);
    const reservation = await bucket.reserve(path).orThrow();
    const browser = createClient(url, publishableKey).storage.from(files.id);

    const uploaded = await browser.uploadToSignedUrl(
      path,
      reservation.token,
      text("big"),
    );

    expect(uploaded.error).toBeNull();
    expect(await row(files.id, path)).toMatchObject({ owner_id: null });
    expect(await bucket.claimReserved(reservation).orThrow()).toEqual({
      path,
    });
    expect(await row(files.id, path)).toMatchObject({
      owner_id: USER,
      owner: USER,
      user_metadata: {
        supportSessionId: SESSION.id,
        supportAdminId: SESSION.adminId,
      },
    });
    expect(await bucket.claimReserved(reservation).orThrow()).toEqual({
      path,
    });
    expect(await (await asTarget.download(path)).data?.text()).toBe("big");
  });

  it("uploads to a reservation from the server and claims it", async () => {
    const path = own("reserved-server.txt");
    const bucket = files.connect(writer);
    const reservation = await bucket.reserve(path).orThrow();
    expect(
      (await bucket.uploadReserved(reservation, text("server"))).error,
    ).toBeNull();
    expect(await row(files.id, path)).toMatchObject({
      owner_id: USER,
      user_metadata: { supportSessionId: SESSION.id },
    });
  });

  it("refuses to reserve a path the target may not write", async () => {
    const path = `${OTHER}/${RUN}/w/reserved.txt`;
    const reserved = await files.connect(writer).reserve(path);
    expect(reserved.error).toMatchObject({
      kind: "forbidden",
      code: "AccessDenied",
    });
    expect(await row(files.id, path)).toBeUndefined();
  });

  it("claims only objects the target could have stored and nobody owns", async () => {
    const bucket = files.connect(writer);
    const before = await row(files.id, hidden);

    expect((await bucket.claimReserved({ path: hidden })).error).toMatchObject({
      kind: "forbidden",
    });
    expect(await row(files.id, hidden)).toEqual(before);

    const taken = own("taken.txt");

    const { error } = await service.storage
      .from(files.id)
      .upload(taken, text("theirs"));

    if (error) {
      throw error;
    }

    await pool.query(
      "update storage.objects set owner_id = $3 where bucket_id = $1 and name = $2",
      [files.id, taken, OTHER_USER],
    );

    expect((await bucket.claimReserved({ path: taken })).error).toMatchObject({
      kind: "forbidden",
      code: "AccessDenied",
    });
    expect(await row(files.id, taken)).toMatchObject({ owner_id: OTHER_USER });
    expect(
      (await bucket.claimReserved({ path: own("missing.txt") })).error,
    ).toMatchObject({ kind: "not_found" });
  });

  it("claims without a request on the target's own client", async () => {
    expect(
      await files
        .connect(supabase)
        .claimReserved({ path: own("anything.txt") })
        .orThrow(),
    ).toEqual({ path: own("anything.txt") });
  });

  it("refuses every write when read-only", async () => {
    const readOnly = supportStorage({
      admin: service.storage,
      sql: postgres.asUser(claims, { readOnly: true }),
      adminSql: postgres.admin,
      session: SESSION,
    }).from(files.id);

    expect(
      (await readOnly.upload(own("ro.txt"), text("x"))).error,
    ).toMatchObject({ code: "SUPPORT_READ_ONLY" });
    expect(
      (await readOnly.createSignedUploadUrl(own("ro.txt"))).error,
    ).toMatchObject({ code: "SUPPORT_READ_ONLY" });
    expect(await row(files.id, own("ro.txt"))).toBeUndefined();
  });

  it("puts an attachment through the block", async () => {
    const path = own("attachment.txt");
    const called: string[] = [];

    const attachments = createAttachments({
      transport: {
        call: (_schema, fn) => {
          called.push(fn);

          return Promise.resolve({
            id: "a1",
            organization_id: ACME,
            bucket: files.id,
            object_path: path,
            name: "attachment.txt",
            mime_type: "text/plain",
            size: "2",
            status: "pending",
            created_at: "2026-10-06T12:00:00Z",
          });
        },
      },
      storage: writer,
    });

    const put = await attachments.put(
      {
        organizationId: ACME,
        name: "attachment.txt",
        mimeType: "text/plain",
        size: 2,
      },
      text("hi"),
    );

    expect(put.error).toBeNull();
    expect(called).toEqual(["create_attachment", "confirm_attachment"]);
    expect(await row(files.id, path)).toMatchObject({ owner_id: USER });
  });
});
