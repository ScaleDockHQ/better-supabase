import { readFile } from "node:fs/promises";
import * as v from "valibot";
import { describe, expect, it } from "vitest";

import * as valibotSchemas from "../fixtures/generated-camel.valibot.ts";
import * as zodSchemas from "../fixtures/generated-camel.zod.ts";

const customer = {
  organizationId: "00000000-0000-4000-8000-000000000001",
  name: "Acme",
  status: "active",
  createdAt: "2026-09-24T09:35:10.123456+00:00",
};

describe("zod generator", () => {
  it("accepts valid inserts and strips nothing required", () => {
    expect(zodSchemas.customersInsert.parse(customer)).toEqual(customer);
  });

  it("rejects values outside CHECK unions and bad uuids", () => {
    const result = zodSchemas.customersInsert.safeParse({
      ...customer,
      status: "deleted",
      organizationId: "x",
    });
    expect(result.success).toBe(false);
    expect(
      result.error?.issues.map((issue) => issue.path.join(".")).sort(),
    ).toEqual(["organizationId", "status"]);
  });

  it("leaves generated identity columns out of writes", () => {
    const note = {
      organizationId: customer.organizationId,
      customerId: customer.organizationId,
      body: "hi",
    };
    expect(zodSchemas.notesInsert.parse({ ...note, id: 5 })).toEqual(note);
    expect(
      zodSchemas.notesRow.safeParse({
        ...note,
        kind: "call",
        attachments: null,
      }).success,
    ).toBe(false);
  });

  it("exposes Standard Schema validators for the validation plugin", () => {
    expect(zodSchemas.validators.customers.insert["~standard"].vendor).toBe(
      "zod",
    );
  });
});

describe("valibot generator", () => {
  it("validates the same shapes", () => {
    expect(v.parse(valibotSchemas.customersInsert, customer)).toEqual(customer);
    expect(
      v.safeParse(valibotSchemas.customersInsert, {
        ...customer,
        status: "deleted",
      }).success,
    ).toBe(false);
    expect(
      v.safeParse(valibotSchemas.notesInsert, {
        organizationId: customer.organizationId,
        customerId: customer.organizationId,
        body: "hi",
        attachments: { files: [{ name: "a.pdf", size: 1 }] },
      }).success,
    ).toBe(true);
  });
});

describe("json schema generator", () => {
  it("writes $defs with required columns and nullable types", async () => {
    const doc = JSON.parse(
      await readFile(
        new URL("../fixtures/generated-camel.schema.json", import.meta.url),
        "utf8",
      ),
    ) as {
      $defs: Record<
        string,
        { required?: string[]; properties: Record<string, unknown> }
      >;
    };
    const insert = doc.$defs["customersInsert"];
    expect(insert?.required).toEqual(["organizationId", "name"]);
    expect(insert?.properties["status"]).toEqual({
      type: "string",
      enum: ["lead", "active", "archived"],
    });
    expect(insert?.properties["kvk"]).toEqual({ type: ["string", "null"] });
    expect(doc.$defs["customersRow"]?.properties["archivedAt"]).toEqual({
      type: ["string", "null"],
      format: "date-time",
    });
  });
});
