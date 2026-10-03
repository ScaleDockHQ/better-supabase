import { describe, expect, it } from "vitest";

import { jsonReplacer, jsonResponse } from "../../src/core/json.ts";

describe("jsonResponse", () => {
  it("keeps a given content type and status", async () => {
    const response = jsonResponse(
      { n: 2n },
      { status: 201, headers: { "content-type": "application/vnd.api+json" } },
    );
    expect(response.status).toBe(201);
    expect(response.headers.get("content-type")).toBe(
      "application/vnd.api+json",
    );
    expect(await response.json()).toEqual({ n: "2" });
  });

  it("leaves other values to JSON.stringify", () => {
    expect(JSON.stringify({ a: 1, b: null }, jsonReplacer)).toBe(
      '{"a":1,"b":null}',
    );
  });
});
