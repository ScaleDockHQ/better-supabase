import { createClient } from "@supabase/supabase-js";
import { describe, expect, expectTypeOf, it, onTestFinished, vi } from "vitest";

import { defineSupabase } from "../../src/core/define.ts";
import { dbError, DbException } from "../../src/core/errors.ts";
import { err, ok } from "../../src/core/result.ts";
import { tenant } from "../../src/plugins/tenant/index.ts";
import {
  defineBucket,
  fromStorageError,
  parseSize,
  type StorageClient,
  type StoragePath,
  TTL,
} from "../../src/storage/index.ts";
import { fakeStorage, storageError } from "../fixtures/fake-storage.ts";
import { schema } from "../fixtures/generated-camel.ts";

const logos = defineBucket({
  id: "customer-logos",
  path: "{orgId}/{customerId}/logo/{version}.webp",
  policy: "tenant",
  fileSizeLimit: "5MiB",
  allowedMimeTypes: ["image/png", "image/*"],
});

describe("defineBucket", () => {
  it("builds, matches and prefixes paths", () => {
    const path = logos.path({ orgId: "o1", customerId: "c1", version: 3 });
    expect(path).toBe("o1/c1/logo/3.webp");
    expect(logos.match(path)).toEqual({
      orgId: "o1",
      customerId: "c1",
      version: "3",
    });
    expect(logos.match("o1/c1/logo/3.png")).toBeNull();
    expect(logos.match("o1/c1/extra/logo/3.webp")).toBeNull();
    expect(logos.prefix({ orgId: "o1" })).toBe("o1");
    expect(logos.prefix({ orgId: "o1", customerId: "c1", version: "x" })).toBe(
      "o1/c1/logo",
    );
    expect(logos.params).toEqual(["orgId", "customerId", "version"]);
  });

  it("rejects unsafe segment values", () => {
    for (const customerId of ["", "..", "a/b", "a\u0000b", "naïve"]) {
      expect(() => logos.path({ orgId: "o1", customerId, version: 1 })).toThrow(
        DbException,
      );
    }
  });

  it("checks size and type", () => {
    expect(logos.check({ size: 5 * 1024 * 1024 + 1 })).toMatchObject({
      kind: "invalid_input",
      status: 413,
      message: "File is larger than 5MiB",
    });
    expect(logos.check({ type: "text/plain" })).toMatchObject({ status: 415 });
    expect(
      logos.check({ size: 10, type: "image/webp; charset=binary" }),
    ).toBeUndefined();
  });

  it("generates idempotent SQL with tenant policies", () => {
    const sql = logos.sql();
    expect(sql).toContain(
      "values ('customer-logos', 'customer-logos', false, 5242880, array['image/png', 'image/*'])",
    );
    expect(sql).toContain(
      'drop policy if exists "bs_customer_logos_insert" on storage.objects;',
    );
    expect(sql).toContain(
      "with check (bucket_id = 'customer-logos' and split_part(name, '/', 1) = (coalesce((select auth.jwt()) ->> 'tenant_id', (select auth.jwt()) -> 'app_metadata' ->> 'tenant_id')) and name ~ '^[^/]+/[^/]+/logo/[^/]+\\.webp$')",
    );
    const owner = defineBucket({
      id: "avatars",
      path: "users/{userId}/{file}",
      policy: "owner",
    }).sql();
    expect(owner).toContain(
      "split_part(name, '/', 2) = (select auth.uid())::text",
    );
    const open = defineBucket({
      id: "public",
      path: "{file}",
      policy: "public",
      public: true,
    }).sql();
    expect(open).not.toContain("for select");
    expect(open).toContain("a select policy would also let anyone list them");
    expect(open).not.toContain("for insert");
    const readable = defineBucket({
      id: "readable",
      path: "{file}",
      policy: "public",
    }).sql();
    expect(readable).toContain(
      "for select to anon, authenticated\n  using (bucket_id = 'readable')",
    );
  });

  it("writes config.toml and detects drift", () => {
    expect(logos.toml()).toBe(
      '[storage.buckets.customer-logos]\npublic = false\nfile_size_limit = "5MiB"\nallowed_mime_types = ["image/png", "image/*"]\n',
    );
    expect(
      logos.drift({
        public: false,
        fileSizeLimit: 5_242_880,
        allowedMimeTypes: ["image/*", "image/png"],
      }),
    ).toEqual([]);
    expect(
      logos
        .drift({ public: true, fileSizeLimit: null, allowedMimeTypes: null })
        .map((drift) => drift.field),
    ).toEqual(["public", "fileSizeLimit", "allowedMimeTypes"]);
    expect(logos.drift(undefined)[0]?.field).toBe("missing");
  });

  it("compiles PermDock policies with list split from read", () => {
    const files = defineBucket({
      id: "org-files",
      path: "{orgId}/{file}",
      policy: {
        permdock: {
          read: "files.read",
          list: "files.list",
          write: "files.write",
        },
        scope: "organization",
      },
    });
    const sql = files.sql();
    const ids = (key: string) =>
      `split_part(name, '/', 1) in (select t.id::text from "permdock"."permitted_organization_ids"('${key}') as t(id))`;
    const listing =
      "storage.allow_any_operation(array['object.list', 'object.list_v2', 's3.object.list'])";
    expect(sql).toContain(
      `create policy "bs_org_files_select" on storage.objects for select to authenticated\n  using (bucket_id = 'org-files' and not ${listing} and ${ids("files.read")});`,
    );
    expect(sql).toContain(
      `create policy "bs_org_files_list" on storage.objects for select to authenticated\n  using (bucket_id = 'org-files' and ${listing} and ${ids("files.list")});`,
    );
    expect(sql).toContain(
      `with check (bucket_id = 'org-files' and ${ids("files.write")} and name ~`,
    );
    expect(sql).toContain(
      `for delete to authenticated\n  using (bucket_id = 'org-files' and ${ids("files.write")});`,
    );
    expect(sql).not.toMatch(/service_role|anon/);

    const global = defineBucket({
      id: "docs",
      path: "{file}",
      policy: {
        permdock: {
          read: "docs.read",
          write: "docs.write",
          delete: "docs.delete",
        },
        scope: "global",
        schema: "authz",
      },
    }).sql();
    expect(global).toContain(
      `using (bucket_id = 'docs' and (select "authz".permdock_has('docs.read')));`,
    );
    expect(global).toContain(`(select "authz".permdock_has('docs.delete'))`);
    expect(global).toContain('drop policy if exists "bs_docs_list"');
    expect(global).not.toContain("allow_any_operation");
    expect(global).not.toContain("service_role");
  });

  it("refuses PermDock keys it cannot compile", () => {
    const bucket = (
      read: string,
      scope = "organization",
      path = "{orgId}/{file}",
    ) =>
      defineBucket({
        id: "x",
        path,
        policy: { permdock: { read, write: "x.write" }, scope },
      });
    expect(() => bucket("files.read#2")).toThrow(/splits by row condition/);
    expect(() => bucket("")).toThrow(/empty/);
    expect(() => bucket("x.read", "org; drop")).toThrow(
      /invalid PermDock scope/,
    );
    expect(() => bucket("x.read", "organization", "{file}")).toThrow(
      /whole path segment/,
    );
  });

  it("refuses PermDock keys the catalog marks with row conditions", () => {
    const catalog = {
      permissions: [
        { key: "files.read", rowConditions: true },
        { key: "files.write", rowConditions: false },
        { key: "files.list", rowConditions: false },
        { key: "files.share" },
      ],
    };
    const bucket = (read: string) =>
      defineBucket({
        id: "x",
        path: "{orgId}/{file}",
        policy: {
          permdock: { read, write: "files.write" },
          scope: "organization",
        },
        catalog,
      });
    expect(() => bucket("files.read")).toThrow(
      /"files\.read" has row conditions in PermDock's catalog/,
    );
    expect(() => bucket("files.share")).toThrow(
      /"files\.share" has no rowConditions flag in PermDock's catalog.*current `permdock catalog`/,
    );
    expect(() => bucket("files.unknown")).toThrow(
      /"files\.unknown" is not in PermDock's catalog/,
    );
    expect(bucket("files.list").sql()).toContain("permitted_organization_ids");
  });

  it("rejects policies that cannot be enforced", () => {
    expect(() =>
      defineBucket({ id: "x", path: "org-{orgId}/{file}", policy: "tenant" }),
    ).toThrow(/whole path segment/);
    expect(() =>
      defineBucket({ id: "x", path: "{a}{b}", policy: "none" }),
    ).toThrow(/adjacent/);
    expect(() => defineBucket({ id: "x", path: "/{a}" })).toThrow(
      /empty segment/,
    );
  });
});

describe("storage helpers", () => {
  it("parses sizes", () => {
    expect(parseSize("5MiB")).toBe(5_242_880);
    expect(parseSize("500KB")).toBe(500_000);
    expect(parseSize(12)).toBe(12);
    expect(() => parseSize("lots")).toThrow('Invalid size "lots"');
  });

  it("maps Storage errors", () => {
    expect(
      fromStorageError({
        name: "StorageApiError",
        message: "new row violates row-level security policy",
        status: 400,
        statusCode: "403",
      }).kind,
    ).toBe("forbidden");
    expect(
      fromStorageError({
        name: "StorageApiError",
        message: "The resource already exists",
        status: 400,
        statusCode: "409",
      }).kind,
    ).toBe("conflict");
    expect(
      fromStorageError({
        name: "StorageApiError",
        message: "Object not found",
        status: 400,
        statusCode: "404",
      }).kind,
    ).toBe("not_found");
    expect(
      fromStorageError({
        name: "StorageApiError",
        message: "Payload too large",
        status: 413,
        statusCode: "413",
      }),
    ).toMatchObject({ kind: "invalid_input", status: 413 });
    expect(
      fromStorageError({ name: "StorageUnknownError", message: "fetch failed" })
        .kind,
    ).toBe("network");
  });
});

describe("renderUrl", () => {
  const URL_BASE = "https://abcdefghijklmnopqrst.supabase.co";
  const client = (fetch: typeof globalThis.fetch) =>
    createClient(URL_BASE, "sb_publishable_test", {
      auth: { persistSession: false, autoRefreshToken: false },
      global: { fetch },
    });
  const transform = {
    width: 320,
    height: 200,
    resize: "cover",
    quality: 70,
  } as const;

  it("builds a /render/image/public URL for public buckets without a request", async () => {
    const fetch = vi.fn<typeof globalThis.fetch>();
    const avatars = defineBucket({
      id: "avatars",
      path: "{userId}/{file}",
      public: true,
      policy: "public",
    }).connect(client(fetch));
    const url = await avatars
      .renderUrl({ userId: "u1", file: "me.webp" }, transform)
      .orThrow();
    expect(fetch).not.toHaveBeenCalled();
    const parsed = new URL(url);
    expect(parsed.pathname).toBe(
      "/storage/v1/render/image/public/avatars/u1/me.webp",
    );
    expect(Object.fromEntries(parsed.searchParams)).toEqual({
      width: "320",
      height: "200",
      resize: "cover",
      quality: "70",
    });
  });

  it("signs a /render/image/sign URL for private buckets", async () => {
    const fetch = vi.fn<typeof globalThis.fetch>(async () =>
      Response.json({
        signedURL:
          "/render/image/sign/customer-logos/o1/c1/logo/3.webp?token=t0k",
      }),
    );
    const url = await logos
      .connect(client(fetch))
      .renderUrl("o1/c1/logo/3.webp", transform, { ttl: "day" })
      .orThrow();
    const [input, init] = fetch.mock.calls[0]!;
    expect(String(input)).toBe(
      `${URL_BASE}/storage/v1/object/sign/customer-logos/o1/c1/logo/3.webp`,
    );
    expect(JSON.parse(String(init?.body))).toEqual({
      expiresIn: 86_400,
      transform,
    });
    expect(url).toBe(
      `${URL_BASE}/storage/v1/render/image/sign/customer-logos/o1/c1/logo/3.webp?token=t0k`,
    );
  });
});

describe("StoragePath", () => {
  it("brands paths with the bucket id", () => {
    const path = logos.path({ orgId: "o1", customerId: "c1", version: 1 });
    expectTypeOf(path).toEqualTypeOf<StoragePath<"customer-logos">>();
    expectTypeOf(path).toExtend<string>();
    const bucket = logos.connect({} as never);
    type Target = Parameters<typeof bucket.exists>[0];
    expectTypeOf(path).toExtend<Target>();
    expectTypeOf("o1/c1/logo/1.webp").toExtend<Target>();
    const avatar = "" as StoragePath<"avatars">;
    const wrongBucket = () =>
      // @ts-expect-error a path from another bucket
      bucket.exists(avatar);
    expectTypeOf(wrongBucket).toBeFunction();
  });
});

describe("defineBucket options", () => {
  it("compiles tenant policies from a SQL expression or one claim", () => {
    const fromSql = defineBucket({
      id: "a",
      path: "{teamId}/{file}",
      policy: "tenant",
      tenant: { param: "teamId", sql: "(select private.team_id())" },
    }).sql();
    expect(fromSql).toContain(
      "split_part(name, '/', 1) = ((select private.team_id()))",
    );
    const fromClaim = defineBucket({
      id: "b",
      path: "x/{orgId}/{file}",
      policy: "tenant",
      tenant: { claim: "app_metadata.org" },
    }).sql();
    expect(fromClaim).toContain(
      "split_part(name, '/', 2) = ((select auth.jwt()) -> 'app_metadata' ->> 'org')",
    );
  });

  it("reports the owner placeholder", () => {
    const custom = defineBucket({
      id: "a",
      path: "{memberId}/{file}",
      policy: "owner",
      owner: { param: "memberId" },
    });
    expect(custom.owner).toBe("memberId");
    expect(custom.sql()).toContain(
      "split_part(name, '/', 1) = (select auth.uid())::text",
    );
    expect(defineBucket({ id: "b", path: "{orgId}/{userId}/{f}" }).owner).toBe(
      "userId",
    );
    expect(
      defineBucket({ id: "c", path: "{orgId}/{f}" }).owner,
    ).toBeUndefined();
  });

  it("uses an explicit PermDock segment", () => {
    const sql = defineBucket({
      id: "a",
      path: "files/{teamId}/{file}",
      policy: {
        permdock: { read: "f.read", write: "f.write" },
        scope: "team",
        segment: 2,
      },
    }).sql();
    expect(sql).toContain(
      `split_part(name, '/', 2) in (select t.id::text from "permdock"."permitted_team_ids"('f.read') as t(id))`,
    );
  });

  it("rejects an unknown policy", () => {
    expect(() =>
      defineBucket({ id: "a", path: "{f}", policy: "everyone" as never }),
    ).toThrow('defineBucket: unknown policy "everyone"');
  });

  it("writes SQL and TOML without limits or policies", () => {
    const plain = defineBucket({ id: "plain", path: "{file}" });
    expect(plain.policy).toBe("none");
    expect(plain.public).toBe(false);
    expect(plain.sql()).toContain(
      "values ('plain', 'plain', false, null, null)",
    );
    expect(plain.sql()).not.toContain("create policy");
    expect(plain.toml()).toBe("[storage.buckets.plain]\npublic = false\n");
    expect(plain.check({ size: 10 ** 12, type: "any/thing" })).toBeUndefined();
    expect(
      plain.drift({
        public: false,
        fileSizeLimit: null,
        allowedMimeTypes: null,
      }),
    ).toEqual([]);
    expect(plain.drift({ public: false })).toEqual([]);
  });

  it("labels numeric size limits in TOML and errors", () => {
    const toml = (fileSizeLimit: number) =>
      defineBucket({ id: "a", path: "{f}", fileSizeLimit }).toml();
    expect(toml(1024)).toContain('file_size_limit = "1KiB"');
    expect(toml(2 * 1024 ** 3)).toContain('file_size_limit = "2GiB"');
    expect(toml(1000)).toContain('file_size_limit = "1000B"');
    expect(
      defineBucket({ id: "a", path: "{f}", fileSizeLimit: 1500 }).check({
        size: 1501,
      })?.message,
    ).toBe("File is larger than 1500B");
  });

  it("matches exact MIME types case-insensitively", () => {
    const text = defineBucket({
      id: "a",
      path: "{f}",
      allowedMimeTypes: ["text/plain"],
    });
    expect(text.check({ type: "TEXT/PLAIN" })).toBeUndefined();
    expect(text.check({ type: "text/plainer" })).toMatchObject({
      status: 415,
      message: "File type text/plainer is not allowed",
    });
    expect(text.check({ type: "" })).toBeUndefined();
  });
});

describe("parseSize", () => {
  it("parses decimals, bare bytes and every unit", () => {
    expect(parseSize("1.5KiB")).toBe(1536);
    expect(parseSize(" 100 ")).toBe(100);
    expect(parseSize("2gb")).toBe(2_000_000_000);
    expect(parseSize("1GiB")).toBe(1024 ** 3);
    expect(parseSize("3B")).toBe(3);
  });

  it("rejects unknown units", () => {
    expect(() => parseSize("5XB")).toThrow('Invalid size "5XB"');
    expect(() => parseSize("")).toThrow(TypeError);
  });
});

describe("fromStorageError", () => {
  it("passes DbErrors through and unwraps DbExceptions", () => {
    const error = dbError("conflict", "taken");
    expect(fromStorageError(error)).toBe(error);
    expect(fromStorageError(new DbException(error))).toBe(error);
  });

  it("maps non-objects and aborts", () => {
    expect(fromStorageError("boom")).toMatchObject({
      kind: "unexpected",
      message: "boom",
    });
    expect(fromStorageError(null).kind).toBe("unexpected");
    expect(
      fromStorageError(new DOMException("stopped", "AbortError")),
    ).toMatchObject({ kind: "aborted", message: "stopped" });
  });

  it.each([
    [{ statusCode: "400" }, "invalid_request"],
    [{ statusCode: "401" }, "unauthorized"],
    [{ statusCode: "403" }, "forbidden"],
    [{ status: 404, statusCode: "NoSuchKey" }, "not_found"],
    [{ status: 409 }, "conflict"],
    [{ statusCode: "415" }, "invalid_input"],
    [{ statusCode: "408" }, "network"],
    [{ status: 429 }, "network"],
    [{ status: 502 }, "network"],
    [{ status: 418 }, "unexpected"],
    [{}, "unexpected"],
    [{ code: "AccessDenied" }, "forbidden"],
    [{ message: "duplicate key" }, "conflict"],
    [{ name: "StorageUnknownError", status: 503 }, "network"],
  ] as const)("maps %j to %s", (fields, kind) => {
    expect(fromStorageError(fields).kind).toBe(kind);
  });

  it("keeps the code, table and status", () => {
    expect(
      fromStorageError({ status: 404, statusCode: "NoSuchKey" }, "docs"),
    ).toEqual({
      kind: "not_found",
      message: "Storage request failed",
      status: 404,
      code: "NoSuchKey",
      table: "docs",
    });
    expect(
      fromStorageError({ statusCode: "429", message: "slow down" }),
    ).toMatchObject({ kind: "network", status: 429, code: "429" });
  });
});

const docs = defineBucket({
  id: "docs",
  path: "{orgId}/{userId}/{file}",
  fileSizeLimit: "1KiB",
  allowedMimeTypes: ["text/plain", "image/*"],
});
const A = { orgId: "o1", userId: "u1", file: "a.txt" } as const;

/** A Storage client whose bucket API is exactly `methods`. */
function stubClient(methods: Record<string, unknown>): StorageClient {
  // SAFETY: each test provides the methods the bucket calls.
  return { storage: { from: () => methods } } as unknown as StorageClient;
}

describe("BucketClient upload and download", () => {
  it("uploads to the templated path with the file options", async () => {
    const { client, files, calls } = fakeStorage();
    const result = await docs.connect(client).upload(A, "hello", {
      contentType: "text/plain",
      cacheControl: "60",
      metadata: { source: "test" },
    });
    expect(result).toEqual(ok({ path: "o1/u1/a.txt" }));
    expect(calls).toEqual([
      {
        bucket: "docs",
        method: "upload",
        args: [
          "o1/u1/a.txt",
          "hello",
          {
            contentType: "text/plain",
            cacheControl: "60",
            metadata: { source: "test" },
            upsert: false,
          },
        ],
      },
    ]);
    expect(files.get("docs/o1/u1/a.txt")?.contentType).toBe("text/plain");
  });

  it("returns a conflict for an existing object unless upsert is set", async () => {
    const { client } = fakeStorage({ files: { "docs/o1/u1/a.txt": "old" } });
    const bucket = docs.connect(client);
    expect(await bucket.upload(A, "new")).toMatchObject({
      ok: false,
      error: { kind: "conflict", table: "docs" },
    });
    expect(
      (await bucket.upload("o1/u1/a.txt", "new", { upsert: true })).ok,
    ).toBe(true);
  });

  it("checks the body against the limits before sending", async () => {
    const { client, calls } = fakeStorage();
    const bucket = docs.connect(client);
    const big = new Uint8Array(1025);
    for (const body of [big, big.buffer, new Blob([big])]) {
      expect(await bucket.upload(A, body)).toMatchObject({
        ok: false,
        error: { kind: "invalid_input", status: 413 },
      });
    }
    expect(
      await bucket.upload(A, new Blob(["%PDF"], { type: "application/pdf" })),
    ).toMatchObject({ ok: false, error: { status: 415 } });
    expect(
      await bucket.upload(A, new Blob(["x"], { type: "image/png" }), {
        contentType: "application/pdf",
      }),
    ).toMatchObject({ ok: false, error: { status: 415 } });
    expect(calls).toEqual([]);
    expect((await bucket.upload(A, new Blob(["x"]))).ok).toBe(true);
  });

  it("rejects paths that do not match the template and aborted signals", async () => {
    const { client, calls } = fakeStorage();
    const bucket = docs.connect(client);
    expect(await bucket.upload("o1/a.txt", "x")).toMatchObject({
      ok: false,
      error: {
        kind: "invalid_input",
        message: 'Path "o1/a.txt" does not match "{orgId}/{userId}/{file}"',
      },
    });
    expect(
      await bucket.upload(A, "x", { signal: AbortSignal.abort() }),
    ).toMatchObject({ ok: false, error: { kind: "aborted" } });
    expect(calls).toEqual([]);
  });

  it("maps thrown fetch failures and empty answers", async () => {
    const { client } = fakeStorage({
      throws: {
        upload: storageError("fetch failed", { name: "StorageUnknownError" }),
      },
    });
    expect(await docs.connect(client).upload(A, "x")).toMatchObject({
      ok: false,
      error: { kind: "network", message: "fetch failed", table: "docs" },
    });
    const empty = stubClient({
      upload: async () => ({ data: null, error: null }),
    });
    expect(await docs.connect(empty).upload(A, "x")).toMatchObject({
      ok: false,
      error: { kind: "unexpected" },
    });
  });

  it("downloads a Blob and passes the signal", async () => {
    const { client, calls } = fakeStorage({
      files: { "docs/o1/u1/a.txt": "hello" },
    });
    const bucket = docs.connect(client);
    const signal = new AbortController().signal;
    const blob = await bucket.download(A, { signal }).orThrow();
    expect(await blob.text()).toBe("hello");
    expect(calls[0]?.args).toEqual(["o1/u1/a.txt", {}, { signal }]);
    await bucket.download(A);
    expect(calls[1]?.args).toEqual(["o1/u1/a.txt", {}, {}]);
    expect(await bucket.download({ ...A, file: "missing.txt" })).toMatchObject({
      ok: false,
      error: { kind: "not_found" },
    });
  });

  it("checks existence", async () => {
    const { client } = fakeStorage({ files: { "docs/o1/u1/a.txt": "x" } });
    const bucket = docs.connect(client);
    expect(await bucket.exists(A)).toEqual(ok(true));
    expect(await bucket.exists({ ...A, file: "b.txt" })).toEqual(ok(false));
    const failing = fakeStorage({
      fail: { exists: storageError("denied", { statusCode: "403" }) },
    });
    expect(await docs.connect(failing.client).exists(A)).toMatchObject({
      ok: false,
      error: { kind: "forbidden", table: "docs" },
    });
  });
});

describe("BucketClient remove and list", () => {
  it("removes objects and skips the request for none", async () => {
    const { client, files, calls } = fakeStorage({
      files: { "docs/o1/u1/a.txt": "a", "docs/o1/u1/b.txt": "b" },
    });
    const bucket = docs.connect(client);
    expect(await bucket.remove([])).toEqual(ok([]));
    expect(calls).toEqual([]);
    expect(await bucket.remove([A, "o1/u1/b.txt"])).toEqual(
      ok(["o1/u1/a.txt", "o1/u1/b.txt"]),
    );
    expect(files.size).toBe(0);
    const failing = fakeStorage({ fail: { remove: storageError("boom") } });
    expect(await docs.connect(failing.client).remove([A])).toMatchObject({
      ok: false,
      error: { kind: "unexpected", message: "boom" },
    });
  });

  it("copies and moves objects within the bucket", async () => {
    const { client, files, calls } = fakeStorage({
      files: { "docs/o1/u1/a.txt": "a" },
    });
    const bucket = docs.connect(client);
    expect(await bucket.copy(A, { ...A, file: "b.txt" })).toEqual(
      ok({ path: "o1/u1/b.txt" }),
    );
    expect(await bucket.move({ ...A, file: "b.txt" }, "o1/u2/c.txt")).toEqual(
      ok({ path: "o1/u2/c.txt" }),
    );
    expect([...files.keys()].sort()).toEqual([
      "docs/o1/u1/a.txt",
      "docs/o1/u2/c.txt",
    ]);
    expect(calls.map((call) => [call.method, ...call.args])).toEqual([
      ["copy", "o1/u1/a.txt", "o1/u1/b.txt"],
      ["move", "o1/u1/b.txt", "o1/u2/c.txt"],
    ]);
    expect(await bucket.copy(A, "o1/u2/c.txt")).toMatchObject({
      ok: false,
      error: { kind: "conflict", table: "docs" },
    });
    expect(await bucket.move("o1/u9/none.txt", A)).toMatchObject({
      ok: false,
      error: { kind: "not_found" },
    });
  });

  it("checks both paths against the template before copying", async () => {
    const { client, calls } = fakeStorage({
      files: { "docs/o1/u1/a.txt": "a" },
    });
    const bucket = docs.connect(client);
    const result = await bucket.copy(A, "not/a/valid/path/at/all.txt");
    expect(result.ok).toBe(false);
    expect(calls).toEqual([]);
  });

  it("lists objects in nested folders with their metadata", async () => {
    const { client, calls } = fakeStorage({
      files: {
        "docs/o1/u1/a.txt": "aaa",
        "docs/o1/u2/b.txt": "b",
        "docs/o2/u1/c.txt": "c",
      },
    });
    const bucket = docs.connect(client);
    await bucket.upload({ ...A, file: "d.png" }, "png", {
      contentType: "image/png",
    });
    expect(await bucket.list().orThrow()).toEqual([
      {
        path: "o1/u1/a.txt",
        size: 3,
        createdAt: "2026-01-01T00:00:00.000Z",
        updatedAt: "2026-01-01T00:00:00.000Z",
      },
      {
        path: "o1/u1/d.png",
        size: 3,
        contentType: "image/png",
        createdAt: "2026-01-01T00:00:00.000Z",
        updatedAt: "2026-01-01T00:00:00.000Z",
      },
      expect.objectContaining({ path: "o1/u2/b.txt" }),
      expect.objectContaining({ path: "o2/u1/c.txt" }),
    ]);
    const within = await bucket.list({ orgId: "o2" }).orThrow();
    expect(within.map((object) => object.path)).toEqual(["o2/u1/c.txt"]);
    expect(calls.findLast((call) => call.method === "list")?.args[0]).toBe(
      "o2/u1",
    );
  });

  it("pages through folders of more than 1000 entries", async () => {
    const files: Record<string, string> = {};
    for (let index = 0; index < 1001; index += 1)
      files[`docs/o1/u1/${String(index).padStart(4, "0")}.txt`] = "x";
    const { client, calls } = fakeStorage({ files });
    const listed = await docs
      .connect(client)
      .list({ orgId: "o1", userId: "u1" });
    expect(listed.ok && listed.data).toHaveLength(1001);
    expect(calls.map((call) => call.args)).toEqual([
      [
        "o1/u1",
        { limit: 1000, offset: 0, sortBy: { column: "name", order: "asc" } },
      ],
      [
        "o1/u1",
        { limit: 1000, offset: 1000, sortBy: { column: "name", order: "asc" } },
      ],
    ]);
  });

  it("omits metadata Storage did not return and passes the signal", async () => {
    const list = vi.fn(async () => ({
      data: [
        {
          name: "a.txt",
          id: "1",
          metadata: null,
          created_at: null,
          updated_at: null,
        },
        {
          name: "b.txt",
          id: "2",
          metadata: { size: "big" },
          created_at: null,
          updated_at: null,
        },
      ],
      error: null,
    }));
    const signal = new AbortController().signal;
    expect(
      await docs.connect(stubClient({ list })).list(A, { signal }).orThrow(),
    ).toEqual([
      { path: "o1/u1/a.txt", createdAt: null, updatedAt: null },
      { path: "o1/u1/b.txt", createdAt: null, updatedAt: null },
    ]);
    expect(list).toHaveBeenCalledWith(
      "o1/u1",
      expect.objectContaining({ offset: 0 }),
      { signal },
    );
  });

  it("returns list failures with the bucket as table", async () => {
    const { client } = fakeStorage({
      fail: { list: storageError("denied", { statusCode: "403" }) },
    });
    expect(await docs.connect(client).list()).toMatchObject({
      ok: false,
      error: { kind: "forbidden", table: "docs" },
    });
    const aborted = await docs
      .connect(fakeStorage().client)
      .list(undefined, { signal: AbortSignal.abort() });
    expect(aborted).toMatchObject({
      ok: false,
      error: { kind: "aborted", table: "docs" },
    });
  });
});

describe("BucketClient URLs", () => {
  it("signs a URL with a TTL, download name and transform", async () => {
    const { client, calls } = fakeStorage();
    const bucket = docs.connect(client);
    expect(await bucket.signedUrl(A).orThrow()).toBe(
      "https://storage.test/sign/docs/o1/u1/a.txt?ttl=3600",
    );
    await bucket.signedUrl(A, { ttl: "week", download: "a.txt" });
    await bucket.signedUrl(A, {
      ttl: 30,
      download: true,
      transform: { width: 10 },
    });
    expect(calls.map((call) => call.args.slice(1))).toEqual([
      [TTL.hour, {}],
      [TTL.week, { download: "a.txt" }],
      [30, { download: true, transform: { width: 10 } }],
    ]);
    const failing = fakeStorage({
      fail: { createSignedUrl: storageError("nope", { statusCode: "404" }) },
    });
    expect(await docs.connect(failing.client).signedUrl(A)).toMatchObject({
      ok: false,
      error: { kind: "not_found" },
    });
  });

  it("reuses a signed URL per connection when asked, until it nears expiry", async () => {
    vi.useFakeTimers();
    try {
      const { client, calls } = fakeStorage();
      const cached = docs.connect(client, { cacheSignedUrls: true });
      await cached.signedUrl(A, { ttl: 600 });
      await cached.signedUrl(A, { ttl: 600 });
      await cached.signedUrl(A, { ttl: 600, download: true });
      expect(calls).toHaveLength(2);
      vi.advanceTimersByTime(541_000);
      await cached.signedUrl(A, { ttl: 600 });
      expect(calls).toHaveLength(3);
      await docs.connect(client).signedUrl(A, { ttl: 600 });
      await docs.connect(client).signedUrl(A, { ttl: 600 });
      expect(calls).toHaveLength(5);
    } finally {
      vi.useRealTimers();
    }
  });

  it("signs many URLs and fails when one is missing", async () => {
    const { client, calls } = fakeStorage({
      files: { "docs/o1/u1/a.txt": "a", "docs/o1/u1/b.txt": "b" },
    });
    const bucket = docs.connect(client);
    expect(await bucket.signedUrls([])).toEqual(ok([]));
    expect(calls).toEqual([]);
    expect(
      await bucket
        .signedUrls([A, "o1/u1/b.txt"], { ttl: "minute", download: true })
        .orThrow(),
    ).toEqual([
      "https://storage.test/sign/docs/o1/u1/a.txt?ttl=60",
      "https://storage.test/sign/docs/o1/u1/b.txt?ttl=60",
    ]);
    expect(calls[0]?.args.slice(1)).toEqual([60, { download: true }]);
    expect(await bucket.signedUrls([A, { ...A, file: "c.txt" }])).toMatchObject(
      {
        ok: false,
        error: {
          kind: "not_found",
          message:
            "Either the object does not exist or you do not have access to it",
          table: "docs",
        },
      },
    );
    const blank = stubClient({
      createSignedUrls: async (paths: string[]) => ({
        data: paths.map((path) => ({ path, error: null, signedUrl: "" })),
        error: null,
      }),
    });
    expect(await docs.connect(blank).signedUrls([A])).toMatchObject({
      ok: false,
      error: { kind: "not_found", message: "No URL for o1/u1/a.txt" },
    });
  });

  it("builds public and render URLs without a request", async () => {
    const getPublicUrl = vi.fn((path: string, options: unknown) => ({
      data: {
        publicUrl: `https://cdn.test/${path}?${JSON.stringify(options)}`,
      },
    }));
    const createSignedUrl = vi.fn();
    const images = defineBucket({
      id: "images",
      path: "{file}",
      public: true,
      policy: "public",
    }).connect(stubClient({ getPublicUrl, createSignedUrl }));
    expect(images.publicUrl("a.png")).toBe("https://cdn.test/a.png?{}");
    images.publicUrl("a.png", { download: "a.png", transform: { width: 5 } });
    expect(
      await images
        .renderUrl("a.png", { height: 4 }, { download: true })
        .orThrow(),
    ).toBe('https://cdn.test/a.png?{"download":true,"transform":{"height":4}}');
    await images.renderUrl("a.png", { height: 4 });
    expect(getPublicUrl.mock.calls.map((call) => call[1])).toEqual([
      {},
      { download: "a.png", transform: { width: 5 } },
      { download: true, transform: { height: 4 } },
      { transform: { height: 4 } },
    ]);
    expect(createSignedUrl).not.toHaveBeenCalled();
    expect(() => images.publicUrl("a/b.png")).toThrow(DbException);
  });
});

describe("BucketClient replace", () => {
  const B = { ...A, file: "b.txt" } as const;

  it("uploads, commits, then removes the previous object", async () => {
    const { client, files } = fakeStorage({
      files: { "docs/o1/u1/a.txt": "old" },
    });
    const commit = vi.fn(() => ok(undefined));
    const result = await docs
      .connect(client)
      .replace(B, "new", { previous: "o1/u1/a.txt", commit });
    expect(result).toEqual(ok({ path: "o1/u1/b.txt", removed: "o1/u1/a.txt" }));
    expect(commit).toHaveBeenCalledWith("o1/u1/b.txt");
    expect([...files.keys()]).toEqual(["docs/o1/u1/b.txt"]);
  });

  it("overwrites in place when the path is unchanged", async () => {
    const { client, files, calls } = fakeStorage({
      files: { "docs/o1/u1/a.txt": "old" },
    });
    const result = await docs.connect(client).replace(A, "new", {
      previous: "o1/u1/a.txt",
      signal: new AbortController().signal,
    });
    expect(result).toEqual(ok({ path: "o1/u1/a.txt", removed: null }));
    expect(files.get("docs/o1/u1/a.txt")?.body).toBe("new");
    expect(calls.map((call) => call.method)).toEqual(["upload"]);
    expect(calls[0]?.args[2]).toMatchObject({ upsert: true });
  });

  it("uploads without a previous object or options", async () => {
    const { client } = fakeStorage();
    expect(await docs.connect(client).replace(A, "x")).toEqual(
      ok({ path: "o1/u1/a.txt", removed: null }),
    );
  });

  it("removes the new object and keeps the previous one when commit fails", async () => {
    const failure = dbError("conflict", "row changed");
    for (const commit of [
      () => err(failure),
      async () => err(failure),
      () => {
        throw new DbException(failure);
      },
    ]) {
      const { client, files } = fakeStorage({
        files: { "docs/o1/u1/a.txt": "old" },
      });
      const result = await docs
        .connect(client)
        .replace(B, "new", { previous: "o1/u1/a.txt", commit });
      expect(result).toEqual(err(failure));
      expect([...files.keys()]).toEqual(["docs/o1/u1/a.txt"]);
    }
  });

  it("keeps the overwritten object when commit fails on the same path", async () => {
    const { client, files, calls } = fakeStorage({
      files: { "docs/o1/u1/a.txt": "old" },
    });
    const result = await docs.connect(client).replace(A, "new", {
      previous: "o1/u1/a.txt",
      commit: () => {
        throw new Error("db down");
      },
    });
    expect(result).toMatchObject({
      ok: false,
      error: { kind: "unexpected", message: "db down" },
    });
    expect(files.has("docs/o1/u1/a.txt")).toBe(true);
    expect(calls.map((call) => call.method)).toEqual(["upload"]);
  });

  it("returns an upload failure without committing", async () => {
    const { client } = fakeStorage({ files: { "docs/o1/u1/b.txt": "taken" } });
    const commit = vi.fn();
    expect(
      await docs.connect(client).replace(B, "new", { commit }),
    ).toMatchObject({ ok: false, error: { kind: "conflict" } });
    expect(commit).not.toHaveBeenCalled();
  });

  it("reports a previous object it could not remove as cleanup", async () => {
    const { client, files } = fakeStorage({
      files: { "docs/o1/u1/a.txt": "old" },
      fail: { remove: storageError("denied", { statusCode: "403" }) },
    });
    const result = await docs
      .connect(client)
      .replace(B, "new", { previous: "o1/u1/a.txt" });
    expect(result).toMatchObject({
      ok: true,
      data: {
        path: "o1/u1/b.txt",
        removed: null,
        cleanup: { kind: "forbidden" },
      },
    });
    expect(files.size).toBe(2);
  });
});

describe("BucketClient signed uploads", () => {
  it("reserves a signed upload URL", async () => {
    const { client, calls } = fakeStorage();
    const bucket = docs.connect(client);
    expect(await bucket.reserve(A).orThrow()).toEqual({
      path: "o1/u1/a.txt",
      token: "token-o1/u1/a.txt",
      signedUrl: "https://storage.test/upload/docs/o1/u1/a.txt",
    });
    await bucket.reserve(A, { upsert: true });
    expect(calls.map((call) => call.args[1])).toEqual([
      undefined,
      { upsert: true },
    ]);
    const failing = fakeStorage({
      fail: {
        createSignedUploadUrl: storageError("denied", { statusCode: "403" }),
      },
    });
    expect(await docs.connect(failing.client).reserve(A)).toMatchObject({
      ok: false,
      error: { kind: "forbidden" },
    });
  });

  it("uploads to a reservation after checking the limits", async () => {
    const { client, files, calls } = fakeStorage();
    const bucket = docs.connect(client);
    const reservation = await bucket.reserve(A).orThrow();
    expect(
      await bucket.uploadReserved(reservation, "hello", {
        contentType: "text/plain",
      }),
    ).toEqual(ok({ path: "o1/u1/a.txt" }));
    expect(calls[1]?.args).toEqual([
      "o1/u1/a.txt",
      "token-o1/u1/a.txt",
      "hello",
      { contentType: "text/plain", upsert: false },
    ]);
    expect(files.get("docs/o1/u1/a.txt")?.body).toBe("hello");

    expect(
      await bucket.uploadReserved(reservation, new Uint8Array(2048)),
    ).toMatchObject({ ok: false, error: { status: 413 } });
    expect(
      await bucket.uploadReserved(reservation, "x", {
        signal: AbortSignal.abort(),
      }),
    ).toMatchObject({ ok: false, error: { kind: "aborted" } });
    expect(
      await bucket.uploadReserved({ path: "elsewhere", token: "t" }, "x"),
    ).toMatchObject({ ok: false, error: { kind: "invalid_input" } });
    expect(calls).toHaveLength(2);

    const failing = fakeStorage({
      fail: {
        uploadToSignedUrl: storageError("expired", { statusCode: "400" }),
      },
    });
    expect(
      await docs.connect(failing.client).uploadReserved(reservation, "x"),
    ).toMatchObject({ ok: false, error: { kind: "invalid_request" } });
  });
});

describe("BucketClient sweep", () => {
  const NOW = Temporal.Instant.from("2026-01-02T00:00:00Z");
  const files = () =>
    fakeStorage({
      files: {
        "docs/o1/u1/a.txt": "a",
        "docs/o1/u1/b.txt": "b",
        "docs/o1/u2/c.txt": "c",
        "docs/o1/stray.txt": "s",
      },
    });

  it("removes unreferenced objects that match the template and are old enough", async () => {
    const storage = files();
    const referenced = vi.fn((paths: readonly string[]) =>
      paths.filter((path) => path === "o1/u1/a.txt"),
    );
    const result = await docs.connect(storage.client).sweep({
      olderThan: Temporal.Duration.from({ hours: 1 }),
      now: () => NOW,
      referenced,
    });
    expect(result).toEqual(
      ok({
        scanned: 4,
        orphans: ["o1/u1/b.txt", "o1/u2/c.txt"],
        removed: ["o1/u1/b.txt", "o1/u2/c.txt"],
      }),
    );
    expect(referenced).toHaveBeenCalledWith([
      "o1/u1/a.txt",
      "o1/u1/b.txt",
      "o1/u2/c.txt",
    ]);
    expect([...storage.files.keys()].toSorted()).toEqual([
      "docs/o1/stray.txt",
      "docs/o1/u1/a.txt",
    ]);
  });

  it("keeps objects newer than the cutoff", async () => {
    const storage = files();
    const bucket = docs.connect(storage.client);
    const referenced = vi.fn(() => []);
    expect(
      await bucket.sweep({
        olderThan: Temporal.Duration.from({ days: 2 }),
        now: () => NOW,
        referenced,
      }),
    ).toEqual(ok({ scanned: 4, orphans: [], removed: [] }));
    expect(
      await bucket.sweep({
        olderThan: Temporal.Instant.from("2025-12-31T00:00:00Z"),
        referenced,
      }),
    ).toEqual(ok({ scanned: 4, orphans: [], removed: [] }));
    expect(referenced).not.toHaveBeenCalled();
    const old = await bucket.sweep({
      olderThan: Temporal.Instant.from("2026-01-02T00:00:00Z"),
      referenced: async () => new Set(["o1/u1/a.txt", "o1/u1/b.txt"]),
    });
    expect(old.ok && old.data.removed).toEqual(["o1/u2/c.txt"]);
  });

  it("returns an error instead of throwing when Temporal is missing", async () => {
    const bucket = docs.connect(files().client);
    const olderThan = Temporal.Duration.from({ hours: 1 });
    vi.stubGlobal("Temporal", undefined);
    onTestFinished(() => {
      vi.unstubAllGlobals();
    });
    const result = await bucket.sweep({ olderThan, referenced: () => [] });
    expect(result.error).toMatchObject({ kind: "unexpected" });
  });

  it("uses the real clock by default", async () => {
    const storage = files();
    const result = await docs.connect(storage.client).sweep({
      olderThan: Temporal.Duration.from({ seconds: 1 }),
      referenced: () => [],
      dryRun: true,
    });
    expect(result.ok && result.data.orphans).toHaveLength(3);
  });

  it("reports orphans without removing them on a dry run", async () => {
    const storage = files();
    const result = await docs.connect(storage.client).sweep({
      olderThan: Temporal.Duration.from({ seconds: 0 }),
      now: () => NOW,
      referenced: () => [],
      dryRun: true,
    });
    expect(result.ok && result.data).toEqual({
      scanned: 4,
      orphans: ["o1/u1/a.txt", "o1/u1/b.txt", "o1/u2/c.txt"],
      removed: [],
    });
    expect(storage.calls.some((call) => call.method === "remove")).toBe(false);
    expect(storage.files.size).toBe(4);
  });

  it("checks and removes in batches, within a prefix", async () => {
    const storage = files();
    const referenced = vi.fn((paths: readonly string[]) =>
      paths.filter((path) => path.endsWith("a.txt")),
    );
    const result = await docs.connect(storage.client).sweep({
      within: { orgId: "o1", userId: "u1" },
      olderThan: Temporal.Duration.from({ seconds: 0 }),
      now: () => NOW,
      batchSize: 1,
      referenced,
      signal: new AbortController().signal,
    });
    expect(result.ok && result.data).toEqual({
      scanned: 2,
      orphans: ["o1/u1/b.txt"],
      removed: ["o1/u1/b.txt"],
    });
    expect(referenced.mock.calls).toEqual([
      [["o1/u1/a.txt"]],
      [["o1/u1/b.txt"]],
    ]);
    expect(
      storage.calls
        .filter((call) => call.method === "remove")
        .map((call) => call.args[0]),
    ).toEqual([["o1/u1/b.txt"]]);
  });

  it("skips objects without a usable date and falls back to updatedAt", async () => {
    const list = async () => ({
      data: [
        {
          name: "a.txt",
          id: "1",
          metadata: {},
          created_at: null,
          updated_at: "2025-01-01T00:00:00Z",
        },
        {
          name: "b.txt",
          id: "2",
          metadata: {},
          created_at: null,
          updated_at: null,
        },
        {
          name: "c.txt",
          id: "3",
          metadata: {},
          created_at: "not a date",
          updated_at: null,
        },
      ],
      error: null,
    });
    const result = await docs.connect(stubClient({ list })).sweep({
      within: { orgId: "o1", userId: "u1" },
      olderThan: Temporal.Duration.from({ seconds: 0 }),
      now: () => NOW,
      referenced: () => [],
      dryRun: true,
    });
    expect(result.ok && result.data.orphans).toEqual(["o1/u1/a.txt"]);
  });

  it("returns list and remove failures", async () => {
    const listing = fakeStorage({
      fail: { list: storageError("denied", { statusCode: "403" }) },
    });
    expect(
      await docs.connect(listing.client).sweep({
        olderThan: Temporal.Duration.from({ seconds: 0 }),
        referenced: () => [],
      }),
    ).toMatchObject({ ok: false, error: { kind: "forbidden" } });

    const storage = fakeStorage({
      files: { "docs/o1/u1/a.txt": "a" },
      fail: { remove: storageError("boom", { statusCode: "500" }) },
    });
    expect(
      await docs.connect(storage.client).sweep({
        olderThan: Temporal.Duration.from({ seconds: 0 }),
        now: () => NOW,
        referenced: () => [],
      }),
    ).toMatchObject({ ok: false, error: { kind: "network" } });

    expect(
      await docs.connect(files().client).sweep({
        olderThan: Temporal.Duration.from({ seconds: 0 }),
        referenced: () => [],
        signal: AbortSignal.abort(),
      }),
    ).toMatchObject({ ok: false, error: { kind: "aborted" } });
  });
});

describe("tenant-scoped buckets", () => {
  const scoped = defineBucket({
    id: "scoped",
    path: "{orgId}/{userId}/{file}",
    tenant: {},
  });
  const mine = { orgId: "o1", userId: "u1", file: "a.txt" } as const;
  const theirs = { orgId: "o2", userId: "u1", file: "a.txt" } as const;

  it("names the tenant placeholder and rejects one the template lacks", () => {
    expect(scoped.tenant).toBe("orgId");
    expect(docs.tenant).toBeUndefined();
    expect(() =>
      defineBucket({ id: "x", path: "{teamId}/{file}", tenant: {} }),
    ).toThrow('defineBucket: tenant.param {orgId} is not in "{teamId}/{file}"');
  });

  it("refuses other tenants' paths before any Storage call", async () => {
    const { client, calls } = fakeStorage({
      files: { "scoped/o2/u1/a.txt": "x" },
    });
    const storage = scoped.connect(client, { tenant: "o1" });
    const refused = {
      ok: false,
      error: { kind: "forbidden", table: "scoped" },
    };
    expect(await storage.upload(theirs, "x")).toMatchObject(refused);
    expect(await storage.upload("o2/u1/b.txt", "x")).toMatchObject(refused);
    expect(await storage.download(theirs)).toMatchObject(refused);
    expect(await storage.signedUrl(theirs)).toMatchObject(refused);
    expect(await storage.signedUrls([mine, theirs])).toMatchObject(refused);
    expect(await storage.remove([theirs])).toMatchObject(refused);
    expect(await storage.reserve(theirs)).toMatchObject(refused);
    expect(await storage.list({ orgId: "o2" })).toMatchObject(refused);
    expect(storage.path(theirs)).toMatchObject({
      ok: false,
      error: {
        kind: "forbidden",
        message: 'Path "o2/u1/a.txt" belongs to another tenant',
      },
    });
    expect(calls).toEqual([]);
    expect(storage.path(mine)).toEqual({
      ok: true,
      data: "o1/u1/a.txt",
      error: null,
    });
    expect((await storage.upload(mine, "x")).ok).toBe(true);
  });

  it("lists only under the caller's tenant", async () => {
    const { client } = fakeStorage({
      files: { "scoped/o1/u1/a.txt": "x", "scoped/o2/u1/a.txt": "y" },
    });
    const listed = await scoped.connect(client, { tenant: "o1" }).list();
    expect(listed.ok && listed.data.map((object) => object.path)).toEqual([
      "o1/u1/a.txt",
    ]);
  });

  it("reads the tenant from the request context, and fails closed without one", async () => {
    const { client, calls } = fakeStorage();
    const fromClaims = scoped.connect(client, {
      context: { claims: { tenant_id: "o1" } },
    });
    expect((await fromClaims.upload(mine, "x")).ok).toBe(true);
    const fromContext = scoped.connect(client, { context: { tenant: "o2" } });
    expect(await fromContext.upload(mine, "x")).toMatchObject({
      ok: false,
      error: { kind: "forbidden" },
    });
    const custom = defineBucket({
      id: "scoped",
      path: "{orgId}/{file}",
      tenant: { claim: "app_metadata.org" },
    });
    expect(
      custom
        .connect(client, {
          context: { claims: { app_metadata: { org: "o3" } } },
        })
        .path({ orgId: "o3", file: "a" }).ok,
    ).toBe(true);
    const before = calls.length;
    const anonymous = scoped.connect(client, { context: {} });
    expect(await anonymous.list()).toMatchObject({
      ok: false,
      error: {
        kind: "forbidden",
        message:
          'No tenant for bucket "scoped": pass { context } or { tenant } to connect(), or { allTenants: true }',
      },
    });
    expect(await scoped.connect(client).upload(mine, "x")).toMatchObject({
      ok: false,
      error: { kind: "forbidden" },
    });
    expect(calls).toHaveLength(before);
  });

  it("uses the tenant tenant() resolved from a custom claim path", async () => {
    const { client } = fakeStorage();
    const db = defineSupabase(schema)
      .use(tenant({ claim: "app_metadata.org" }))
      .connect(
        {
          name: "echo",
          execute: () => Promise.resolve(ok({ rows: [], count: null })),
        },
        { claims: { tenant_id: "o1", app_metadata: { org: "o9" } } },
      );
    const storage = scoped.connect(client, { context: db.$context });
    expect(storage.path({ orgId: "o9", userId: "u1", file: "a" }).ok).toBe(
      true,
    );
    expect(storage.path(mine)).toMatchObject({
      ok: false,
      error: { kind: "forbidden" },
    });
  });

  it("lets admin work cross tenants with allTenants", async () => {
    const { client } = fakeStorage();
    const admin = scoped.connect(client, { allTenants: true });
    expect((await admin.upload(theirs, "x")).ok).toBe(true);
    expect((await admin.upload(mine, "x")).ok).toBe(true);
  });
});
