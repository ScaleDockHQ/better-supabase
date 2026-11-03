import { describe, expect, it } from "vitest";

import { decodeHookMetadata } from "../../../src/workflow-sdk/world/metadata.ts";

const encoder = new TextEncoder();

/** The bytes the Workflow runtime stores: format prefix plus devalue JSON. */
const devalue = (flat: unknown): Uint8Array =>
  encoder.encode(`devl${JSON.stringify(flat)}`);

/** Cbor-x's encoding of a Uint8Array: tag 64, then a byte string. */
function cbor(bytes: Uint8Array): Uint8Array {
  const length = bytes.byteLength;

  const head =
    length < 24
      ? [0x40 + length]
      : length < 256
        ? [0x58, length]
        : [0x59, Math.floor(length / 256), length % 256];

  return Uint8Array.from([0xd8, 0x40, ...head, ...bytes]);
}

async function encrypt(
  plain: Uint8Array,
  key: Uint8Array,
): Promise<Uint8Array> {
  const nonce = new Uint8Array(12).fill(3);

  const aes = await crypto.subtle.importKey(
    "raw",
    Uint8Array.from(key),
    "AES-GCM",
    false,
    ["encrypt"],
  );

  const sealed = new Uint8Array(
    await crypto.subtle.encrypt(
      { name: "AES-GCM", iv: Uint8Array.from(nonce) },
      aes,
      Uint8Array.from(plain),
    ),
  );

  return Uint8Array.from([...encoder.encode("encr"), ...nonce, ...sealed]);
}

describe("decodeHookMetadata", () => {
  const metadata = { tenantId: "t1", steps: [1, 2], done: false, note: null };

  // devalue's flat form of `metadata`.
  const flat = [
    { tenantId: 1, steps: 2, done: 3, note: 4 },
    "t1",
    [5, 6],
    false,
    null,
    1,
    2,
  ];

  it("decodes an unencrypted devalue payload", async () => {
    expect(await decodeHookMetadata(cbor(devalue(flat)), undefined)).toEqual(
      metadata,
    );
  });

  it("decodes a payload encrypted with the run key", async () => {
    const key = new Uint8Array(32).fill(9);
    const sealed = await encrypt(devalue(flat), key);

    expect(await decodeHookMetadata(cbor(sealed), key)).toEqual(metadata);
  });

  it("returns undefined without the key, with the wrong key or for none", async () => {
    const key = new Uint8Array(32).fill(9);
    const sealed = cbor(await encrypt(devalue(flat), key));

    expect(await decodeHookMetadata(sealed, undefined)).toBeUndefined();
    expect(
      await decodeHookMetadata(sealed, new Uint8Array(32).fill(1)),
    ).toBeUndefined();
    expect(await decodeHookMetadata(null, key)).toBeUndefined();
    expect(
      await decodeHookMetadata(Uint8Array.from([0xf7]), key),
    ).toBeUndefined();
  });

  it("reads a long byte string and plain primitives", async () => {
    const long = ["x".repeat(300)];
    expect(await decodeHookMetadata(cbor(devalue(long)), undefined)).toBe(
      "x".repeat(300),
    );
    expect(
      await decodeHookMetadata(cbor(devalue(-1)), undefined),
    ).toBeUndefined();
    expect(await decodeHookMetadata(cbor(devalue([5])), undefined)).toBe(5);
  });

  it("returns undefined for a type metadata doesn't use", async () => {
    const withMap = [["Map", 1, 2], "a", "b"];
    expect(
      await decodeHookMetadata(cbor(devalue(withMap)), undefined),
    ).toBeUndefined();
  });
});
