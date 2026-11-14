import { describe, expect, it } from "vitest";

import { publicJwks } from "./public-jwks.ts";

describe("publicJwks", () => {
  it("drops the private member and limits the key to verifying", () => {
    const text = JSON.stringify([
      {
        kty: "EC",
        kid: "k1",
        crv: "P-256",
        x: "x",
        y: "y",
        d: "secret",
        key_ops: ["sign", "verify"],
      },
    ]);

    expect(JSON.parse(publicJwks(text) ?? "{}")).toEqual({
      keys: [
        {
          kty: "EC",
          kid: "k1",
          crv: "P-256",
          x: "x",
          y: "y",
          key_ops: ["verify"],
        },
      ],
    });
  });

  it("returns undefined for no usable key", () => {
    expect(publicJwks("not json")).toBeUndefined();
    expect(publicJwks("[]")).toBeUndefined();
    expect(publicJwks("{}")).toBeUndefined();
  });
});
