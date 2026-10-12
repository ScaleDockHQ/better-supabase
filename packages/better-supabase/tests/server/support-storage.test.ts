import { describe, expect, it, vi } from "vitest";

import type { SqlCall, SqlRule } from "../fixtures/fake-sql.ts";

import { createAttachments } from "../../src/blocks/attachments/index.ts";
import { createDataLifecycle } from "../../src/blocks/data-lifecycle/index.ts";
import { supportStorage } from "../../src/server/support-storage.ts";
import {
  defineBucket,
  fromStorageError,
  type StorageApi,
  type StorageBucketApi,
} from "../../src/storage/index.ts";
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

/** One folder level of `visible`, folders included, as `storage.search` returns it. */
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
  const sorted = [...visible].sort((a, b) =>
    a.toLowerCase().localeCompare(b.toLowerCase()),
  );
  for (const name of sorted) {
    if (!name.toLowerCase().startsWith(start)) continue;
    const rest = name.slice(prefix.length);
    const slash = rest.indexOf("/");
    if (slash < 0) {
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
    if (seen.has(folder)) continue;
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
    ])
      expect((await docs.listV2(options)).error?.status).toBe(400);
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

    const reversed = fakeSql([[FLAT, [...rows].reverse()]]);
    const unicode = supportStorage({
      admin: fakeAdmin().admin,
      sql: reversed.sql,
    }).from("docs");
    const named = await unicode.listV2({ limit: 1 });
    await unicode.listV2({ cursor: named.data?.nextCursor ?? "" });
    expect(reversed.calls[1]?.values).toEqual(["docs", 1001, "org/é"]);
  });
});

describe("supportStorage writes and failures", () => {
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

  it("refuses every write with 403, read-only or not", async () => {
    for (const [readOnly, code] of [
      [true, "SUPPORT_READ_ONLY"],
      [false, "SUPPORT_STORAGE_WRITES"],
    ] as const) {
      const { docs, calls } = docsOf([], { readOnly });
      for (const write of writes) {
        const reply = await write(docs);
        expect(reply).toMatchObject({
          data: null,
          error: {
            name: "StorageApiError",
            status: 403,
            statusCode: "403",
            code,
          },
        });
        expect(fromStorageError(reply.error, "docs")).toMatchObject({
          kind: "forbidden",
          code,
          table: "docs",
        });
      }
      expect(calls).toEqual([]);
    }
    const { docs } = docsOf([]);
    expect((await docs.upload("a", "x")).error?.message).toBe(
      "The support session is read-only",
    );
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
    ])
      expect(fromStorageError(reply.error).kind).toBe("forbidden");
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
    expect(await attachments.download("a1").orThrow()).toMatchObject({
      signedUrl: "https://storage.test/sign/org-1/attachments/a1",
    });
    const read = await attachments.read("a1").orThrow();
    expect(await read.file.text()).toBe("hi");
    expect(calls.map((call) => call.method)).toEqual([
      "createSignedUrl",
      "download",
    ]);
  });

  it("leaves no pending attachment behind a refused put", async () => {
    const { storage } = docsOf([], { readOnly: false });
    const called: string[] = [];
    const attachments = createAttachments({
      transport: {
        call: (_schema, fn) => {
          called.push(fn);
          return Promise.resolve(
            fn === "create_attachment"
              ? {
                  id: "a2",
                  organization_id: "org-1",
                  bucket: "attachments",
                  object_path: "org-1/attachments/a2",
                  name: "note.txt",
                  mime_type: "text/plain",
                  size: "2",
                  status: "pending",
                  created_at: "2026-10-06T12:00:00Z",
                }
              : true,
          );
        },
      },
      storage,
    });
    const put = await attachments.put(
      {
        organizationId: "org-1",
        name: "note.txt",
        mimeType: "text/plain",
        size: 2,
      },
      new Blob(["hi"]),
    );
    expect(put.error).toMatchObject({
      kind: "forbidden",
      code: "SUPPORT_STORAGE_WRITES",
    });
    expect(called).toEqual(["create_attachment", "delete_attachment"]);
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
