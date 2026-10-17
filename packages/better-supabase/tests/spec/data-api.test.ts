import { describe, expect, it } from "vitest";

import { defineSupabase } from "../../src/core/define.ts";
import { defineApi } from "../../src/spec/api.ts";
import { buildApiModel } from "../../src/spec/build.ts";
import { schema } from "../fixtures/generated-camel.ts";

const betterSupabase = defineSupabase(schema);
const info = { title: "CRM", version: "1.0.0" };
const supabaseUrl = "https://abc.supabase.co/";

const operation = (
  model: ReturnType<typeof buildApiModel>["model"],
  id: string,
) => {
  const found = model.operations.find((entry) => entry.id === id);

  if (!found) {
    throw new Error(`no operation ${id}`);
  }

  return found;
};

describe("buildApiModel: dataApi", () => {
  const { model, diagnostics } = buildApiModel(betterSupabase, {
    info,
    supabaseUrl,
    resources: { customers: true },
    dataApi: {
      tables: ["customers"],
      functions: ["customers_by_status", "my_profile", "set_my_avatar_path"],
    },
  });

  it("documents the four table operations under /rest/v1 on the project", () => {
    const ids = model.operations
      .filter((entry) => entry.source.kind === "data-api")
      .map((entry) => [entry.method, entry.path, entry.id]);

    expect(ids).toEqual([
      ["get", "/rest/v1/customers", "dataApiSelectCustomers"],
      ["post", "/rest/v1/customers", "dataApiInsertCustomers"],
      ["patch", "/rest/v1/customers", "dataApiUpdateCustomers"],
      ["delete", "/rest/v1/customers", "dataApiDeleteCustomers"],
      [
        "post",
        "/rest/v1/rpc/customers_by_status",
        "dataApiRpcCustomersByStatus",
      ],
      ["post", "/rest/v1/rpc/my_profile", "dataApiRpcMyProfile"],
      ["post", "/rest/v1/rpc/set_my_avatar_path", "dataApiRpcSetMyAvatarPath"],
    ]);
    expect(operation(model, "dataApiSelectCustomers")).toMatchObject({
      tags: ["Data API"],
      servers: [{ url: "https://abc.supabase.co" }],
      security: [
        { supabaseApiKey: [], supabaseJwt: [] },
        { supabaseApiKey: [] },
      ],
      source: { kind: "data-api", table: "customers", operation: "select" },
    });
    expect(model.securitySchemes).toHaveProperty("supabaseApiKey");
    expect(model.security).toEqual([{ supabaseJwt: [] }]);
    expect(diagnostics).toEqual([]);
  });

  it("uses database column names, while the resource keeps the app casing", () => {
    const row = model.schemas["DataApiCustomersRow"];

    expect(Object.keys(row?.["properties"] ?? {})).toContain("organization_id");
    expect(row?.["required"]).toContain("organization_id");
    expect(
      Object.keys(model.schemas["CustomersRow"]?.["properties"] ?? {}),
    ).toContain("organizationId");
    expect(
      operation(model, "dataApiSelectCustomers").parameters.map(
        (parameter) => parameter.name,
      ),
    ).toEqual(
      expect.arrayContaining([
        "select",
        "order",
        "limit",
        "offset",
        "organization_id",
        "Range",
        "Prefer",
      ]),
    );
  });

  it("documents inserts, single or bulk, and PostgREST errors", () => {
    const insert = operation(model, "dataApiInsertCustomers");

    expect(insert.requestBody?.content["application/json"]?.schema).toEqual({
      oneOf: [
        { $ref: "#/components/schemas/DataApiCustomersInsert" },
        {
          type: "array",
          items: { $ref: "#/components/schemas/DataApiCustomersInsert" },
        },
      ],
    });
    expect(insert.responses).toMatchObject({
      "201": {},
      "4XX": { ref: "DataApiError" },
    });
    expect(model.responses["DataApiError"]).toBeDefined();
  });

  it("documents RPCs from the function metadata", () => {
    const byStatus = operation(model, "dataApiRpcCustomersByStatus");

    expect(byStatus.requestBody).toEqual({
      required: true,
      content: {
        "application/json": {
          schema: {
            type: "object",
            properties: {
              p_limit: { type: "integer" },
              p_status: { type: "string" },
            },
            required: ["p_limit", "p_status"],
            additionalProperties: false,
          },
        },
      },
    });
    expect(byStatus.responses["200"]).toMatchObject({
      content: {
        "application/json": {
          schema: {
            type: "array",
            items: { $ref: "#/components/schemas/DataApiCustomersRow" },
          },
        },
      },
    });
    expect(
      operation(model, "dataApiRpcMyProfile").responses["200"],
    ).toMatchObject({
      content: {
        "application/json": {
          schema: { items: { properties: { full_name: {} } } },
        },
      },
    });
    expect(
      Object.keys(operation(model, "dataApiRpcSetMyAvatarPath").responses),
    ).toContain("204");
  });

  it("skips Data API writes in requirePermissions", () => {
    const built = buildApiModel(betterSupabase, {
      info,
      supabaseUrl,
      requirePermissions: true,
      dataApi: { tables: ["customers"] },
    });

    expect(built.diagnostics).toEqual([]);
  });

  it("limits the operations per table", () => {
    const built = buildApiModel(betterSupabase, {
      info,
      supabaseUrl,
      dataApi: { operations: { notes: ["select"] } },
    });

    expect(built.model.operations.map((entry) => entry.id)).toEqual([
      "dataApiSelectNotes",
    ]);
  });

  it("reports unknown tables and functions and a missing project URL", () => {
    const built = buildApiModel(betterSupabase, {
      info,
      dataApi: { tables: ["nope"], functions: ["missing"] },
    });

    expect(built.diagnostics.map((entry) => entry.code)).toEqual([
      "data-api-server-missing",
      "data-api-table-unknown",
      "data-api-function-unknown",
    ]);
    expect(built.model.operations).toEqual([]);
  });

  it("renders operation servers in OpenAPI", () => {
    const api = defineApi(betterSupabase, {
      info,
      supabaseUrl,
      dataApi: { tables: ["customers"] },
    });

    const { document } = api.openapi();

    expect(document.paths["/rest/v1/customers"]?.["get"]).toMatchObject({
      servers: [{ url: "https://abc.supabase.co" }],
    });
  });
});
