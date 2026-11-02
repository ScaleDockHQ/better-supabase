import { describe, expect, it } from "vitest";

import { SPEC_PINS } from "../../src/core/spec-pins.ts";
import {
  BITSTRING_MIN_ENTRIES,
  StatusList,
  VC_CONTEXT_V2,
  bitstringEntry,
} from "../../src/verifiable-credentials/index.ts";

describe("W3C VC Data Model 2.0 and Bitstring Status List 1.0", () => {
  it("pins the versions", () => {
    expect(SPEC_PINS.vcDataModel).toBe("2.0");
    expect(SPEC_PINS.bitstringStatusList).toBe("1.0");
  });

  it("uses the version 2 context", () => {
    expect(VC_CONTEXT_V2).toBe("https://www.w3.org/ns/credentials/v2");
  });

  it("requires 131,072 entries in a bitstring (section 4.2)", () => {
    expect(BITSTRING_MIN_ENTRIES).toBe(131_072);
  });

  it("counts bitstring positions from the left (section 4.1)", async () => {
    const list = StatusList.create(BITSTRING_MIN_ENTRIES);

    list.set(0, 1);

    const encoded = await list.toEncodedList();

    const stream = new Blob([
      Uint8Array.from(
        atob(encoded.slice(1).replaceAll("-", "+").replaceAll("_", "/")),
        (c) => c.codePointAt(0)!,
      ),
    ])
      .stream()
      .pipeThrough(new DecompressionStream("gzip"));

    const bytes = new Uint8Array(await new Response(stream).arrayBuffer());

    expect(bytes[0]).toBe(0b1000_0000);
  });

  it("writes a BitstringStatusListEntry with a string index", () => {
    expect(bitstringEntry("https://x/list", 3)).toEqual({
      id: "https://x/list#3",
      type: "BitstringStatusListEntry",
      statusPurpose: "revocation",
      statusListIndex: "3",
      statusListCredential: "https://x/list",
    });
  });
});
