import type { StandardSchemaV1 } from "@standard-schema/spec";

import { describe, expect, it } from "vitest";

import { returnsTag } from "../../src/cli/gen/model-functions.ts";
import {
  decodeRpcReturn,
  registerRpcReturn,
} from "../../src/schema/rpc-returns.ts";

// SAFETY: the test schema only checks one field; the Standard Schema fields it
// omits are optional at runtime.
const total = {
  "~standard": {
    version: 1,
    vendor: "test",
    validate: (value: unknown) =>
      typeof value === "object" &&
      value !== null &&
      "total" in value &&
      typeof value.total === "number"
        ? { value }
        : { issues: [{ message: "total must be a number" }] },
  },
} as StandardSchemaV1;

describe("rpc return schemas", () => {
  it("reads the returns tag", () => {
    expect(returnsTag("/** @bsb returns=./invoice.ts#InvoiceTotal */")).toBe(
      "./invoice.ts#InvoiceTotal",
    );
    expect(returnsTag("no tag")).toBeUndefined();
  });

  it("rejects a payload the schema refuses", () => {
    registerRpcReturn("invoice_total", total);

    expect(decodeRpcReturn("invoice_total", { total: 1 })).toEqual({
      total: 1,
    });
    expect(() => decodeRpcReturn("invoice_total", { total: "1" })).toThrow(
      /total must be a number/u,
    );
    expect(decodeRpcReturn("other", { total: "1" })).toEqual({ total: "1" });
  });
});
