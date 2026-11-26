/* oxlint-disable eslint/no-bitwise, unicorn/prefer-math-trunc -- md5 and the bitset are defined over 32-bit words and bits, so shifts and masks are the algorithm. 35 findings. */

/**
 * The bitset form of the `permissions` claim: `{ [tenant]: { h, b } }`, where
 * `h` is the hash of the permission catalog the hook used and `b` the base64url
 * bitset of the keys the caller holds, one bit per catalog key in sorted order.
 * About 60 bytes for 300 keys, where the key list is several kilobytes. The
 * claim is a cache of what the database grants; RLS stays the authority.
 */

/** The sorted permission keys of a catalog with the hash the hook writes. */
export interface PermissionCatalog {
  readonly keys: readonly string[];
  /** The first 8 hex digits of the md5 of the keys joined by a newline. */
  readonly hash: string;
}

/**
 * Builds the catalog the hook and the reader share: keys sorted by code point
 * (the hook sorts `collate "C"`) and hashed, so a catalog that differs between
 * the database and the app is noticed instead of misread.
 */
export function permissionCatalog(keys: Iterable<string>): PermissionCatalog {
  const sorted = [...new Set(keys)].toSorted((a, b) =>
    a < b ? -1 : a > b ? 1 : 0,
  );

  return { keys: sorted, hash: md5Hex(sorted.join("\n")).slice(0, 8) };
}

/**
 * The keys a `{ h, b }` claim value grants, or `undefined` when the value has
 * another shape or was written for another catalog, so the caller asks the
 * database.
 */
export function expandPermissionBitset(
  catalog: PermissionCatalog,
  value: unknown,
): readonly string[] | undefined {
  if (typeof value !== "object" || value === null || Array.isArray(value)) {
    return undefined;
  }

  // SAFETY: an object, checked above; each field is checked before use.
  const { h, b } = value as { readonly h?: unknown; readonly b?: unknown };

  if (h !== catalog.hash || typeof b !== "string") {
    return undefined;
  }

  const bytes = decodeBase64Url(b);

  if (bytes === undefined) {
    return undefined;
  }

  return catalog.keys.filter(
    (_, index) => ((bytes[index >> 3] ?? 0) & (1 << (index & 7))) !== 0,
  );
}

function decodeBase64Url(value: string): Uint8Array | undefined {
  try {
    const padded = value.replaceAll("-", "+").replaceAll("_", "/");
    const binary = atob(padded + "=".repeat((4 - (padded.length % 4)) % 4));

    return Uint8Array.from(binary, (char) => char.codePointAt(0) ?? 0);
  } catch {
    return undefined;
  }
}

const MD5_SHIFTS = [
  7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22, 5, 9, 14, 20, 5,
  9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20, 4, 11, 16, 23, 4, 11, 16, 23, 4, 11,
  16, 23, 4, 11, 16, 23, 6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15,
  21,
] as const;

const MD5_K = Array.from({ length: 64 }, (_, index) =>
  Math.floor(Math.abs(Math.sin(index + 1)) * 2 ** 32),
);

/**
 * Md5 of the UTF-8 text as hex. The hook hashes with Postgres `md5()`; Web
 * Crypto has no synchronous md5 and runtime entries import no Node built-ins.
 */
export function md5Hex(text: string): string {
  const input = new TextEncoder().encode(text);
  const padded = new Uint8Array((((input.length + 8) >> 6) + 1) << 6);
  padded.set(input);
  padded[input.length] = 0x80;
  const view = new DataView(padded.buffer);
  view.setUint32(padded.length - 8, (input.length * 8) >>> 0, true);
  view.setUint32(
    padded.length - 4,
    Math.floor((input.length * 8) / 2 ** 32),
    true,
  );

  let a0 = 0x67_45_23_01;
  let b0 = 0xef_cd_ab_89;
  let c0 = 0x98_ba_dc_fe;
  let d0 = 0x10_32_54_76;

  for (let offset = 0; offset < padded.length; offset += 64) {
    let a = a0;
    let b = b0;
    let c = c0;
    let d = d0;

    for (let i = 0; i < 64; i += 1) {
      let f: number;
      let g: number;

      if (i < 16) {
        f = (b & c) | (~b & d);
        g = i;
      } else if (i < 32) {
        f = (d & b) | (~d & c);
        g = (5 * i + 1) % 16;
      } else if (i < 48) {
        f = b ^ c ^ d;
        g = (3 * i + 5) % 16;
      } else {
        f = c ^ (b | ~d);
        g = (7 * i) % 16;
      }

      const rotated =
        (a + f + (MD5_K[i] ?? 0) + view.getUint32(offset + g * 4, true)) | 0;

      const shift = MD5_SHIFTS[i] ?? 0;
      a = d;
      d = c;
      c = b;
      b = (b + ((rotated << shift) | (rotated >>> (32 - shift)))) | 0;
    }

    a0 = (a0 + a) | 0;
    b0 = (b0 + b) | 0;
    c0 = (c0 + c) | 0;
    d0 = (d0 + d) | 0;
  }

  const out = new DataView(new ArrayBuffer(16));
  out.setUint32(0, a0, true);
  out.setUint32(4, b0, true);
  out.setUint32(8, c0, true);
  out.setUint32(12, d0, true);

  return Array.from(new Uint8Array(out.buffer), (byte) =>
    byte.toString(16).padStart(2, "0"),
  ).join("");
}
