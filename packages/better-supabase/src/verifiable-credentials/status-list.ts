/* oxlint-disable no-bitwise -- a status list is a bit array; bit indexing is its job (25 findings) */
import type { Jwks } from "../core/jws.ts";
import type { CredentialSigner } from "./shared.ts";

import { fromBase64, toBase64Url } from "../core/base64.ts";
import { isRecord } from "../core/guards.ts";
import { JwsError, verifyCompact } from "../core/jws.ts";
import { nowInstant } from "../core/temporal.ts";
import { CredentialError, epochSeconds, signJws } from "./shared.ts";

/** The JWS `typ` of a Token Status List Token. */
export const STATUS_LIST_TYP = "statuslist+jwt";

/** The smallest list a Bitstring Status List allows (W3C section 4.2). */
export const BITSTRING_MIN_ENTRIES = 131_072;

/** The largest list `StatusList.decode` inflates, against decompression bombs. */
const MAX_BYTES = 16 * 1024 * 1024;

/** A status value: `0` is valid, `1` is revoked or suspended. */
export type StatusBit = 0 | 1;

/**
 * A one-bit status list. Bits are kept as Token Status List draft-21 writes
 * them (index 0 is the least significant bit of byte 0); the W3C Bitstring
 * encoder reverses each byte, since that spec counts from the left.
 */
export class StatusList {
  readonly bytes: Uint8Array;

  private constructor(bytes: Uint8Array) {
    this.bytes = bytes;
  }

  /** A list of `size` entries, all `0`. */
  static create(size: number): StatusList {
    if (!Number.isInteger(size) || size < 1) {
      throw new TypeError("A status list has at least one entry");
    }

    return new StatusList(new Uint8Array(Math.ceil(size / 8)));
  }

  /** The number of entries, rounded up to a whole byte. */
  get size(): number {
    return this.bytes.length * 8;
  }

  get(index: number): StatusBit {
    this.check(index);

    // SAFETY: masking with 1 leaves 0 or 1.
    return ((this.bytes[index >> 3]! >> (index & 7)) & 1) as StatusBit;
  }

  set(index: number, value: StatusBit): void {
    this.check(index);

    const mask = 1 << (index & 7);
    const byte = this.bytes[index >> 3]!;

    this.bytes[index >> 3] = value === 1 ? byte | mask : byte & ~mask;
  }

  private check(index: number): void {
    if (!Number.isInteger(index) || index < 0 || index >= this.size) {
      throw new RangeError(`Status index ${String(index)} is out of range`);
    }
  }

  /** Reads the Token Status List `lst` value: base64url of zlib bytes. */
  static async fromLst(lst: string): Promise<StatusList> {
    return new StatusList(await inflate(fromBase64(lst), "deflate"));
  }

  /** The `lst` value: base64url of the zlib-compressed bytes. */
  async toLst(): Promise<string> {
    return toBase64Url(await deflate(this.bytes, "deflate"));
  }

  /** Reads a Bitstring Status List `encodedList`: multibase `u` and gzip. */
  static async fromEncodedList(encoded: string): Promise<StatusList> {
    if (!encoded.startsWith("u")) {
      throw new CredentialError(
        "STATUS_LIST_ENCODING",
        "An encodedList is multibase base64url, starting with u",
      );
    }

    const bytes = await inflate(fromBase64(encoded.slice(1)), "gzip");

    return new StatusList(reverseBits(bytes));
  }

  /** The `encodedList`: `u`, then base64url of the gzip of the MSB-first bits. */
  async toEncodedList(): Promise<string> {
    if (this.size < BITSTRING_MIN_ENTRIES) {
      throw new RangeError(
        `A Bitstring Status List has at least ${String(BITSTRING_MIN_ENTRIES)} entries`,
      );
    }

    return `u${toBase64Url(await deflate(reverseBits(this.bytes), "gzip"))}`;
  }
}

function reverseBits(bytes: Uint8Array): Uint8Array {
  return bytes.map((byte) => {
    let reversed = 0;

    for (let bit = 0; bit < 8; bit += 1) {
      reversed |= ((byte >> bit) & 1) << (7 - bit);
    }

    return reversed;
  });
}

async function deflate(
  bytes: Uint8Array,
  format: "deflate" | "gzip",
): Promise<Uint8Array> {
  // The copy is backed by a plain ArrayBuffer, which Blob accepts.
  const stream = new Blob([new Uint8Array(bytes)])
    .stream()
    .pipeThrough(new CompressionStream(format));

  return new Uint8Array(await new Response(stream).arrayBuffer());
}

async function inflate(
  bytes: Uint8Array,
  format: "deflate" | "gzip",
): Promise<Uint8Array> {
  // The copy is backed by a plain ArrayBuffer, which Blob accepts.
  const reader = new Blob([new Uint8Array(bytes)])
    .stream()
    .pipeThrough(new DecompressionStream(format))
    .getReader();

  const chunks: Uint8Array[] = [];
  let total = 0;

  try {
    for (;;) {
      const { done, value } = await reader.read();

      if (done) {
        break;
      }

      total += value.length;

      if (total > MAX_BYTES) {
        await reader.cancel();
        throw new CredentialError(
          "STATUS_LIST_SIZE",
          "The status list inflates past 16 MiB",
        );
      }

      chunks.push(value);
    }
  } catch (error) {
    if (error instanceof CredentialError) {
      throw error;
    }

    throw new CredentialError(
      "STATUS_LIST_ENCODING",
      "The status list is not valid compressed data",
    );
  }

  const result = new Uint8Array(total);
  let offset = 0;

  for (const chunk of chunks) {
    result.set(chunk, offset);
    offset += chunk.length;
  }

  return result;
}

export interface StatusListTokenOptions {
  readonly signer: CredentialSigner;
  /** The `sub` claim: the URI the credentials' `status.status_list.uri` names. */
  readonly uri: string;
  readonly list: StatusList;
  readonly issuedAt?: Temporal.Instant;
  readonly expiresAt?: Temporal.Instant;
  /** Seconds a relying party may cache the token (`ttl`). */
  readonly ttl?: number;
}

/** A Status List Token (Token Status List draft-21, `statuslist+jwt`). */
export async function signStatusListToken(
  options: StatusListTokenOptions,
): Promise<string> {
  return signJws(
    options.signer,
    { typ: STATUS_LIST_TYP },
    {
      sub: options.uri,
      iat: epochSeconds(options.issuedAt),
      ...(options.expiresAt === undefined
        ? {}
        : { exp: epochSeconds(options.expiresAt) }),
      ...(options.ttl === undefined ? {} : { ttl: options.ttl }),
      status_list: { bits: 1, lst: await options.list.toLst() },
    },
  );
}

export interface ReadStatusOptions {
  readonly jwks: Jwks;
  /**
   * The URI the credential's reference names; it has to equal the token's
   * `sub`.
   */
  readonly uri: string;
  readonly index: number;
  readonly now?: Temporal.Instant;
}

/** Verifies a Status List Token and returns the bit at `index`. */
export async function readStatus(
  token: string,
  options: ReadStatusOptions,
): Promise<StatusBit> {
  let payload: Readonly<Record<string, unknown>>;

  try {
    ({ payload } = await verifyCompact(token, options.jwks, {
      typ: STATUS_LIST_TYP,
    }));
  } catch (error) {
    throw error instanceof JwsError
      ? new CredentialError(error.code, error.message)
      : error;
  }

  if (payload["sub"] !== options.uri) {
    throw new CredentialError(
      "STATUS_LIST_SUBJECT",
      "The status list token is for another URI",
    );
  }

  if (
    typeof payload["exp"] === "number" &&
    payload["exp"] <= epochSeconds(options.now)
  ) {
    throw new CredentialError("STATUS_LIST_EXPIRED", "The status list expired");
  }

  const list = payload["status_list"];

  if (
    !isRecord(list) ||
    list["bits"] !== 1 ||
    typeof list["lst"] !== "string"
  ) {
    throw new CredentialError(
      "STATUS_LIST_CLAIMS",
      "Only one-bit status lists are supported",
    );
  }

  return (await StatusList.fromLst(list["lst"])).get(options.index);
}

/** The `credentialStatus` entry of a W3C credential (Bitstring Status List 1.0). */
export interface BitstringStatusEntry {
  readonly id: string;
  readonly type: "BitstringStatusListEntry";
  readonly statusPurpose: "revocation" | "suspension";
  readonly statusListIndex: string;
  readonly statusListCredential: string;
}

export function bitstringEntry(
  listCredentialUrl: string,
  index: number,
  purpose: "revocation" | "suspension" = "revocation",
): BitstringStatusEntry {
  return {
    id: `${listCredentialUrl}#${String(index)}`,
    type: "BitstringStatusListEntry",
    statusPurpose: purpose,
    statusListIndex: String(index),
    statusListCredential: listCredentialUrl,
  };
}

/** The `@context` entry every VC Data Model 2.0 credential starts with. */
export const VC_CONTEXT_V2 = "https://www.w3.org/ns/credentials/v2";

export interface BitstringListCredentialOptions {
  readonly signer: CredentialSigner;
  /**
   * The URL the list credential is served from: the entries'
   * `statusListCredential`.
   */
  readonly id: string;
  readonly issuer: string;
  readonly list: StatusList;
  readonly purpose?: "revocation" | "suspension";
  readonly validFrom?: Temporal.Instant;
  readonly validUntil?: Temporal.Instant;
}

/** A `BitstringStatusListCredential` secured as `application/vc+jwt`. */
export async function signBitstringStatusListCredential(
  options: BitstringListCredentialOptions,
): Promise<string> {
  return signJws(
    options.signer,
    { typ: "vc+jwt", cty: "vc" },
    {
      "@context": [VC_CONTEXT_V2],
      id: options.id,
      type: ["VerifiableCredential", "BitstringStatusListCredential"],
      issuer: options.issuer,
      validFrom: (options.validFrom ?? nowInstant()).toString(),
      ...(options.validUntil === undefined
        ? {}
        : { validUntil: options.validUntil.toString() }),
      credentialSubject: {
        id: `${options.id}#list`,
        type: "BitstringStatusList",
        statusPurpose: options.purpose ?? "revocation",
        encodedList: await options.list.toEncodedList(),
      },
    },
  );
}

/** Verifies a `BitstringStatusListCredential` and returns the bit for `entry`. */
export async function readBitstringStatus(
  token: string,
  entry: BitstringStatusEntry,
  jwks: Jwks,
): Promise<StatusBit> {
  let payload: Readonly<Record<string, unknown>>;

  try {
    ({ payload } = await verifyCompact(token, jwks, { typ: "vc+jwt" }));
  } catch (error) {
    throw error instanceof JwsError
      ? new CredentialError(error.code, error.message)
      : error;
  }

  const subject = payload["credentialSubject"];

  if (
    payload["id"] !== entry.statusListCredential ||
    !isRecord(subject) ||
    subject["type"] !== "BitstringStatusList" ||
    subject["statusPurpose"] !== entry.statusPurpose ||
    typeof subject["encodedList"] !== "string"
  ) {
    throw new CredentialError(
      "STATUS_LIST_CLAIMS",
      "The list credential does not match the entry",
    );
  }

  const list = await StatusList.fromEncodedList(subject["encodedList"]);

  // The W3C list reads from the left; fromEncodedList already reversed it.
  return list.get(Number(entry.statusListIndex));
}
