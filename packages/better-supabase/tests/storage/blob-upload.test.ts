import { describe, expect, it } from "vitest";

import type {
  BlobHandleUpload,
  BlobUploaded,
} from "../../src/storage/index.ts";

import { dbError } from "../../src/core/errors.ts";
import { err, ok } from "../../src/core/result.ts";
import { blobUploadRoute } from "../../src/storage/index.ts";

const BLOB: BlobUploaded = {
  url: "https://s.public.blob.vercel-storage.com/a.png",
  pathname: "a.png",
  contentType: "image/png",
};

/**
 * Mirrors handleUpload: a token request runs onBeforeGenerateToken, a callback
 * runs onUploadCompleted.
 */
const handleUpload: BlobHandleUpload = async (options) => {
  const body = options.body as {
    type: string;
    payload: Record<string, string | undefined>;
  };

  if (body.type === "blob.generate-client-token") {
    const grant = await options.onBeforeGenerateToken(
      body.payload["pathname"] ?? "",
      body.payload["clientPayload"] ?? null,
      false,
    );

    return { type: body.type, clientToken: "token", grant };
  }

  await options.onUploadCompleted?.({
    blob: BLOB,
    tokenPayload: body.payload["tokenPayload"] ?? null,
  });

  return { type: body.type, response: "ok" };
};

function post(body: unknown): Request {
  return new Request("https://app.test/api/upload", {
    method: "POST",
    body: typeof body === "string" ? body : JSON.stringify(body),
  });
}

describe("blobUploadRoute", () => {
  const recorded: unknown[] = [];

  const route = blobUploadRoute({
    handleUpload,
    authorize: ({ pathname }) =>
      pathname.startsWith("org_1/")
        ? ok({
            allowedContentTypes: ["image/png"],
            maximumSizeInBytes: 1000,
            tokenPayload: "org_1",
          })
        : err(dbError("forbidden", "Not your folder")),
    onCompleted: ({ blob, tokenPayload }) => {
      recorded.push({ blob, tokenPayload });

      return tokenPayload === "bad"
        ? err(dbError("unexpected", "Disk full"))
        : ok(null);
    },
  });

  it("issues a token with the grant the permission check returned", async () => {
    const response = await route(
      post({
        type: "blob.generate-client-token",
        payload: { pathname: "org_1/a.png" },
      }),
    );

    expect(response.status).toBe(200);
    expect(await response.json()).toMatchObject({
      clientToken: "token",
      grant: {
        allowedContentTypes: ["image/png"],
        maximumSizeInBytes: 1000,
        tokenPayload: "org_1",
      },
    });
  });

  it("refuses a token request the check refuses, with that error's status", async () => {
    const response = await route(
      post({
        type: "blob.generate-client-token",
        payload: { pathname: "org_2/a.png" },
      }),
    );

    expect(response.status).toBe(403);
    expect(response.headers.get("content-type")).toBe(
      "application/problem+json",
    );
  });

  it("records the upload on the callback with the checked payload", async () => {
    const response = await route(
      post({
        type: "blob.upload-completed",
        payload: { blob: BLOB, tokenPayload: "org_1" },
      }),
    );

    expect(response.status).toBe(200);
    expect(recorded).toEqual([{ blob: BLOB, tokenPayload: "org_1" }]);
  });

  it("answers an error from onCompleted so Vercel retries", async () => {
    const response = await route(
      post({
        type: "blob.upload-completed",
        payload: { blob: BLOB, tokenPayload: "bad" },
      }),
    );

    expect(response.status).toBeGreaterThanOrEqual(500);
  });

  it("refuses a body that is not JSON", async () => {
    expect((await route(post("nope"))).status).toBe(400);
  });
});
