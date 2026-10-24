import { afterEach, describe, expect, it, vi } from "vitest";

import type { StorageApi, StorageResponse } from "../../src/storage/index.ts";

import { ok } from "../../src/core/result.ts";
import { defineBucket } from "../../src/storage/index.ts";
import { sendable, xhrUpload } from "../../src/storage/progress.ts";
import { fakeStorage } from "../fixtures/fake-storage.ts";

type Outcome =
  | { readonly status: number; readonly text?: string }
  | "error"
  | "hang";

const sent: FakeXhr[] = [];
let outcome: Outcome = { status: 200 };

interface Progress {
  readonly loaded: number;
  readonly total: number;
  readonly lengthComputable: boolean;
}

class FakeUpload {
  readonly listeners: ((event: Progress) => void)[] = [];
  addEventListener(_type: "progress", listener: (event: Progress) => void) {
    this.listeners.push(listener);
  }
  progress(loaded: number, total: number) {
    for (const listener of this.listeners) {
      listener({ loaded, total, lengthComputable: total > 0 });
    }
  }
}

class FakeXhr extends EventTarget {
  method = "";
  url = "";
  headers: Record<string, string> = {};
  body: unknown;
  status = 0;
  responseText = "";
  aborted = false;
  upload = new FakeUpload();
  open(method: string, url: string) {
    this.method = method;
    this.url = url;
  }
  setRequestHeader(name: string, value: string) {
    this.headers[name] = value;
  }
  abort() {
    this.aborted = true;
    this.dispatchEvent(new Event("abort"));
  }
  send(body: unknown) {
    this.body = body;
    sent.push(this);
    const current = outcome;
    queueMicrotask(() => {
      if (current === "hang") {
        return;
      }

      if (current === "error") {
        this.dispatchEvent(new Event("error"));

        return;
      }

      this.upload.progress(0, 0);
      this.upload.progress(5, 10);
      this.status = current.status;
      this.responseText = current.text ?? "";
      this.dispatchEvent(new Event("load"));
    });
  }
}

const docs = defineBucket({
  id: "docs",
  path: "{organizationId}/{file}",
  fileSizeLimit: "1KiB",
});

const A = { organizationId: "o1", file: "a.txt" } as const;

afterEach(() => {
  vi.unstubAllGlobals();
  sent.length = 0;
  outcome = { status: 200 };
});

describe("upload progress", () => {
  it("reports 1 after a storage-js upload when XMLHttpRequest is missing", async () => {
    const { client } = fakeStorage();
    const progress: number[] = [];

    const result = await docs
      .connect(client)
      .upload(A, "hello", { onProgress: (value) => progress.push(value) });

    expect(result).toEqual(ok({ path: "o1/a.txt" }));
    expect(progress).toEqual([1]);
  });

  it("PUTs to a signed upload URL with progress events", async () => {
    vi.stubGlobal("XMLHttpRequest", FakeXhr);
    const { client, calls } = fakeStorage();
    const progress: number[] = [];
    const body = new Blob(["hello"], { type: "text/plain" });

    const result = await docs
      .connect(client)
      .upload(A, body, {
        upsert: true,
        cacheControl: "60",
        onProgress: (value) => progress.push(value),
      });

    expect(result).toEqual(ok({ path: "o1/a.txt" }));
    expect(progress).toEqual([0.5, 1]);
    expect(calls.map((call) => call.method)).toEqual(["createSignedUploadUrl"]);
    expect(sent[0]).toMatchObject({
      method: "PUT",
      url: "https://storage.test/storage/v1/object/upload/sign/docs/o1/a.txt?token=token-o1/a.txt",
      headers: {
        "x-upsert": "true",
        "cache-control": "max-age=60",
        "content-type": "text/plain",
      },
      body,
    });
  });

  it("maps failed and erroring requests and keeps metadata uploads on storage-js", async () => {
    vi.stubGlobal("XMLHttpRequest", FakeXhr);
    const { client, calls } = fakeStorage();
    const bucket = docs.connect(client);
    outcome = {
      status: 403,
      text: JSON.stringify({ statusCode: "403", message: "denied" }),
    };
    expect(
      await bucket.upload(A, "x", { onProgress: () => undefined }),
    ).toMatchObject({
      ok: false,
      error: { kind: "forbidden", message: "denied" },
    });
    outcome = { status: 500, text: "oops" };
    expect(
      await bucket.upload(A, "x", { onProgress: () => undefined }),
    ).toMatchObject({
      ok: false,
      error: { message: "Upload failed with status 500" },
    });
    outcome = "error";
    expect(
      await bucket.upload(A, "x", { onProgress: () => undefined }),
    ).toMatchObject({ ok: false, error: { kind: "network" } });
    await bucket.upload(A, "x", {
      metadata: { a: 1 },
      onProgress: () => undefined,
    });
    expect(calls.at(-1)?.method).toBe("upload");
  });

  it("claims the uploaded object when Storage has a claim step", async () => {
    vi.stubGlobal("XMLHttpRequest", FakeXhr);
    const { client, calls } = fakeStorage();
    const claimed: string[] = [];

    const claiming = (
      reply: StorageResponse<{ readonly path: string }>,
    ): StorageApi => ({
      from: (bucket) => client.storage.from(bucket),
      claimSignedUpload: (_bucket, path) => {
        claimed.push(path);

        return Promise.resolve(reply);
      },
    });

    expect(
      await docs
        .connect(claiming({ data: { path: "o1/a.txt" }, error: null }))
        .upload(A, "x", { onProgress: () => undefined }),
    ).toEqual(ok({ path: "o1/a.txt" }));
    expect(claimed).toEqual(["o1/a.txt"]);

    expect(
      await docs
        .connect(
          claiming({
            data: null,
            error: {
              name: "StorageApiError",
              message: "taken",
              status: 403,
              statusCode: "403",
            },
          }),
        )
        .upload(A, "x", { onProgress: () => undefined }),
    ).toMatchObject({ ok: false, error: { kind: "forbidden" } });
    expect(calls.some((call) => call.method === "remove")).toBe(false);
  });

  it("cancels the request on abort", async () => {
    vi.stubGlobal("XMLHttpRequest", FakeXhr);
    outcome = "hang";
    const controller = new AbortController();

    const pending = xhrUpload(FakeXhr, "https://x", "body", {
      upsert: false,
      signal: controller.signal,
      onProgress: () => undefined,
    });

    controller.abort();
    expect(await pending).toMatchObject({ name: "AbortError" });
    expect(sent[0]!.aborted).toBe(true);
    expect(sent[0]!.headers["content-type"]).toBeUndefined();
  });

  it("sends everything but streams", () => {
    expect(sendable("x")).toBe(true);
    expect(sendable(new ReadableStream())).toBe(false);
  });
});
