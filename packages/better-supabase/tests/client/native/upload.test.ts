import { describe, expect, it } from "vitest";

import type { UploadBody, UploadOptions } from "../../../src/storage/bucket.ts";

import {
  contentTypeOf,
  uploadFromUri,
} from "../../../src/client/native/upload.ts";
import { AsyncResult, ok } from "../../../src/core/result.ts";

function fakeBucket() {
  const calls: {
    target: string;
    body: UploadBody;
    options?: UploadOptions | undefined;
  }[] = [];
  return {
    calls,
    bucket: {
      upload: (target: string, body: UploadBody, options?: UploadOptions) => {
        calls.push({ target, body, options });
        return new AsyncResult(Promise.resolve(ok({ path: target })));
      },
    },
  };
}

describe("contentTypeOf", () => {
  it("maps extensions, ignoring case, queries and folders with dots", () => {
    expect(contentTypeOf("file:///a/b/photo.JPG")).toBe("image/jpeg");
    expect(contentTypeOf("file:///a/b/doc.pdf?x=1#y")).toBe("application/pdf");
    expect(contentTypeOf("file:///a.dir/file")).toBeUndefined();
    expect(contentTypeOf("file:///a/file.unknown")).toBeUndefined();
  });
});

describe("uploadFromUri", () => {
  it("reads the file and uploads its bytes with a content type", async () => {
    const fake = fakeBucket();
    const result = await uploadFromUri(
      fake.bucket,
      "u1/avatar",
      "file:///tmp/a.png",
      {
        upsert: true,
        fetch: () => Promise.resolve(new Response(new Uint8Array([1, 2, 3]))),
      },
    );
    expect(result.ok).toBe(true);
    const call = fake.calls[0];
    expect(call?.options).toEqual({ upsert: true, contentType: "image/png" });
    expect(call?.body).toBeInstanceOf(ArrayBuffer);
  });

  it("prefers the option, then the extension, then the response header", async () => {
    const fake = fakeBucket();
    const read = () =>
      Promise.resolve(
        new Response("x", { headers: { "content-type": "text/x-custom" } }),
      );
    await uploadFromUri(fake.bucket, "a", "content://a", { fetch: read });
    await uploadFromUri(fake.bucket, "b", "content://b.txt", { fetch: read });
    await uploadFromUri(fake.bucket, "c", "content://c.txt", {
      fetch: read,
      contentType: "image/png",
    });
    expect(fake.calls.map((call) => call.options?.contentType)).toEqual([
      "text/x-custom",
      "text/plain",
      "image/png",
    ]);
  });

  it("returns an error when the file can't be read", async () => {
    const fake = fakeBucket();
    const missing = await uploadFromUri(fake.bucket, "a", "file:///gone.png", {
      fetch: () => Promise.resolve(new Response(null, { status: 404 })),
    });
    expect(missing.error?.kind).toBe("invalid_input");
    const thrown = await uploadFromUri(fake.bucket, "a", "file:///gone.png", {
      fetch: () => Promise.reject(new Error("denied")),
    });
    expect(thrown.ok).toBe(false);
    expect(fake.calls).toEqual([]);
  });
});
