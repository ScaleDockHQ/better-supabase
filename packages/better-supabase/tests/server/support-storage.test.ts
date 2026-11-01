import { describe, expect, it, vi } from "vitest";

import type { StorageApi, StorageBucketApi } from "../../src/storage/index.ts";
import type { SqlCall, SqlRule } from "../fixtures/fake-sql.ts";

import { createAttachments } from "../../src/blocks/attachments/index.ts";
import { createDataLifecycle } from "../../src/blocks/data-lifecycle/index.ts";
import { supportStorage } from "../../src/server/support-storage.ts";
import { defineBucket, fromStorageError } from "../../src/storage/index.ts";
import { fakeSql, pgError } from "../fixtures/fake-sql.ts";

const VISIBLE = "as visible";
const VISIBLE_MANY = "from unnest($2::text[])";
const INFO = "to_jsonb(o) as object";
const SEARCH = "storage.search(";
const SEARCH_V2 = "storage.search_v2(";
const FLAT = "from storage.objects\nwhere";

const INFO_SQL =
  "select to_jsonb(o) as object from storage.objects o where o.bucket_id = $1 and o.name = $2";

const CREATED = new Date("2026-10-01T00:00:00.123Z");
const UPDATED = new Date("2026-10-02T00:00:00.456Z");

/**
 * One folder level of `visible`, folders included, as `storage.search` returns
 * it.
 */
function search(visible: readonly string[], call: SqlCall) {
  const [prefix, , limit, , offset, term] = call.values as [
    string,
    string,
    number,
    number,
    number,
    string,
  ];

  const start = `${prefix}${term}`.toLowerCase();
  const seen = new Set<string>();
  const entries: Record<string, unknown>[] = [];

  const sorted = visible.toSorted((a, b) =>
    a.toLowerCase().localeCompare(b.toLowerCase()),
  );

  for (const name of sorted) {
    if (!name.toLowerCase().startsWith(start)) {
      continue;
    }

    const rest = name.slice(prefix.length);
    const slash = rest.indexOf("/");

    if (slash === -1) {
      entries.push({
        name: rest,
        id: `id-${name}`,
        updated_at: UPDATED,
        created_at: CREATED,
        last_accessed_at: UPDATED,
        metadata: { size: rest.length, mimetype: "text/plain" },
      });
      continue;
    }

    const folder = rest.slice(0, slash);

    if (seen.has(folder)) {
      continue;
    }

    seen.add(folder);
    entries.push({
      name: folder,
      id: null,
      updated_at: null,
      created_at: null,
      last_accessed_at: null,
      metadata: null,
    });
  }

  return entries.slice(offset, offset + limit);
}

/** The target's view of `storage.objects`: RLS lets them see `visible`. */
function targetSql(visible: readonly string[], extra: readonly SqlRule[] = []) {
  return fakeSql([
    ...extra,
    [
      VISIBLE,
      (call) => [{ visible: visible.includes(String(call.values[1])) }],
    ],
    [
      VISIBLE_MANY,
      (call) =>
        (call.values[1] as string[])
          .filter((path) => visible.includes(path))
          .map((path) => ({ path })),
    ],
    [SEARCH, (call) => search(visible, call)],
  ]);
}

function fakeAdmin() {
  const calls: { method: string; args: unknown[] }[] = [];

  const reply =
    (method: string, data: (...args: unknown[]) => unknown) =>
    (...args: unknown[]) => {
      calls.push({ method, args });

      return Promise.resolve({ data: data(...args), error: null });
    };

  const bucket: Record<string, unknown> = {
    download: reply("download", () => new Blob(["hi"])),
    createSignedUrl: reply("createSignedUrl", (path) => ({
      signedUrl: `https://storage.test/sign/${String(path)}`,
    })),
    createSignedUrls: reply("createSignedUrls", (paths) =>
      (paths as string[]).map((path) => ({
        error: null,
        path,
        signedUrl: `https://storage.test/sign/${path}`,
      })),
    ),
    upload: reply("upload", (path) => ({ path })),
    update: reply("update", (path) => ({ path })),
    createSignedUploadUrl: reply("createSignedUploadUrl", (path) => ({
      signedUrl: `https://storage.test/upload/sign/${String(path)}?token=t1`,
      token: "t1",
      path,
    })),
    uploadToSignedUrl: reply("uploadToSignedUrl", (path) => ({ path })),
    remove: reply("remove", (paths) =>
      (paths as unknown[]).map((entry) => ({
        name:
          typeof entry === "string" ? entry : (entry as { path: string }).path,
      })),
    ),
    copy: reply("copy", (_from, to) => ({ path: `docs/${String(to)}` })),
    move: reply("move", () => ({ message: "Successfully moved" })),
    purgeCache: reply("purgeCache", () => ({ message: "success" })),
    getPublicUrl: vi.fn((path: string) => ({
      data: { publicUrl: `https://storage.test/public/${path}` },
    })),
  };

  const from = vi.fn(() => bucket);
  // SAFETY: supportStorage only calls these methods on the service client.
  const admin = { from } as unknown as StorageApi;

  return { admin, from, bucket, calls };
}

function docsOf(
  visible: readonly string[],
  options: { readonly readOnly?: boolean } = {},
) {
  const sql = targetSql(visible);
  const service = fakeAdmin();

  const storage = supportStorage({
    admin: service.admin,
    sql: sql.sql,
    ...options,
  });

  return { ...service, sql, storage, docs: storage.from("docs") };
}

describe("supportStorage reads", () => {
  it("downloads and signs only what the target may see, with every option", async () => {
    const { docs, calls, sql, from } = docsOf(["org/a.pdf"]);

    const blob = await docs.download("/org//a.pdf/", {
      transform: { width: 64 },
      versionId: "v1",
      cacheNonce: "n",
    });

    expect(blob.error).toBeNull();
    expect(await blob.data?.text()).toBe("hi");
    expect(sql.calls[0]).toEqual({
      text: "select exists (select 1 from storage.objects o where o.bucket_id = $1 and o.name = $2) as visible",
      values: ["docs", "org/a.pdf"],
    });
    expect(from).toHaveBeenCalledWith("docs");
    expect(calls[0]).toEqual({
      method: "download",
      args: [
        "org/a.pdf",
        { transform: { width: 64 }, versionId: "v1", cacheNonce: "n" },
        undefined,
      ],
    });

    const signed = await docs.createSignedUrl("org/a.pdf", 60, {
      download: "a.pdf",
      transform: { height: 10 },
      versionId: "v1",
      cacheNonce: "n",
    });

    expect(signed).toEqual({
      data: { signedUrl: "https://storage.test/sign/org/a.pdf" },
      error: null,
    });
    expect(calls[1]?.args).toEqual([
      "org/a.pdf",
      60,
      {
        download: "a.pdf",
        transform: { height: 10 },
        versionId: "v1",
        cacheNonce: "n",
      },
    ]);

    const hidden = await docs.download("org/hidden.pdf");
    expect(hidden).toEqual({
      data: null,
      error: {
        name: "StorageApiError",
        message: "Object not found",
        status: 400,
        statusCode: "404",
        code: "NoSuchKey",
      },
    });
    expect(fromStorageError(hidden.error, "docs")).toMatchObject({
      kind: "not_found",
      code: "NoSuchKey",
    });
    expect((await docs.createSignedUrl("org/hidden.pdf", 60)).data).toBeNull();
    expect(calls).toHaveLength(2);
  });

  it("signs the visible paths of a batch and reports the hidden ones", async () => {
    const { docs, calls } = docsOf(["a", "b"]);

    const reply = await docs.createSignedUrls(["a", "/x", "b", "a"], 60, {
      download: true,
    });

    expect(reply.data).toEqual([
      { error: null, path: "a", signedUrl: "https://storage.test/sign/a" },
      {
        error:
          "Either the object does not exist or you do not have access to it",
        path: "x",
        signedUrl: null,
      },
      { error: null, path: "b", signedUrl: "https://storage.test/sign/b" },
      { error: null, path: "a", signedUrl: "https://storage.test/sign/a" },
    ]);
    expect(calls).toEqual([
      {
        method: "createSignedUrls",
        args: [["a", "b"], 60, { download: true }],
      },
    ]);
    expect((await docs.createSignedUrls(["x"], 60)).data).toEqual([
      expect.objectContaining({ path: "x", signedUrl: null }),
    ]);
    expect(calls).toHaveLength(1);
  });

  it("answers exists and info from SQL alone", async () => {
    const sql = targetSql(
      ["org/a.pdf"],
      [
        [
          (call) => call.text.includes(INFO) && call.values[1] === "org/a.pdf",
          [
            {
              object: {
                id: "o1",
                name: "org/a.pdf",
                version: "v1",
                bucket_id: "docs",
                metadata: {
                  size: 3,
                  mimetype: "application/pdf",
                  cacheControl: "max-age=60",
                  eTag: '"e"',
                },
                user_metadata: { source: "scan" },
                created_at: "2026-10-01T00:00:00.123456+00:00",
                updated_at: "2026-10-02T00:00:00+00:00",
                archived_at: null,
                is_delete_marker: false,
                is_versioned: true,
              },
            },
          ],
        ],
      ],
    );

    const service = fakeAdmin();

    const docs = supportStorage({ admin: service.admin, sql: sql.sql }).from(
      "docs",
    );

    expect(await docs.exists("org/a.pdf")).toEqual({ data: true, error: null });
    expect(await docs.exists("org/hidden.pdf")).toEqual({
      data: false,
      error: null,
    });
    expect((await docs.info("/org/a.pdf")).data).toEqual({
      id: "o1",
      name: "org/a.pdf",
      version: "v1",
      bucketId: "docs",
      createdAt: "2026-10-01T00:00:00.123Z",
      size: 3,
      contentType: "application/pdf",
      cacheControl: "max-age=60",
      etag: '"e"',
      lastModified: "2026-10-02T00:00:00.000Z",
      metadata: { source: "scan" },
      archivedAt: null,
      isDeleteMarker: false,
      isVersioned: true,
    });
    expect((await docs.info("org/hidden.pdf")).error?.code).toBe("NoSuchKey");
    await docs.info("org/a.pdf", { versionId: "v1" });
    expect(sql.calls.at(-1)).toEqual({
      text: `${INFO_SQL} and o.version = $3`,
      values: ["docs", "org/a.pdf", "v1"],
    });
    expect(service.calls).toEqual([]);
  });

  it("keeps sparse info rows and builds public URLs without a check", async () => {
    const sql = targetSql([], [[INFO, [{ object: { id: "o1" } }]]]);
    const service = fakeAdmin();

    const docs = supportStorage({ admin: service.admin, sql: sql.sql }).from(
      "docs",
    );

    expect((await docs.info("a")).data).toEqual({
      id: "o1",
      name: "",
      version: "",
      bucketId: "",
      createdAt: "",
    });
    expect(docs.getPublicUrl("a/b.png", { download: true })).toEqual({
      data: { publicUrl: "https://storage.test/public/a/b.png" },
    });
    expect(service.bucket["getPublicUrl"]).toHaveBeenCalledWith("a/b.png", {
      download: true,
    });
    expect(sql.calls).toHaveLength(1);
  });
});

describe("supportStorage listings", () => {
  it("lists one folder level through storage.search, as storage-api calls it", async () => {
    const { docs, sql, calls } = docsOf([
      "org/a.pdf",
      "org/B.pdf",
      "org/sub/c.pdf",
      "x.pdf",
    ]);

    const listed = await docs.list("org");
    expect(listed.data).toEqual([
      {
        name: "a.pdf",
        id: "id-org/a.pdf",
        updated_at: "2026-10-02T00:00:00.456Z",
        created_at: "2026-10-01T00:00:00.123Z",
        last_accessed_at: "2026-10-02T00:00:00.456Z",
        metadata: { size: 5, mimetype: "text/plain" },
      },
      expect.objectContaining({ name: "B.pdf" }),
      {
        name: "sub",
        id: null,
        updated_at: null,
        created_at: null,
        last_accessed_at: null,
        metadata: null,
      },
    ]);
    expect(sql.calls[0]?.text).toContain(
      "from storage.search($1::text, $2::text, $3::int, $4::int, $5::int, $6::text, $7::text, $8::text) s",
    );
    expect(sql.calls[0]?.values).toEqual([
      "org/",
      "docs",
      100,
      2,
      0,
      "",
      "name",
      "asc",
    ]);
    await docs.list("org/", { search: "b", limit: 1, offset: 1 });
    expect(sql.calls[1]?.values).toEqual([
      "org/",
      "docs",
      1,
      2,
      1,
      "b",
      "name",
      "asc",
    ]);
    await docs.list(undefined, {
      search: "50%_\\",
      sortBy: { column: "created_at", order: "desc" },
    });
    expect(sql.calls[2]?.values).toEqual([
      "",
      "docs",
      100,
      1,
      0,
      "50\\%\\_\\\\",
      "created_at",
      "desc",
    ]);
    expect(calls).toEqual([]);
  });

  it("rejects the list options storage-api rejects", async () => {
    const { docs, sql } = docsOf([]);

    for (const options of [
      { limit: 0 },
      { limit: 1.5 },
      { offset: -1 },
      { sortBy: { column: "size" } },
      { sortBy: { column: "name", order: "up" } },
    ]) {
      const reply = await docs.list("", options);
      expect(reply.error).toMatchObject({
        status: 400,
        code: "InvalidRequest",
      });
      expect(fromStorageError(reply.error).kind).toBe("invalid_request");
    }

    for (const options of [
      { limit: 0 },
      { sortBy: { column: "size" as "name" } },
      { sortBy: { column: "name" as const, order: "up" as "asc" } },
    ]) {
      expect((await docs.listV2(options)).error?.status).toBe(400);
    }

    expect((await docs.listV2({ cursor: "!" })).error).toMatchObject({
      code: "InvalidParameter",
    });
    expect((await docs.listV2({ cursor: btoa("z:nope") })).error?.code).toBe(
      "InvalidParameter",
    );
    expect(sql.calls).toEqual([]);
  });

  it("pages listV2 with folders through storage.search_v2", async () => {
    const row = (name: string, id: string | null) => ({
      key: name.split("/")[1],
      name,
      id,
      updated_at: id ? UPDATED : null,
      created_at: id ? CREATED : null,
      last_accessed_at: null,
      metadata: null,
    });

    const sql = fakeSql([
      [
        SEARCH_V2,
        [
          row("org/a.pdf", "1"),
          row("org/sub/", null),
          row("org/sub/x", "3"),
          row("org/z.pdf", "4"),
        ],
      ],
    ]);

    const docs = supportStorage({
      admin: fakeAdmin().admin,
      sql: sql.sql,
    }).from("docs");

    const page = await docs.listV2({
      prefix: "org/",
      with_delimiter: true,
      limit: 2,
    });

    expect(page.data).toEqual({
      hasNext: true,
      nextCursor: btoa("l:org/sub/"),
      folders: [{ name: "org/sub/" }],
      objects: [
        {
          name: "org/a.pdf",
          key: "a.pdf",
          id: "1",
          updated_at: "2026-10-02T00:00:00.456Z",
          created_at: "2026-10-01T00:00:00.123Z",
          metadata: null,
        },
      ],
    });
    expect(sql.calls[0]?.values).toEqual([
      "org/",
      "docs",
      3,
      2,
      "",
      "asc",
      "name",
      null,
    ]);
    await docs.listV2({
      prefix: "org/",
      with_delimiter: true,
      cursor: btoa(
        "l:org/sub/\no:desc\nc:created_at\na:2026-10-01T00:00:00.000Z",
      ),
    });
    expect(sql.calls[1]?.values).toEqual([
      "org/",
      "docs",
      1001,
      2,
      "org/sub/",
      "desc",
      "created_at",
      "2026-10-01T00:00:00.000Z",
    ]);
    const root = await docs.listV2({ with_delimiter: true });
    expect(sql.calls[2]?.values.slice(0, 5)).toEqual(["", "docs", 1001, 1, ""]);
    expect(root.data?.hasNext).toBe(false);
    expect(root.data?.nextCursor).toBeUndefined();
    expect(root.data?.folders).toEqual([{ name: "org/" }]);
  });

  it("pages a flat listV2 with the query storage-api runs", async () => {
    const rows = [
      {
        id: "1",
        name: "org/a",
        metadata: { size: 1 },
        updated_at: UPDATED,
        created_at: CREATED,
        last_accessed_at: UPDATED,
      },
      {
        id: "2",
        name: "org/é",
        metadata: null,
        updated_at: UPDATED,
        created_at: CREATED,
        last_accessed_at: UPDATED,
      },
    ];

    const sql = fakeSql([[FLAT, rows]]);

    const docs = supportStorage({
      admin: fakeAdmin().admin,
      sql: sql.sql,
    }).from("docs");

    const first = await docs.listV2({
      prefix: "org/5%",
      limit: 1,
      sortBy: { column: "updated_at", order: "desc" },
    });

    expect(sql.calls[0]).toEqual({
      text: `select id::text as id, name, metadata, updated_at, created_at, last_accessed_at
from storage.objects
where bucket_id = $1 and name like $3
order by updated_at desc, name collate "C" desc
limit $2::int`,
      values: ["docs", 2, "org/5\\%%"],
    });
    expect(first.data?.objects).toEqual([
      {
        name: "org/a",
        id: "1",
        updated_at: "2026-10-02T00:00:00.456Z",
        created_at: "2026-10-01T00:00:00.123Z",
        last_accessed_at: "2026-10-02T00:00:00.456Z",
        metadata: { size: 1 },
      },
    ]);
    const cursor = first.data?.nextCursor ?? "";
    expect(atob(cursor)).toBe(
      "l:org/a\no:desc\nc:updated_at\na:2026-10-02T00:00:00.456Z",
    );
    await docs.listV2({ cursor });
    expect(sql.calls[1]).toEqual({
      text: `select id::text as id, name, metadata, updated_at, created_at, last_accessed_at
from storage.objects
where bucket_id = $1 and row(date_trunc('milliseconds', updated_at), name collate "C") < row(coalesce(nullif($3, '')::timestamptz, 'epoch'::timestamptz), $4)
order by updated_at desc, name collate "C" desc
limit $2::int`,
      values: ["docs", 1001, "2026-10-02T00:00:00.456Z", "org/a"],
    });
    const byName = await docs.listV2({ limit: 1 });
    expect(atob(byName.data?.nextCursor ?? "")).toBe("l:org/a");
    await docs.listV2({ cursor: byName.data?.nextCursor ?? "" });
    expect(sql.calls[3]?.text).toContain(
      'where bucket_id = $1 and name collate "C" > $3',
    );
    expect(sql.calls[3]?.values).toEqual(["docs", 1001, "org/a"]);

    const reversed = fakeSql([[FLAT, rows.toReversed()]]);

    const unicode = supportStorage({
      admin: fakeAdmin().admin,
      sql: reversed.sql,
    }).from("docs");

    const named = await unicode.listV2({ limit: 1 });
    await unicode.listV2({ cursor: named.data?.nextCursor ?? "" });
    expect(reversed.calls[1]?.values).toEqual(["docs", 1001, "org/é"]);
  });
});

const SESSION = {
  id: "session-1",
  adminId: "admin-1",
  targetUserId: "00000000-0000-4000-8000-0000000000aa",
  startedAt: Temporal.Instant.from("2026-10-01T00:00:00Z"),
} as const;

const SINCE = "2026-10-01T00:00:00Z";

const STAMP = { supportSessionId: "session-1", supportAdminId: "admin-1" };
const SAVEPOINT = "savepoint better_supabase_support_write";
const ROLLBACK = "rollback to savepoint better_supabase_support_write";
const RLS = 'new row violates row-level security policy for table "objects"';

function writableOf(
  visible: readonly string[],
  rules: readonly SqlRule[] = [],
  ownerRules: readonly SqlRule[] = [],
) {
  const sql = targetSql(visible, [
    ...rules,
    [
      "select name, owner_id from storage.objects",
      (call) =>
        visible.includes(String(call.values[1]))
          ? [{ name: call.values[1], owner_id: null }]
          : [],
    ],
  ]);

  const owner = fakeSql(ownerRules);
  const service = fakeAdmin();

  const storage = supportStorage({
    admin: service.admin,
    sql: sql.sql,
    adminSql: owner.sql,
    session: SESSION,
    readOnly: false,
  });

  return { ...service, sql, owner, storage, docs: storage.from("docs") };
}

describe("supportStorage writes", () => {
  it("authorises an upload as the target in a rolled-back savepoint", async () => {
    const { docs, sql, owner, calls } = writableOf([]);

    const reply = await docs.upload("/org//a.txt", "x", {
      contentType: "text/plain",
      metadata: { kind: "note", supportSessionId: "forged" },
    });

    expect(reply).toEqual({ data: { path: "org/a.txt" }, error: null });
    expect(sql.transactions).toBe(1);
    expect(sql.calls).toEqual([
      { text: SAVEPOINT, values: [] },
      {
        text: "insert into storage.objects (bucket_id, name, owner, owner_id, user_metadata)\nvalues ($1, $2, $3::uuid, $4, $5::jsonb)",
        values: [
          "docs",
          "org/a.txt",
          SESSION.targetUserId,
          SESSION.targetUserId,
          JSON.stringify({ kind: "note", ...STAMP }),
        ],
      },
      { text: ROLLBACK, values: [] },
    ]);
    expect(calls).toEqual([
      {
        method: "upload",
        args: [
          "org/a.txt",
          "x",
          { contentType: "text/plain", metadata: { kind: "note", ...STAMP } },
        ],
      },
    ]);
    expect(owner.calls).toEqual([
      {
        text: "update storage.objects set owner = $3::uuid, owner_id = $4\nwhere bucket_id = $1 and name = $2 and user_metadata ->> 'supportSessionId' = $5",
        values: [
          "docs",
          "org/a.txt",
          SESSION.targetUserId,
          SESSION.targetUserId,
          "session-1",
        ],
      },
    ]);
  });

  it("authorises upserts and updates against the update policy", async () => {
    const { docs, sql, calls } = writableOf([]);
    await docs.upload("a", "x", { upsert: true });
    await docs.update("b", "y");
    const upserts = sql.texts().filter((text) => text.includes("insert"));
    expect(upserts).toHaveLength(2);

    for (const text of upserts) {
      expect(text).toContain(
        "on conflict (bucket_id, name) do update\nset owner = excluded.owner, owner_id = excluded.owner_id, user_metadata = excluded.user_metadata",
      );
    }

    expect(calls.map((call) => call.method)).toEqual(["upload", "update"]);
    expect(calls[0]?.args[2]).toEqual({ upsert: true, metadata: STAMP });
  });

  it("stores a target id that is not a uuid without the legacy owner", async () => {
    const sql = fakeSql();
    const owner = fakeSql();
    const service = fakeAdmin();
    await supportStorage({
      admin: service.admin,
      sql: sql.sql,
      adminSql: owner.sql,
      session: { ...SESSION, targetUserId: "user-1" },
      readOnly: false,
    })
      .from("docs")
      .upload("a", "x");
    expect(sql.calls[1]?.values.slice(2, 4)).toEqual([null, "user-1"]);
    expect(owner.calls[0]?.values.slice(2, 4)).toEqual([null, "user-1"]);
  });

  it("answers a refused dry run as Storage does, without writing", async () => {
    const { docs, sql, owner, calls } = writableOf(
      [],
      [["insert into", { throws: pgError("42501", RLS) }]],
    );

    const reply = await docs.upload("a", "x");
    expect(reply).toEqual({
      data: null,
      error: {
        name: "StorageApiError",
        message: "new row violates row-level security policy",
        status: 403,
        statusCode: "403",
        code: "AccessDenied",
      },
    });
    expect(fromStorageError(reply.error, "docs")).toMatchObject({
      kind: "forbidden",
      code: "AccessDenied",
    });
    expect(sql.texts().at(-1)).toBe(ROLLBACK);
    expect(calls).toEqual([]);
    expect(owner.calls).toEqual([]);

    const duplicate = writableOf(
      [],
      [["insert into", { throws: pgError("23505", "duplicate key") }]],
    );

    const again = await duplicate.docs.upload("a", "x");
    expect(again.error).toMatchObject({ status: 409, code: "Duplicate" });
    expect(fromStorageError(again.error).kind).toBe("conflict");

    const broken = writableOf(
      [],
      [["insert into", { throws: pgError("57014", "canceling statement") }]],
    );

    expect((await broken.docs.upload("a", "x")).error).toMatchObject({
      name: "DbError",
      code: "57014",
    });
  });

  it("passes a Storage refusal through without claiming the object", async () => {
    const { docs, bucket, owner } = writableOf([]);
    bucket["upload"] = () =>
      Promise.resolve({
        data: null,
        error: { name: "StorageApiError", message: "too big", status: 413 },
      });
    expect((await docs.upload("a", "x")).error).toMatchObject({
      message: "too big",
    });
    expect(owner.calls).toEqual([]);
  });

  it("removes the stored object when the owner update fails", async () => {
    const { docs, calls } = writableOf(
      [],
      [],
      [[() => true, { throws: pgError("40001", "could not serialize") }]],
    );

    const reply = await docs.upload("a", "x");
    expect(reply.error).toMatchObject({ name: "DbError", code: "40001" });
    expect(calls.map((call) => [call.method, call.args[0]])).toEqual([
      ["upload", "a"],
      ["remove", ["a"]],
    ]);
  });

  it("removes only the paths the target may delete", async () => {
    const { docs, sql, calls } = writableOf(
      [],
      [["delete from", [{ name: "org/a" }, { name: "org/c" }]]],
    );

    const reply = await docs.remove([
      "/org/a",
      "org/b",
      { path: "org/c", versionId: "v1" },
      "org/a",
    ]);

    expect(sql.calls[1]).toEqual({
      text: "select set_config('storage.allow_delete_query', 'true', true)",
      values: [],
    });
    expect(sql.calls[2]).toEqual({
      text: "delete from storage.objects where bucket_id = $1 and name = any($2::text[]) returning name",
      values: ["docs", ["org/a", "org/b", "org/c"]],
    });
    expect(sql.texts().at(-1)).toBe(ROLLBACK);
    expect(calls).toEqual([
      {
        method: "remove",
        args: [["org/a", { path: "org/c", versionId: "v1" }, "org/a"]],
      },
    ]);
    expect(reply.data).toHaveLength(3);

    const none = writableOf([]);
    expect(await none.docs.remove(["org/b"])).toEqual({
      data: [],
      error: null,
    });
    expect(none.calls).toEqual([]);
  });

  it("copies and moves what the target may read and write", async () => {
    const { docs, sql, owner, calls } = writableOf(
      ["org/a"],
      [["update storage.objects", [{ name: "org/b" }]]],
    );

    expect(
      await docs.copy("org/a", "org/b", { destinationBucket: "other" }),
    ).toEqual({ data: { path: "docs/org/b" }, error: null });
    expect(sql.calls.slice(1, 3)).toEqual([
      {
        text: "select name, owner_id from storage.objects where bucket_id = $1 and name = $2",
        values: ["docs", "org/a"],
      },
      {
        text: expect.stringContaining("insert into storage.objects"),
        values: [
          "other",
          "org/b",
          SESSION.targetUserId,
          SESSION.targetUserId,
          JSON.stringify(STAMP),
        ],
      },
    ]);
    expect(owner.calls[0]).toEqual({
      text: "update storage.objects\nset owner = $3::uuid, owner_id = $4, user_metadata = coalesce(user_metadata, '{}'::jsonb) || $5::jsonb\nwhere bucket_id = $1 and name = $2 and owner_id is null",
      values: [
        "other",
        "org/b",
        SESSION.targetUserId,
        SESSION.targetUserId,
        JSON.stringify(STAMP),
      ],
    });

    sql.calls.length = 0;
    expect(await docs.move("/org/a", "org/b")).toEqual({
      data: { message: "Successfully moved" },
      error: null,
    });
    expect(sql.calls[2]).toEqual({
      text: "update storage.objects\nset bucket_id = $3, name = $4, owner = $5::uuid, owner_id = $6\nwhere bucket_id = $1 and name = $2\nreturning name",
      values: [
        "docs",
        "org/a",
        "docs",
        "org/b",
        SESSION.targetUserId,
        SESSION.targetUserId,
      ],
    });
    expect(owner.calls[1]).toEqual({
      text: "update storage.objects\nset owner = $3::uuid, owner_id = $4, user_metadata = coalesce(user_metadata, '{}'::jsonb) || $5::jsonb\nwhere bucket_id = $1 and name = $2 and owner_id is not distinct from $6",
      values: [
        "docs",
        "org/b",
        SESSION.targetUserId,
        SESSION.targetUserId,
        JSON.stringify(STAMP),
        null,
      ],
    });
    expect(calls.map((call) => call.method)).toEqual(["copy", "move"]);
  });

  it("claims a moved object by the owner it had before the move", async () => {
    const { docs, owner } = writableOf(
      [],
      [
        [
          "select name, owner_id from storage.objects",
          [{ name: "org/a", owner_id: "someone-else" }],
        ],
        ["update storage.objects", [{ name: "org/b" }]],
      ],
    );

    expect((await docs.move("org/a", "org/b")).error).toBeNull();
    expect(owner.calls[0]?.values.at(-1)).toBe("someone-else");
  });

  it("upserts against the current-version index once Storage versions objects", async () => {
    const { docs, sql } = writableOf(
      [],
      [["from pg_indexes", [{ versioned: true }]]],
    );

    await docs.upload("a", "x", { upsert: true });
    await docs.update("b", "y");
    await docs.upload("c", "z");
    expect(
      sql.texts().filter((text) => text.includes("from pg_indexes")),
    ).toHaveLength(1);
    const upserts = sql.texts().filter((text) => text.includes("on conflict"));
    expect(upserts).toHaveLength(2);

    for (const text of upserts) {
      expect(text).toContain(
        'on conflict (bucket_id, name collate "C") where archived_at is null do update',
      );
    }
  });

  it("answers a hidden or unmovable source like a missing one", async () => {
    const hidden = writableOf([]);

    for (const reply of [
      await hidden.docs.copy("org/a", "org/b"),
      await hidden.docs.move("org/a", "org/b"),
    ]) {
      expect(reply.error).toMatchObject({ statusCode: "404" });
    }

    const pinned = writableOf(["org/a"]);
    expect((await pinned.docs.move("org/a", "org/b")).error).toMatchObject({
      code: "NoSuchKey",
    });
    expect([...hidden.calls, ...pinned.calls]).toEqual([]);
  });

  it("undoes a copy or a move whose owner update fails", async () => {
    const failing: SqlRule[] = [[() => true, { throws: "offline" }]];

    const { docs, calls, from } = writableOf(
      ["org/a"],
      [["update storage.objects", [{ name: "org/b" }]]],
      failing,
    );

    expect(
      fromStorageError(
        (await docs.copy("org/a", "org/b", { destinationBucket: "other" }))
          .error,
      ).kind,
    ).toBe("unexpected");
    expect((await docs.move("org/a", "org/b")).error).toMatchObject({
      name: "DbError",
    });
    expect(calls.map((call) => [call.method, ...call.args])).toEqual([
      ["copy", "org/a", "org/b", { destinationBucket: "other" }],
      ["remove", ["org/b"]],
      ["move", "org/a", "org/b", {}],
      ["move", "org/b", "org/a", { destinationBucket: "docs" }],
    ]);
    expect(from.mock.calls.map((call: unknown[]) => call[0])).toContain(
      "other",
    );
  });

  it("purges the cache of an object the target may see", async () => {
    const { docs, calls } = writableOf(["org/a"]);
    expect(await docs.purgeCache("org/a")).toEqual({
      data: { message: "success" },
      error: null,
    });
    expect((await docs.purgeCache("org/b")).error).toMatchObject({
      code: "NoSuchKey",
    });
    expect(calls.map((call) => call.method)).toEqual(["purgeCache"]);
  });
});

const CLAIM_SQL =
  "update storage.objects\nset owner = $3::uuid, owner_id = $4, user_metadata = coalesce(user_metadata, '{}'::jsonb) || $5::jsonb\nwhere bucket_id = $1 and name = $2 and owner_id is null and updated_at >= $6::timestamptz\nreturning name";

const OWNER_SQL =
  "select owner_id, updated_at >= $3::timestamptz as recent\nfrom storage.objects where bucket_id = $1 and name = $2";

const INSERT_SQL =
  "insert into storage.objects (bucket_id, name, owner, owner_id, user_metadata)\nvalues ($1, $2, $3::uuid, $4, $5::jsonb)";

const DUPLICATE: SqlRule = [
  "insert into",
  { throws: pgError("23505", "duplicate key value") },
];

function claimOf(storage: StorageApi, bucket = "docs") {
  return (path: string) => {
    if (!storage.claimSignedUpload) {
      throw new TypeError("claimSignedUpload is missing");
    }

    return storage.claimSignedUpload(bucket, path);
  };
}

describe("supportStorage signed uploads", () => {
  it("signs an upload URL once the target may insert the object", async () => {
    const { docs, sql, owner, calls } = writableOf([]);

    const reply = await docs.createSignedUploadUrl("/org//a.txt");

    expect(reply).toEqual({
      data: {
        signedUrl: "https://storage.test/upload/sign/org/a.txt?token=t1",
        token: "t1",
        path: "org/a.txt",
      },
      error: null,
    });
    expect(sql.calls).toEqual([
      { text: SAVEPOINT, values: [] },
      {
        text: INSERT_SQL,
        values: [
          "docs",
          "org/a.txt",
          SESSION.targetUserId,
          SESSION.targetUserId,
          JSON.stringify(STAMP),
        ],
      },
      { text: ROLLBACK, values: [] },
    ]);
    expect(calls).toEqual([
      { method: "createSignedUploadUrl", args: ["org/a.txt", undefined] },
    ]);
    expect(owner.calls).toEqual([]);
  });

  it("authorises an upsert reservation against the update policy", async () => {
    const { docs, sql, calls } = writableOf([]);

    await docs.createSignedUploadUrl("a", { upsert: true });
    expect(sql.calls[2]?.text).toContain(
      "on conflict (bucket_id, name) do update",
    );
    expect(calls[0]?.args).toEqual(["a", { upsert: true }]);
  });

  it("refuses to sign what the target may not insert", async () => {
    const { docs, owner, calls } = writableOf(
      [],
      [["insert into", { throws: pgError("42501", RLS) }]],
    );

    const reply = await docs.createSignedUploadUrl("a");
    expect(reply).toEqual({
      data: null,
      error: {
        name: "StorageApiError",
        message: "new row violates row-level security policy",
        status: 403,
        statusCode: "403",
        code: "AccessDenied",
      },
    });
    expect(calls).toEqual([]);
    expect(owner.calls).toEqual([]);
  });

  it("claims an uploaded object without an owner for the target", async () => {
    const { storage, sql, owner, calls } = writableOf(
      [],
      [DUPLICATE],
      [["returning name", [{ name: "org/a.txt" }]]],
    );

    const reply = await claimOf(storage)("/org/a.txt");

    expect(reply).toEqual({ data: { path: "org/a.txt" }, error: null });
    expect(sql.calls).toEqual([
      { text: SAVEPOINT, values: [] },
      {
        text: INSERT_SQL,
        values: [
          "docs",
          "org/a.txt",
          SESSION.targetUserId,
          SESSION.targetUserId,
          JSON.stringify(STAMP),
        ],
      },
      { text: ROLLBACK, values: [] },
      { text: expect.stringContaining("from pg_indexes"), values: [] },
    ]);
    expect(owner.calls).toEqual([
      {
        text: CLAIM_SQL,
        values: [
          "docs",
          "org/a.txt",
          SESSION.targetUserId,
          SESSION.targetUserId,
          JSON.stringify(STAMP),
          SINCE,
        ],
      },
    ]);
    expect(calls).toEqual([]);
  });

  it("refuses to claim an object another user owns", async () => {
    const { storage, owner } = writableOf(
      [],
      [DUPLICATE],
      [["as recent", [{ owner_id: "someone-else", recent: true }]]],
    );

    const reply = await claimOf(storage)("a");
    expect(reply).toEqual({
      data: null,
      error: {
        name: "StorageApiError",
        message: "The object belongs to another user",
        status: 403,
        statusCode: "403",
        code: "AccessDenied",
      },
    });
    expect(fromStorageError(reply.error, "docs").kind).toBe("forbidden");
    expect(owner.calls.at(-1)).toEqual({
      text: OWNER_SQL,
      values: ["docs", "a", SINCE],
    });
  });

  it("refuses to claim an object stored before the session started", async () => {
    const { storage } = writableOf(
      [],
      [DUPLICATE],
      [["as recent", [{ owner_id: null, recent: false }]]],
    );

    expect(await claimOf(storage)("a")).toEqual({
      data: null,
      error: {
        name: "StorageApiError",
        message: "The object was stored before the support session started",
        status: 403,
        statusCode: "403",
        code: "AccessDenied",
      },
    });

    const theirs = writableOf(
      [],
      [DUPLICATE],
      [["as recent", [{ owner_id: "someone-else", recent: false }]]],
    );

    expect((await claimOf(theirs.storage)("a")).error).toMatchObject({
      code: "AccessDenied",
      message: "The object was stored before the support session started",
    });
    expect(theirs.calls.some((call) => call.method === "remove")).toBe(false);

    const mine = writableOf(
      [],
      [DUPLICATE],
      [["as recent", [{ owner_id: SESSION.targetUserId, recent: false }]]],
    );

    expect(await claimOf(mine.storage)("a")).toEqual({
      data: { path: "a" },
      error: null,
    });
  });

  it("claims again when the upload lands between the update and the check", async () => {
    let attempts = 0;

    const { storage } = writableOf(
      [],
      [DUPLICATE],
      [
        [
          "returning name",
          () => {
            attempts += 1;

            return attempts === 1 ? [] : [{ name: "a" }];
          },
        ],
        ["as recent", [{ owner_id: null, recent: true }]],
      ],
    );

    expect(await claimOf(storage)("a")).toEqual({
      data: { path: "a" },
      error: null,
    });
    expect(attempts).toBe(2);
  });

  it("removes nothing when a claim is refused", async () => {
    const { storage, calls } = writableOf(
      [],
      [["insert into", { throws: pgError("42501", RLS) }]],
      [["as recent", [{ owner_id: null, recent: true }]]],
    );

    expect((await claimOf(storage)("a")).error).toMatchObject({
      status: 403,
      code: "AccessDenied",
    });
    expect(calls.some((call) => call.method === "remove")).toBe(false);
  });

  it("only claims the current version once Storage versions objects", async () => {
    const { storage, owner } = writableOf(
      [],
      [DUPLICATE, ["from pg_indexes", [{ versioned: true }]]],
    );

    await claimOf(storage)("a");
    expect(owner.texts()).toEqual([
      `${CLAIM_SQL.replace("\nreturning name", "")} and archived_at is null\nreturning name`,
      `${OWNER_SQL} and archived_at is null`,
    ]);
  });

  it("accepts a repeated claim of the target's object without stamping it again", async () => {
    const { storage, owner } = writableOf(
      [],
      [DUPLICATE],
      [["as recent", [{ owner_id: SESSION.targetUserId, recent: true }]]],
    );

    expect(await claimOf(storage)("a")).toEqual({
      data: { path: "a" },
      error: null,
    });
    expect(owner.calls.map((call) => call.text)).toEqual([
      CLAIM_SQL,
      OWNER_SQL,
    ]);
  });

  it("answers a claim of a missing object like Storage does", async () => {
    const missing = writableOf([]);
    expect((await claimOf(missing.storage)("a")).error).toMatchObject({
      statusCode: "404",
      code: "NoSuchKey",
    });
    expect(missing.owner.calls).toEqual([]);

    const removed = writableOf([], [DUPLICATE]);
    expect((await claimOf(removed.storage)("a")).error).toMatchObject({
      code: "NoSuchKey",
    });
    expect(removed.owner.calls).toHaveLength(2);
  });

  it("refuses to claim what the target may not insert", async () => {
    const { storage, owner } = writableOf(
      [],
      [["insert into", { throws: pgError("42501", RLS) }]],
    );

    expect((await claimOf(storage)("a")).error).toMatchObject({
      status: 403,
      code: "AccessDenied",
    });
    expect(owner.calls).toEqual([]);

    const broken = writableOf(
      [],
      [["insert into", { throws: pgError("57014", "canceling statement") }]],
    );

    expect((await claimOf(broken.storage)("a")).error).toMatchObject({
      name: "DbError",
      code: "57014",
    });
  });

  it("uploads with a token and claims the stored object", async () => {
    const { docs, sql, owner, calls } = writableOf(
      [],
      [],
      [["returning name", [{ name: "org/a.txt" }]]],
    );

    const reply = await docs.uploadToSignedUrl("org/a.txt", "t1", "x", {
      contentType: "text/plain",
      metadata: { kind: "note" },
    });

    expect(reply).toEqual({ data: { path: "org/a.txt" }, error: null });
    expect(sql.calls[1]?.values.at(-1)).toBe(
      JSON.stringify({ kind: "note", ...STAMP }),
    );
    expect(calls).toEqual([
      {
        method: "uploadToSignedUrl",
        args: [
          "org/a.txt",
          "t1",
          "x",
          { contentType: "text/plain", metadata: { kind: "note", ...STAMP } },
        ],
      },
    ]);
    expect(owner.texts()).toEqual([CLAIM_SQL]);
  });

  it("removes a token upload whose claim fails or is refused", async () => {
    const failing = writableOf(
      [],
      [],
      [[() => true, { throws: pgError("40001", "could not serialize") }]],
    );

    expect(
      (await failing.docs.uploadToSignedUrl("a", "t1", "x")).error,
    ).toMatchObject({ name: "DbError", code: "40001" });
    expect(failing.calls.map((call) => call.method)).toEqual([
      "uploadToSignedUrl",
      "remove",
    ]);

    const foreign = writableOf(
      [],
      [],
      [["as recent", [{ owner_id: "signer-of-the-token", recent: true }]]],
    );

    expect(
      (await foreign.docs.uploadToSignedUrl("a", "t1", "x")).error,
    ).toMatchObject({ code: "AccessDenied" });
    expect(foreign.calls.map((call) => [call.method, call.args[0]])).toEqual([
      ["uploadToSignedUrl", "a"],
      ["remove", ["a"]],
    ]);

    const vanished = writableOf([]);
    expect(
      (await vanished.docs.uploadToSignedUrl("a", "t1", "x")).error,
    ).toMatchObject({ code: "NoSuchKey" });
    expect(vanished.calls.map((call) => call.method)).toEqual([
      "uploadToSignedUrl",
      "remove",
    ]);

    const refused = writableOf([]);
    refused.bucket["uploadToSignedUrl"] = () =>
      Promise.resolve({
        data: null,
        error: { name: "StorageApiError", message: "expired", status: 400 },
      });
    expect(
      (await refused.docs.uploadToSignedUrl("a", "t1", "x")).error,
    ).toMatchObject({ message: "expired" });
    expect(refused.owner.calls).toEqual([]);
  });
});

describe("supportStorage refusals and failures", () => {
  const writes: readonly ((
    bucket: StorageBucketApi,
  ) => PromiseLike<{ readonly error: unknown }>)[] = [
    (bucket) => bucket.upload("a", "x"),
    (bucket) => bucket.update("a", "x"),
    (bucket) => bucket.createSignedUploadUrl("a"),
    (bucket) => bucket.uploadToSignedUrl("a", "t", "x"),
    (bucket) => bucket.remove(["a"]),
    (bucket) => bucket.copy("a", "b"),
    (bucket) => bucket.move("a", "b"),
    (bucket) => bucket.purgeCache("a"),
  ];

  const refused = (reply: { readonly error: unknown }, code: string) => {
    expect(reply).toMatchObject({
      data: null,
      error: { name: "StorageApiError", status: 403, statusCode: "403", code },
    });
    expect(fromStorageError(reply.error, "docs")).toMatchObject({
      kind: "forbidden",
      code,
      table: "docs",
    });
  };

  it("refuses every write in a read-only session", async () => {
    const sql = fakeSql();
    const owner = fakeSql();
    const service = fakeAdmin();

    const storage = supportStorage({
      admin: service.admin,
      sql: sql.sql,
      adminSql: owner.sql,
      session: SESSION,
    });

    const docs = storage.from("docs");

    for (const write of writes) {
      refused(await write(docs), "SUPPORT_READ_ONLY");
    }

    refused(await claimOf(storage)("a"), "SUPPORT_READ_ONLY");

    expect(service.calls).toEqual([]);
    expect(sql.calls).toEqual([]);
    expect((await docs.upload("a", "x")).error?.message).toBe(
      "The support session is read-only",
    );
  });

  it("refuses writes when the session, the admin client or transactions are missing", async () => {
    const sql = fakeSql();
    const service = fakeAdmin();

    for (const options of [
      { sql: sql.sql, session: SESSION },
      { sql: sql.sql, adminSql: sql.sql },
      {
        sql: { queryRaw: <T>(text: string) => sql.sql.queryRaw<T>(text) },
        adminSql: sql.sql,
        session: SESSION,
      },
    ]) {
      const storage = supportStorage({
        admin: service.admin,
        readOnly: false,
        ...options,
      });

      for (const write of writes) {
        refused(await write(storage.from("docs")), "SUPPORT_STORAGE_WRITES");
      }

      refused(await claimOf(storage)("a"), "SUPPORT_STORAGE_WRITES");
    }

    expect(service.calls).toEqual([]);
    expect(sql.calls).toEqual([]);
  });

  it("maps database and service errors", async () => {
    const failing = fakeSql([
      [
        () => true,
        { throws: pgError("42501", "permission denied for table objects") },
      ],
    ]);

    const service = fakeAdmin();

    const docs = supportStorage({
      admin: service.admin,
      sql: failing.sql,
    }).from("docs");

    expect(fromStorageError((await docs.download("a")).error)).toMatchObject({
      kind: "forbidden",
      code: "42501",
    });
    expect(await docs.exists("a")).toMatchObject({
      data: false,
      error: { kind: "forbidden" },
    });

    for (const reply of [
      await docs.list(""),
      await docs.listV2(),
      await docs.info("a"),
      await docs.createSignedUrls(["a"], 60),
    ]) {
      expect(fromStorageError(reply.error).kind).toBe("forbidden");
    }

    const thrown = fakeSql([[() => true, { throws: "boom" }]]);

    const download = await supportStorage({
      admin: service.admin,
      sql: thrown.sql,
    })
      .from("docs")
      .download("a");

    expect(fromStorageError(download.error).kind).toBe("unexpected");

    const broken = fakeAdmin();
    broken.bucket["createSignedUrls"] = () =>
      Promise.resolve({
        data: null,
        error: { name: "StorageApiError", message: "down", status: 503 },
      });

    const urls = await supportStorage({
      admin: broken.admin,
      sql: targetSql(["a"]).sql,
    })
      .from("docs")
      .createSignedUrls(["a"], 60);

    expect(urls.error).toMatchObject({ message: "down" });
  });
});

describe("clients over supportStorage", () => {
  const docs = defineBucket({ id: "docs", path: "{organizationId}/{file}" });

  it("serves a connected bucket and walks every listing page", async () => {
    const names = Array.from(
      { length: 1001 },
      (_, index) => `o1/f${String(index).padStart(4, "0")}`,
    );

    const { storage, calls } = docsOf([...names, "o1/sub/deep"]);
    const bucket = docs.connect(storage);
    const all = await bucket.list({ organizationId: "o1" }).orThrow();
    expect(all).toHaveLength(1002);
    expect(all.at(-1)).toMatchObject({ path: "o1/sub/deep", size: 4 });
    expect(await bucket.exists("o1/f0000").orThrow()).toBe(true);
    expect(await bucket.exists("o1/hidden").orThrow()).toBe(false);
    expect(
      await bucket
        .signedUrl("o1/f0001", { ttl: 60, transform: { width: 8 } })
        .orThrow(),
    ).toBe("https://storage.test/sign/o1/f0001");
    expect(calls.at(-1)?.args[2]).toEqual({ transform: { width: 8 } });
    expect((await bucket.download("o1/hidden")).error?.kind).toBe("not_found");
    expect((await bucket.upload("o1/new", "x")).error).toMatchObject({
      kind: "forbidden",
      code: "SUPPORT_READ_ONLY",
    });
    expect((await bucket.remove(["o1/f0000"])).error?.kind).toBe("forbidden");
  });

  it("reserves and claims an upload in a writable session", async () => {
    let uploaded = false;

    const { storage, owner, calls } = writableOf(
      [],
      [
        [
          "insert into",
          () =>
            uploaded ? { throws: pgError("23505", "duplicate key value") } : [],
        ],
      ],
      [["returning name", [{ name: "o1/big.bin" }]]],
    );

    const bucket = docs.connect(storage);
    const reservation = await bucket.reserve("o1/big.bin").orThrow();
    uploaded = true;
    expect(reservation).toEqual({
      path: "o1/big.bin",
      token: "t1",
      signedUrl: "https://storage.test/upload/sign/o1/big.bin?token=t1",
    });
    expect(await bucket.claimReserved(reservation).orThrow()).toEqual({
      path: "o1/big.bin",
    });
    expect(calls.map((call) => call.method)).toEqual(["createSignedUploadUrl"]);
    expect(owner.texts()).toEqual([CLAIM_SQL]);
  });

  it("refuses a reservation and its claim in a read-only session", async () => {
    const { storage, calls } = docsOf([]);
    const bucket = docs.connect(storage);

    for (const result of [
      await bucket.reserve("o1/big.bin"),
      await bucket.claimReserved({ path: "o1/big.bin" }),
    ]) {
      expect(result.error).toMatchObject({
        kind: "forbidden",
        code: "SUPPORT_READ_ONLY",
      });
    }

    expect(calls).toEqual([]);
  });

  it("claims a reservation without a request outside a support session", async () => {
    const service = fakeAdmin();

    expect(
      await docs
        .connect(service.admin)
        .claimReserved({ path: "o1/a" })
        .orThrow(),
    ).toEqual({ path: "o1/a" });
    expect(service.calls).toEqual([]);
  });

  it("reads attachments the target may see", async () => {
    const { storage, calls } = docsOf(["org-1/attachments/a1"]);

    const stored = {
      id: "a1",
      organization_id: "org-1",
      bucket: "attachments",
      object_path: "org-1/attachments/a1",
      name: "plan.pdf",
      mime_type: "application/pdf",
      size: "5",
      status: "clean",
      created_at: "2026-10-06T12:00:00Z",
      uploaded_at: "2026-10-06T12:00:05Z",
    };

    const attachments = createAttachments({
      transport: { call: () => Promise.resolve(stored) },
      storage,
    });

    expect(await attachments.download({ id: "a1" }).orThrow()).toMatchObject({
      signedUrl: "https://storage.test/sign/org-1/attachments/a1",
    });
    const read = await attachments.read("a1").orThrow();
    expect(await read.file.text()).toBe("hi");
    expect(calls.map((call) => call.method)).toEqual([
      "createSignedUrl",
      "download",
    ]);
  });

  it("puts an attachment in a writable session", async () => {
    const { storage, calls, owner } = writableOf([]);
    const called: string[] = [];

    const pending = {
      id: "a2",
      organization_id: "org-1",
      bucket: "attachments",
      object_path: "org-1/attachments/a2",
      name: "note.txt",
      mime_type: "text/plain",
      size: "2",
      status: "pending",
      created_at: "2026-10-06T12:00:00Z",
    };

    const attachments = createAttachments({
      transport: {
        call: (_schema, fn) => {
          called.push(fn);

          return Promise.resolve(pending);
        },
      },
      storage,
      tenant: "org-1",
    });

    const put = await attachments.put({
      subject: null,
      attachment: { name: "note.txt", mimeType: "text/plain", size: 2 },
      file: new Blob(["hi"]),
    });

    expect(put.error).toBeNull();
    expect(called).toEqual(["create_attachment", "confirm_attachment"]);
    expect(calls.map((call) => [call.method, call.args[0]])).toEqual([
      ["upload", "org-1/attachments/a2"],
    ]);
    expect(owner.calls[0]?.values[0]).toBe("attachments");
  });

  it("signs the data exports the target may read", async () => {
    const { storage } = docsOf(["export-1/public.projects.ndjson"]);

    const lifecycle = createDataLifecycle({
      transport: {
        call: () =>
          Promise.resolve({
            id: "export-1",
            user_id: "u1",
            status: "ready",
            bucket: "exports",
            files: [
              "export-1/public.projects.ndjson",
              "export-1/public.hidden.ndjson",
            ],
            requested_at: "2026-10-06T12:00:00Z",
          }),
      },
      storage,
    });

    expect((await lifecycle.download("export-1")).error).toMatchObject({
      kind: "not_found",
    });
    const visible = docsOf(["export-1/public.projects.ndjson"]);

    const one = createDataLifecycle({
      transport: {
        call: () =>
          Promise.resolve({
            id: "export-1",
            status: "ready",
            bucket: "exports",
            files: ["export-1/public.projects.ndjson"],
            requested_at: "2026-10-06T12:00:00Z",
          }),
      },
      storage: visible.storage,
    });

    expect((await one.download("export-1").orThrow()).files).toEqual([
      {
        table: "public.projects",
        url: "https://storage.test/sign/export-1/public.projects.ndjson",
      },
    ]);
  });
});
