const NONCE_LENGTH = 12;
const FORMAT_LENGTH = 4;
const decoder = /* @__PURE__ */ new TextDecoder();

/** Reads the byte string cbor-x writes for a Buffer or Uint8Array. */
function cborBytes(input: Uint8Array): Uint8Array | undefined {
  let at = 0;

  // cbor-x tags a Uint8Array with 64 (0xd8 0x40) before the byte string.
  if (input[0] === 0xd8 && input[1] === 0x40) {
    at = 2;
  }

  const head = input[at];

  if (head === undefined || Math.floor(head / 32) !== 2) {
    return undefined;
  }

  const info = head % 32;
  let length = info;
  let start = at + 1;

  if (info === 24) {
    length = input[start] ?? 0;
    start += 1;
  } else if (info === 25) {
    length = (input[start] ?? 0) * 256 + (input[start + 1] ?? 0);
    start += 2;
  } else if (info === 26) {
    length = new DataView(input.buffer, input.byteOffset + start, 4).getUint32(
      0,
    );
    start += 4;
  } else if (info > 26) {
    return undefined;
  }

  return input.subarray(start, start + length);
}

class Unsupported extends Error {}

/** Decodes devalue's flat JSON for the plain data hook metadata holds. */
function devalueParse(text: string): unknown {
  const root: unknown = JSON.parse(text);

  if (typeof root === "number") {
    return special(root);
  }

  if (!Array.isArray(root)) {
    throw new Unsupported("not a devalue document");
  }

  const values: readonly unknown[] = root;
  const done = new Map<number, unknown>();

  const at = (index: number): unknown => {
    if (index < 0) {
      return special(index);
    }

    if (done.has(index)) {
      return done.get(index);
    }

    const value = values[index];

    if (Array.isArray(value)) {
      const list: unknown[] = [];
      done.set(index, list);

      if (typeof value[0] === "string") {
        if (value[0] === "Date" && typeof value[1] === "string") {
          const date = new Date(value[1]);
          done.set(index, date);

          return date;
        }

        throw new Unsupported(`unsupported value ${value[0]}`);
      }

      for (const entry of value) {
        list.push(at(Number(entry)));
      }

      return list;
    }

    if (typeof value === "object" && value !== null) {
      const record: Record<string, unknown> = {};
      done.set(index, record);

      for (const [key, entry] of Object.entries(value)) {
        record[key] = at(Number(entry));
      }

      return record;
    }

    done.set(index, value);

    return value;
  };

  return at(0);
}

function special(code: number): unknown {
  switch (code) {
    case -1: {
      return undefined;
    }

    case -3: {
      return Number.NaN;
    }

    case -4: {
      return Number.POSITIVE_INFINITY;
    }

    case -5: {
      return Number.NEGATIVE_INFINITY;
    }

    case -6: {
      return -0;
    }

    default: {
      throw new Unsupported(`unknown devalue code ${String(code)}`);
    }
  }
}

async function open(
  bytes: Uint8Array,
  key: Uint8Array | undefined,
): Promise<Uint8Array | undefined> {
  const prefix = decoder.decode(bytes.subarray(0, FORMAT_LENGTH));

  if (prefix === "devl") {
    return bytes;
  }

  // `encp` (sealed to the run's public key) can't be opened with the run key.
  if (prefix !== "encr" || key === undefined) {
    return undefined;
  }

  const body = bytes.subarray(FORMAT_LENGTH);

  const aes = await crypto.subtle.importKey(
    "raw",
    Uint8Array.from(key),
    "AES-GCM",
    false,
    ["decrypt"],
  );

  const plain = await crypto.subtle.decrypt(
    { name: "AES-GCM", iv: Uint8Array.from(body.subarray(0, NONCE_LENGTH)) },
    aes,
    Uint8Array.from(body.subarray(NONCE_LENGTH)),
  );

  return new Uint8Array(plain);
}

/**
 * The value a hook was created with, from `workflow_hooks.metadata_cbor`: CBOR
 * around a format-prefixed payload that is AES-GCM encrypted with the run's key
 * when the World has an encryption key and devalue otherwise. Resolves with
 * `undefined` for no metadata, a sealed payload, a missing key or a value type
 * hook metadata doesn't use.
 */
export async function decodeHookMetadata(
  cbor: Uint8Array | null | undefined,
  key: Uint8Array | undefined,
): Promise<unknown> {
  if (cbor === null || cbor === undefined) {
    return undefined;
  }

  const bytes = cborBytes(cbor);

  if (bytes === undefined) {
    return undefined;
  }

  try {
    const plain = await open(bytes, key);

    if (plain === undefined) {
      return undefined;
    }

    return devalueParse(decoder.decode(plain.subarray(FORMAT_LENGTH)));
  } catch (error) {
    if (error instanceof Unsupported || error instanceof SyntaxError) {
      return undefined;
    }

    // A wrong key or a damaged ciphertext.
    if (error instanceof DOMException) {
      return undefined;
    }

    throw error;
  }
}
