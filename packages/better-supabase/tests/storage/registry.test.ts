import { describe, expect, expectTypeOf, it } from "vitest";

import type { Result } from "../../src/core/result.ts";

import {
  avatarBucket,
  defineBucket,
  defineBuckets,
  type StoragePath,
} from "../../src/storage/index.ts";
import { fakeStorage } from "../fixtures/fake-storage.ts";

const files = defineBucket({
  id: "files",
  path: ["{orgId}/files/{fileId}.{ext}", "{orgId}/legacy/{...rest}"],
  policy: "tenant",
  tenant: {},
});
const attachments = defineBucket({
  id: "attachments",
  path: "{orgId}/{messageId}/{name}",
});
const avatars = avatarBucket();

const buckets = defineBuckets({ files, attachments, avatars });

describe("defineBuckets", () => {
  it("lists the registered ids and keeps the definitions by name", () => {
    expect(buckets.ids).toEqual(["files", "attachments", "avatars"]);
    expect(buckets.buckets.files).toBe(files);
    expect(buckets.has("attachments")).toBe(true);
    expect(buckets.has("toString")).toBe(false);
    expectTypeOf(buckets.ids).toEqualTypeOf<
      readonly ("files" | "attachments" | "avatars")[]
    >();
  });

  it("finds a bucket by id and fails closed for an unknown one", () => {
    expect(buckets.byId("attachments")).toEqual({
      ok: true,
      data: attachments,
      error: null,
    });
    for (const id of ["unknown", "", "__proto__", "constructor"]) {
      expect(buckets.byId(id)).toMatchObject({
        ok: false,
        data: null,
        error: {
          kind: "invalid_input",
          message: `Bucket "${id}" is not registered`,
        },
      });
    }
    expectTypeOf(buckets.byId("files")).toEqualTypeOf<Result<typeof files>>();
    expectTypeOf(buckets.byId("x" as string)).toEqualTypeOf<
      Result<typeof files | typeof attachments | typeof avatars>
    >();
  });

  it("refuses two buckets with the same id", () => {
    expect(() =>
      defineBuckets({
        files,
        copy: defineBucket({ id: "files", path: "{a}" }),
      }),
    ).toThrow('defineBuckets: "copy" reuses the bucket id "files"');
  });

  it("resolves a stored reference against the bucket's templates", () => {
    expect(
      buckets.resolve({ bucket: "files", path: "o1/legacy/2023/a.pdf" }),
    ).toEqual({
      ok: true,
      data: { bucket: files, path: "o1/legacy/2023/a.pdf" },
      error: null,
    });
    expect(
      buckets.resolve({ bucket: "attachments", path: "o1/f1.pdf" }),
    ).toMatchObject({
      ok: false,
      error: {
        kind: "invalid_input",
        table: "attachments",
        message: 'Path "o1/f1.pdf" does not match "{orgId}/{messageId}/{name}"',
      },
    });
    expect(
      buckets.resolve({ bucket: "files", path: "o1/files/../x.pdf" }),
    ).toMatchObject({ ok: false, error: { kind: "invalid_input" } });
    expect(buckets.resolve({ bucket: "gone", path: "o1/a/b" })).toMatchObject({
      ok: false,
      error: {
        kind: "invalid_input",
        message: 'Bucket "gone" is not registered',
      },
    });
  });

  it("connects the stored bucket and checks the tenant without a request", async () => {
    const { client, calls } = fakeStorage({
      files: { "files/o1/files/f1.pdf": "x" },
    });
    const ref = buckets.connectStored(
      client,
      { bucket: "files", path: "o1/files/f1.pdf" },
      { tenant: "o1" },
    );
    if (!ref.ok) throw new Error(ref.error.message);
    expect(ref.data.bucket).toBe(files);
    expect(ref.data.path).toBe("o1/files/f1.pdf");
    expect(ref.data.storage.bucket).toBe(files);
    expectTypeOf(ref.data.path).toEqualTypeOf<
      StoragePath<"files" | "attachments" | "avatars">
    >();
    expect(calls).toEqual([]);
    expect(await ref.data.storage.exists(ref.data.path)).toMatchObject({
      ok: true,
      data: true,
    });

    expect(
      buckets.connectStored(
        client,
        { bucket: "files", path: "o2/files/f1.pdf" },
        { tenant: "o1" },
      ),
    ).toMatchObject({
      ok: false,
      error: {
        kind: "forbidden",
        message: 'Path "o2/files/f1.pdf" belongs to another tenant',
      },
    });
    expect(
      buckets.connectStored(client, { bucket: "other", path: "o1/a/b" }),
    ).toMatchObject({ ok: false, error: { kind: "invalid_input" } });
    expect(
      buckets.connectStored(client, { bucket: "attachments", path: "o1/a" }),
    ).toMatchObject({ ok: false, error: { kind: "invalid_input" } });
  });
});
