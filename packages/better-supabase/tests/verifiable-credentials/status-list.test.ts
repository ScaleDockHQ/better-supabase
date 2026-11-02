import { describe, expect, it } from "vitest";

import { fromBase64 } from "../../src/core/base64.ts";
import {
  BITSTRING_MIN_ENTRIES,
  StatusList,
  bitstringEntry,
  readBitstringStatus,
  readStatus,
  signBitstringStatusListCredential,
  signStatusListToken,
} from "../../src/verifiable-credentials/index.ts";
import { testKey } from "./fixtures.ts";

describe("StatusList", () => {
  it("keeps index 0 in the least significant bit of byte 0", () => {
    const list = StatusList.create(16);

    list.set(0, 1);
    list.set(9, 1);

    expect([...list.bytes]).toEqual([0b0000_0001, 0b0000_0010]);
    expect(list.get(0)).toBe(1);
    expect(list.get(1)).toBe(0);
    list.set(0, 0);
    expect(list.get(0)).toBe(0);
  });

  it("round-trips through the zlib lst value", async () => {
    const list = StatusList.create(1000);

    list.set(7, 1);
    list.set(999, 1);

    const read = await StatusList.fromLst(await list.toLst());

    expect(read.get(7)).toBe(1);
    expect(read.get(999)).toBe(1);
    expect(read.get(8)).toBe(0);
  });

  it("writes the W3C bitstring from the left and gzip-compressed", async () => {
    const list = StatusList.create(BITSTRING_MIN_ENTRIES);

    list.set(0, 1);

    const encoded = await list.toEncodedList();

    expect(encoded.startsWith("u")).toBe(true);

    const raw = fromBase64(encoded.slice(1));

    // Gzip magic number.
    expect([raw[0], raw[1]]).toEqual([0x1f, 0x8b]);

    const read = await StatusList.fromEncodedList(encoded);

    expect(read.get(0)).toBe(1);
    expect(read.get(1)).toBe(0);
  });

  it("refuses short bitstrings, bad indexes and bad encodings", async () => {
    await expect(StatusList.create(100).toEncodedList()).rejects.toThrow(
      RangeError,
    );
    expect(() => StatusList.create(8).get(8)).toThrow(RangeError);
    await expect(StatusList.fromEncodedList("zabc")).rejects.toMatchObject({
      code: "STATUS_LIST_ENCODING",
    });
    await expect(StatusList.fromLst("AAAA")).rejects.toMatchObject({
      code: "STATUS_LIST_ENCODING",
    });
  });
});

describe("Token Status List", () => {
  it("signs a statuslist+jwt and reads a revoked index", async () => {
    const key = await testKey("ES256");
    const list = StatusList.create(64);

    list.set(5, 1);

    const token = await signStatusListToken({
      signer: key.signer,
      uri: "https://issuer.example/status/1",
      list,
      ttl: 300,
    });

    const read = (index: number, uri = "https://issuer.example/status/1") =>
      readStatus(token, { jwks: key.jwks, uri, index });

    expect(await read(5)).toBe(1);
    expect(await read(4)).toBe(0);
    await expect(
      read(5, "https://issuer.example/status/2"),
    ).rejects.toMatchObject({ code: "STATUS_LIST_SUBJECT" });
  });
});

describe("Bitstring Status List", () => {
  it("signs a list credential and reads an entry", async () => {
    const key = await testKey("Ed25519");
    const list = StatusList.create(BITSTRING_MIN_ENTRIES);
    const url = "https://issuer.example/credentials/status/3";

    list.set(94_567, 1);

    const token = await signBitstringStatusListCredential({
      signer: key.signer,
      id: url,
      issuer: "https://issuer.example",
      list,
    });

    expect(
      await readBitstringStatus(token, bitstringEntry(url, 94_567), key.jwks),
    ).toBe(1);
    expect(
      await readBitstringStatus(token, bitstringEntry(url, 94_568), key.jwks),
    ).toBe(0);
    await expect(
      readBitstringStatus(
        token,
        bitstringEntry(url, 1, "suspension"),
        key.jwks,
      ),
    ).rejects.toMatchObject({ code: "STATUS_LIST_CLAIMS" });
  });
});
