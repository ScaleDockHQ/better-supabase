import { afterEach, describe, expect, it, vi } from "vitest";

import type { BlockCall } from "../../../src/core/block-helpers.ts";
import type { FileStore } from "../../../src/storage/file-store.ts";

import {
  confirmInStore,
  sendToSignedUrl,
  signUpload,
} from "../../../src/blocks/attachments/files.ts";
import { dbError } from "../../../src/core/errors.ts";
import { AsyncResult, ok } from "../../../src/core/result.ts";
import { vercelBlobStore } from "../../../src/storage/file-store.ts";
import { fakeBlobModule } from "../../fixtures/file-stores.ts";

const FILE = {
  id: "att_1",
  bucket: "attachments",
  path: "org_1/attachments/att_1",
  mimeType: "text/plain",
  size: 5,
};

const blobStore = (): FileStore => vercelBlobStore(fakeBlobModule().module);

function without(key: "head" | "signedUploadUrl"): FileStore {
  const store = { ...blobStore() };

  delete store[key];

  return store;
}

const noService: BlockCall = () =>
  AsyncResult.err(dbError("unexpected", "must not be called"));

afterEach(() => {
  vi.unstubAllGlobals();
});

describe("signUpload", () => {
  it("refuses a store without signedUploadUrl with the block's hint", async () => {
    const signed = await signUpload(
      without("signedUploadUrl"),
      FILE,
      "ATTACHMENT_UPLOAD_FAILED",
    );

    expect(signed.ok ? undefined : signed.error).toMatchObject({
      kind: "invalid_request",
      hint: "ATTACHMENT_UPLOAD_FAILED",
    });
  });
});

describe("sendToSignedUrl", () => {
  const ticket = { signedUrl: "https://blob.test/upload", token: "" };

  it("reports a fetch that throws and a store that refuses as upload failures", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn(() => Promise.reject(new TypeError("fetch failed"))),
    );

    const offline = await sendToSignedUrl(ticket, new Blob(["hello"]));

    expect(offline.ok ? undefined : offline.error).toMatchObject({
      kind: "network",
      hint: "ATTACHMENT_UPLOAD_FAILED",
    });

    vi.stubGlobal(
      "fetch",
      vi.fn(() => Promise.resolve(new Response(null, { status: 413 }))),
    );

    const refused = await sendToSignedUrl(
      { ...ticket, method: "POST", headers: { "x-api-version": "11" } },
      new Blob(["hello"], { type: "text/plain" }),
    );

    expect(refused.ok ? undefined : refused.error.message).toBe(
      "The file store refused the upload (413)",
    );
  });

  it("sends the bytes with PUT by default", async () => {
    const fetch = vi.fn((_url: string, _init?: RequestInit) =>
      Promise.resolve(new Response(null, { status: 200 })),
    );

    vi.stubGlobal("fetch", fetch);

    expect(await sendToSignedUrl(ticket, new Blob(["hello"]))).toEqual(
      ok(null),
    );
    expect(fetch.mock.calls[0]?.[1]).toMatchObject({
      method: "PUT",
      headers: {},
    });
  });
});

describe("confirmInStore", () => {
  it("refuses a store without head", async () => {
    const confirmed = await confirmInStore(
      without("head"),
      noService,
      FILE,
      "ATTACHMENT_CONFIRM_FAILED",
    );

    expect(confirmed.ok ? undefined : confirmed.error).toMatchObject({
      kind: "invalid_request",
      hint: "ATTACHMENT_CONFIRM_FAILED",
    });
  });

  it("answers not uploaded before asking Postgres when the store has no object", async () => {
    let calls = 0;

    const service: BlockCall = () => {
      calls += 1;

      return AsyncResult.err(dbError("unexpected", "must not be called"));
    };

    const confirmed = await confirmInStore(
      blobStore(),
      service,
      FILE,
      "ATTACHMENT_CONFIRM_FAILED",
    );

    expect(confirmed.ok ? undefined : confirmed.error).toMatchObject({
      kind: "not_found",
      hint: "ATTACHMENT_NOT_UPLOADED",
    });
    expect(calls).toBe(0);
  });
});
