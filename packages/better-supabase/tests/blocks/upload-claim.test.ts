import { describe, expect, it } from "vitest";

import { claimsUploads, claimUpload } from "../../src/blocks/upload-claim.ts";
import { ok } from "../../src/core/result.ts";

const HINTS = { notUploaded: "X_NOT_UPLOADED", forbidden: "X_FORBIDDEN" };
const FILE = { bucket: "files", path: "o1/a.txt" };

describe("claimUpload", () => {
  it("succeeds without a request when the storage has no claim step", async () => {
    expect(claimsUploads({})).toBe(false);
    expect(await claimUpload({}, FILE, HINTS)).toEqual(ok(undefined));
  });

  it("passes the bucket and path and maps a refusal to the block's hints", async () => {
    const seen: string[] = [];

    const storage = (error: unknown) => ({
      claimSignedUpload: (bucket: string, path: string) => {
        seen.push(`${bucket}/${path}`);

        return Promise.resolve({ data: null, error });
      },
    });

    expect(claimsUploads(storage(null))).toBe(true);
    expect(await claimUpload(storage(null), FILE, HINTS)).toEqual(
      ok(undefined),
    );
    expect(seen).toEqual(["files/o1/a.txt"]);
    expect(
      await claimUpload(
        storage({ message: "denied", status: 403, statusCode: "403" }),
        FILE,
        HINTS,
      ),
    ).toMatchObject({
      ok: false,
      error: { kind: "forbidden", message: "denied", hint: "X_FORBIDDEN" },
    });
    expect(
      await claimUpload(
        storage({ message: "Object not found", statusCode: "404" }),
        FILE,
        HINTS,
      ),
    ).toMatchObject({
      ok: false,
      error: { kind: "not_found", hint: "X_NOT_UPLOADED" },
    });
  });
});
