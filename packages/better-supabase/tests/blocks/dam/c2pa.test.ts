import { describe, expect, it } from "vitest";

import type { C2paManifest, C2paReader } from "../../../src/blocks/dam/c2pa.ts";

import {
  c2paReaderOf,
  readC2paManifest,
} from "../../../src/blocks/dam/c2pa.ts";

const AI =
  "http://cv.iptc.org/newscodes/digitalsourcetype/trainedAlgorithmicMedia";

const input = { bytes: new Uint8Array([1, 2, 3]), mimeType: "image/jpeg" };

function reader(manifest: C2paManifest | undefined | Error): C2paReader {
  return {
    apiVersion: 1,
    name: "fake",
    read: async () => {
      if (manifest instanceof Error) {
        throw manifest;
      }

      return manifest;
    },
  };
}

describe("readC2paManifest", () => {
  it("reports a file without a manifest as absent", async () => {
    const result = await readC2paManifest(reader(undefined), input);

    expect(result.ok && result.data).toEqual({
      status: "absent",
      aiGenerated: false,
      actions: [],
    });
  });

  it("keeps the actions of a valid manifest and flags generated media", async () => {
    const result = await readC2paManifest(
      reader({
        claimGenerator: "tool/1",
        valid: true,
        validationErrors: [],
        ingredients: [],
        actions: [{ action: "c2pa.created", digitalSourceType: AI }],
      }),
      input,
    );

    expect(result.ok && result.data.status).toBe("valid");
    expect(result.ok && result.data.aiGenerated).toBe(true);
    expect(result.ok && result.data.actions).toHaveLength(1);
  });

  it("drops the actions of a manifest that failed validation", async () => {
    const result = await readC2paManifest(
      reader({
        valid: false,
        validationErrors: ["assertion.dataHash.mismatch"],
        ingredients: [],
        actions: [{ action: "c2pa.edited" }],
      }),
      input,
    );

    expect(result.ok && result.data.status).toBe("invalid");
    expect(result.ok && result.data.actions).toEqual([]);
  });

  it("returns an error when the reader fails", async () => {
    const result = await readC2paManifest(reader(new Error("boom")), input);

    expect(!result.ok && result.error.hint).toBe("C2PA_READER_FAILED");
    expect(!result.ok && result.error.message).not.toContain("boom");
  });

  it("rejects a reader of another API version", () => {
    expect(() =>
      c2paReaderOf({
        ...reader(undefined),
        apiVersion: 2,
      } as unknown as C2paReader),
    ).toThrow(/supports 1/);
  });
});
