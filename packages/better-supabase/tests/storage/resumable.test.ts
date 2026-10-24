import { describe, expect, it } from "vitest";

import { defineBucket, resumableEndpoint } from "../../src/storage/index.ts";
import { fakeStorage, storageError } from "../fixtures/fake-storage.ts";

const docs = defineBucket({
  id: "docs",
  path: "{organizationId}/{userId}/{file}",
});

const A = { organizationId: "o1", userId: "u1", file: "a.txt" } as const;

const token = (exp: number): string =>
  [
    "e30",
    Buffer.from(JSON.stringify({ exp })).toString("base64url"),
    "sig",
  ].join(".");

describe("resumableEndpoint", () => {
  it("maps a hosted project to the direct Storage host", () => {
    expect(resumableEndpoint("https://abcdefgh.supabase.co")).toBe(
      "https://abcdefgh.storage.supabase.co/storage/v1/upload/resumable/sign",
    );
    expect(
      resumableEndpoint(
        "https://abcdefgh.supabase.co/storage/v1/object/upload/sign/docs/a.txt?token=t",
      ),
    ).toBe(
      "https://abcdefgh.storage.supabase.co/storage/v1/upload/resumable/sign",
    );
    expect(
      resumableEndpoint("https://abcdefgh.supabase.co/storage/v1", {
        direct: false,
      }),
    ).toBe("https://abcdefgh.supabase.co/storage/v1/upload/resumable/sign");
  });

  it("keeps local stacks, custom domains and the direct host", () => {
    expect(resumableEndpoint("http://127.0.0.1:54321/")).toBe(
      "http://127.0.0.1:54321/storage/v1/upload/resumable/sign",
    );
    expect(
      resumableEndpoint(
        "http://localhost:54321/storage/v1/object/upload/sign/docs/a.txt?token=t",
      ),
    ).toBe("http://localhost:54321/storage/v1/upload/resumable/sign");
    expect(resumableEndpoint("https://api.example.com")).toBe(
      "https://api.example.com/storage/v1/upload/resumable/sign",
    );
    expect(
      resumableEndpoint("https://abcdefgh.storage.supabase.co/storage/v1"),
    ).toBe(
      "https://abcdefgh.storage.supabase.co/storage/v1/upload/resumable/sign",
    );
  });
});

describe("BucketClient.reserveResumable", () => {
  it("returns the TUS endpoint, headers, metadata and expiry", async () => {
    const { client, calls } = fakeStorage();
    const bucket = docs.connect(client);

    expect(
      await bucket.reserveResumable(A, { now: () => 0 }).orThrow(),
    ).toEqual({
      path: "o1/u1/a.txt",
      token: "token-o1/u1/a.txt",
      signedUrl:
        "https://storage.test/storage/v1/object/upload/sign/docs/o1/u1/a.txt?token=token-o1/u1/a.txt",
      bucket: "docs",
      tusEndpoint: "https://storage.test/storage/v1/upload/resumable/sign",
      expiresAt: "1970-01-01T02:00:00.000Z",
      headers: { "x-signature": "token-o1/u1/a.txt", "x-upsert": "false" },
      metadata: { bucketName: "docs", objectName: "o1/u1/a.txt" },
    });

    await bucket.reserveResumable(A, { upsert: true });
    expect(calls.map((call) => call.args[1])).toEqual([
      undefined,
      { upsert: true },
    ]);
  });

  it("reads the expiry from the token and keeps the refusal", async () => {
    const exp = 1_900_000_000;
    const { client } = fakeStorage();

    const signed = {
      storage: {
        from: (id: string) => ({
          ...client.storage.from(id),
          createSignedUploadUrl: async (path: string) => ({
            data: {
              path,
              token: token(exp),
              signedUrl: `https://abcdefgh.supabase.co/storage/v1/object/upload/sign/docs/${path}?token=x`,
            },
            error: null,
          }),
        }),
      },
    };

    const reserved = await docs
      .connect(signed)
      .reserveResumable(A, { upsert: true })
      .orThrow();

    expect(reserved).toMatchObject({
      tusEndpoint:
        "https://abcdefgh.storage.supabase.co/storage/v1/upload/resumable/sign",
      expiresAt: new Date(exp * 1000).toISOString(),
      headers: { "x-upsert": "true" },
    });

    const failing = fakeStorage({
      fail: {
        createSignedUploadUrl: storageError("denied", { statusCode: "403" }),
      },
    });

    expect(
      await docs.connect(failing.client).reserveResumable(A),
    ).toMatchObject({ ok: false, error: { kind: "forbidden" } });
  });
});
