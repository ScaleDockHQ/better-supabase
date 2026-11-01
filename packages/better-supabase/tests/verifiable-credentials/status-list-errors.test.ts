import { describe, expect, it } from "vitest";

import {
  BITSTRING_MIN_ENTRIES,
  CredentialError,
  STATUS_LIST_TYP,
  StatusList,
  bitstringEntry,
  readBitstringStatus,
  readStatus,
  signBitstringStatusListCredential,
  signStatusListToken,
} from "../../src/verifiable-credentials/index.ts";
import { signJws } from "../../src/verifiable-credentials/shared.ts";
import { testKey } from "./fixtures.ts";

const URI = "https://issuer.test/list";
const NOW = Temporal.Instant.from("2026-06-01T00:00:00Z");

async function codeOf(promise: Promise<unknown>): Promise<unknown> {
  try {
    await promise;
  } catch (error) {
    return error instanceof CredentialError ? error.code : error;
  }

  return undefined;
}

describe("StatusList bounds", () => {
  it("refuses a bad size and bad indexes", () => {
    expect(() => StatusList.create(0)).toThrow(TypeError);
    expect(() => StatusList.create(1.5)).toThrow(TypeError);

    const list = StatusList.create(8);

    expect(list.size).toBe(8);
    expect(() => list.get(-1)).toThrow(RangeError);
    expect(() => list.get(8)).toThrow(RangeError);
    expect(() => {
      list.set(0.5, 1);
    }).toThrow(RangeError);
  });

  it("refuses short bitstrings and bad encodings", async () => {
    await expect(StatusList.create(8).toEncodedList()).rejects.toThrow(
      RangeError,
    );
    expect(await codeOf(StatusList.fromEncodedList("xabc"))).toBe(
      "STATUS_LIST_ENCODING",
    );
    expect(await codeOf(StatusList.fromEncodedList("uAAAA"))).toBe(
      "STATUS_LIST_ENCODING",
    );
    expect(await codeOf(StatusList.fromLst("AAAA"))).toBe(
      "STATUS_LIST_ENCODING",
    );
  });

  it("refuses a list that inflates past the limit", async () => {
    const list = StatusList.create(8 * 17 * 1024 * 1024);

    expect(await codeOf(StatusList.fromLst(await list.toLst()))).toBe(
      "STATUS_LIST_SIZE",
    );
  });
});

describe("readStatus", () => {
  it("signs with optional expiry and ttl and reads a bit", async () => {
    const { signer, jwks } = await testKey();
    const list = StatusList.create(8);

    list.set(3, 1);

    const token = await signStatusListToken({
      signer,
      uri: URI,
      list,
      issuedAt: NOW,
      expiresAt: NOW.add({ hours: 1 }),
      ttl: 60,
    });

    expect(
      await readStatus(token, { jwks, uri: URI, index: 3, now: NOW }),
    ).toBe(1);
  });

  it("refuses a bad signature, subject and expiry", async () => {
    const { signer, jwks } = await testKey();
    const other = await testKey();
    const list = StatusList.create(8);

    const token = await signStatusListToken({
      signer,
      uri: URI,
      list,
      issuedAt: NOW,
      expiresAt: NOW.add({ hours: 1 }),
    });

    expect(
      await codeOf(
        readStatus(token, { jwks: other.jwks, uri: URI, index: 0, now: NOW }),
      ),
    ).toBeTruthy();
    expect(
      await codeOf(
        readStatus(token, { jwks, uri: "other", index: 0, now: NOW }),
      ),
    ).toBe("STATUS_LIST_SUBJECT");
    expect(
      await codeOf(
        readStatus(token, {
          jwks,
          uri: URI,
          index: 0,
          now: NOW.add({ hours: 2 }),
        }),
      ),
    ).toBe("STATUS_LIST_EXPIRED");
  });

  it("refuses unsupported list claims", async () => {
    const { signer, jwks } = await testKey();

    const make = (status_list: unknown) =>
      signJws(signer, { typ: STATUS_LIST_TYP }, { sub: URI, status_list });

    for (const claim of [
      undefined,
      { bits: 2, lst: "x" },
      { bits: 1, lst: 5 },
    ]) {
      expect(
        await codeOf(
          readStatus(await make(claim), { jwks, uri: URI, index: 0 }),
        ),
      ).toBe("STATUS_LIST_CLAIMS");
    }
  });
});

describe("readBitstringStatus", () => {
  const url = "https://issuer.test/bits";

  it("signs with optional validity and reads a suspension bit", async () => {
    const { signer, jwks } = await testKey();
    const list = StatusList.create(BITSTRING_MIN_ENTRIES);

    list.set(5, 1);

    const token = await signBitstringStatusListCredential({
      signer,
      id: url,
      issuer: "https://issuer.test",
      list,
      purpose: "suspension",
      validFrom: NOW,
      validUntil: NOW.add({ hours: 1 }),
    });

    expect(
      await readBitstringStatus(
        token,
        bitstringEntry(url, 5, "suspension"),
        jwks,
      ),
    ).toBe(1);
  });

  it("refuses a bad signature and mismatched entries", async () => {
    const { signer, jwks } = await testKey();
    const other = await testKey();

    const token = await signBitstringStatusListCredential({
      signer,
      id: url,
      issuer: "https://issuer.test",
      list: StatusList.create(BITSTRING_MIN_ENTRIES),
    });

    expect(
      await codeOf(
        readBitstringStatus(token, bitstringEntry(url, 0), other.jwks),
      ),
    ).toBeTruthy();
    expect(
      await codeOf(
        readBitstringStatus(token, bitstringEntry(url, 0, "suspension"), jwks),
      ),
    ).toBe("STATUS_LIST_CLAIMS");
    expect(
      await codeOf(
        readBitstringStatus(token, bitstringEntry("other", 0), jwks),
      ),
    ).toBe("STATUS_LIST_CLAIMS");

    const bad = await signJws(
      signer,
      { typ: "vc+jwt" },
      {
        id: url,
        credentialSubject: {
          type: "BitstringStatusList",
          statusPurpose: "revocation",
          encodedList: 5,
        },
      },
    );

    expect(
      await codeOf(readBitstringStatus(bad, bitstringEntry(url, 0), jwks)),
    ).toBe("STATUS_LIST_CLAIMS");
  });
});
