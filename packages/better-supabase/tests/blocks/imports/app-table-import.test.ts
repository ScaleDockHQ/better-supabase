import type { StandardSchemaV1 } from "@standard-schema/spec";

import { describe, expect, it } from "vitest";

import {
  appTableImport,
  previewImport,
  runImport,
} from "../../../src/blocks/imports/index.ts";
import { defineSupabase } from "../../../src/core/define.ts";
import { capturingClient } from "../../fixtures/client.ts";
import { schema } from "../../fixtures/generated-camel.ts";

interface Row {
  readonly organizationId: string;
  readonly kvk: string;
  readonly name: string;
}

const columns: StandardSchemaV1<unknown, Row> = {
  "~standard": {
    version: 1,
    vendor: "test",
    validate: (value) => {
      const record: Record<string, unknown> =
        typeof value === "object" && value !== null ? { ...value } : {};

      const { organizationId, kvk, name } = record;

      if (
        typeof organizationId !== "string" ||
        typeof kvk !== "string" ||
        typeof name !== "string"
      ) {
        return {
          issues: [{ message: "organizationId, kvk and name required" }],
        };
      }

      return { value: { organizationId, kvk, name } };
    },
  },
};

const CSV = "org,kvk,name\no1,1,Acme Inc\no1,2,Beta\no1,3,Gamma\n";
const MAPPING = { org: "organizationId", kvk: "kvk", name: "name" };

const EXISTING = [
  { id: "c1", organizationId: "o1", kvk: "1", name: "Acme" },
  { id: "c2", organizationId: "o1", kvk: "2", name: "" },
];

function setup(update?: "fill" | "overwrite") {
  const captured = capturingClient((request) => ({
    body: request.method === "GET" ? EXISTING : [],
  }));

  const db = defineSupabase(schema).connect(captured.client);

  const definition = appTableImport({
    table: "customers",
    columns,
    repository: db.customers,
    key: ["organizationId", "kvk"],
    ...(update ? { update } : {}),
  });

  return { captured, definition };
}

describe("appTableImport", () => {
  it("previews new, changed and unchanged rows without writing", async () => {
    const { captured, definition } = setup("overwrite");
    const result = await previewImport(definition, CSV, MAPPING);

    expect(result.errors).toEqual([]);
    expect(result.preview).toEqual({ created: 1, changed: 2, unchanged: 0 });
    expect(captured.requests.map((request) => request.method)).toEqual(["GET"]);
  });

  it("counts a row as unchanged in fill mode when its fields are set", async () => {
    const { definition } = setup();
    const result = await previewImport(definition, CSV, MAPPING);

    expect(result.preview).toEqual({ created: 1, changed: 1, unchanged: 1 });
  });

  it("upserts on the unique set and keeps set fields in fill mode", async () => {
    const { captured, definition } = setup();

    const result = await runImport(definition, CSV, MAPPING, {
      organizationId: "o1",
      start: async () => "run-1",
      finish: async () => {},
    });

    expect(result).toMatchObject({ status: "completed", imported: 3 });

    const write = captured.last();
    expect(write.method).toBe("POST");
    expect(write.params.get("on_conflict")).toBe("organization_id,kvk");
    expect(write.headers.get("prefer")).toContain(
      "resolution=merge-duplicates",
    );
    expect(write.body).toEqual([
      { organization_id: "o1", kvk: "1", name: "Acme" },
      { organization_id: "o1", kvk: "2", name: "Beta" },
      { organization_id: "o1", kvk: "3", name: "Gamma" },
    ]);
  });

  it("refuses a key that is not a unique set", () => {
    const { client } = capturingClient();
    const db = defineSupabase(schema).connect(client);

    expect(() =>
      appTableImport({
        table: "customers",
        columns,
        repository: db.customers,
        key: ["name"],
      }),
    ).toThrow(
      "appTableImport: key (name) is not a unique set of customers; add it to appTables.customers.unique",
    );
  });
});
