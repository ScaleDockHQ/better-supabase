import { describe, expect, it } from "vitest";

import { defineAuthorizer } from "../../src/core/authorizer.ts";
import { defineSupabase } from "../../src/core/define.ts";
import { defineListQuery } from "../../src/list/index.ts";
import { buildApiModel } from "../../src/spec/build.ts";
import { schema } from "../fixtures/generated-camel.ts";
import { opaque, standard } from "./helpers.ts";

const betterSupabase = defineSupabase(schema);
const info = { title: "CRM", version: "1.0.0" };

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

describe("buildApiModel: resources", () => {
  it("rejects unknown tables", () => {
    expect(() =>
      buildApiModel(betterSupabase, { info, resources: { nope: true } }),
    ).toThrow('unknown table "nope"');
  });

  it("documents tables and columns from the schema metadata", () => {
    const { model } = buildApiModel(betterSupabase, {
      info,
      resources: { customers: true },
    });

    expect(model.schemas["CustomersRow"]).toMatchObject({
      description: "Companies the organization sells to.",
      properties: { name: { description: "Trading name." } },
    });
    expect(model.tags).toEqual([
      {
        name: "customers",
        description: "Companies the organization sells to.",
      },
    ]);
    expect(model.schemas["Problem"]).toBeDefined();
  });

  it("uses list-query parameters and a cursor page", () => {
    const list = defineListQuery(betterSupabase, "customers", {
      search: ["name"],
      sorts: { name: { name: "asc" } },
      defaultSort: "name",
      pagination: "cursor",
    });

    const { model } = buildApiModel(betterSupabase, {
      info,
      basePath: "/api/",
      resources: { customers: { list, operations: ["list"] } },
    });

    const listOp = operation(model, "listCustomers");
    expect(listOp.path).toBe("/api/customers");
    expect(listOp.parameters.map((parameter) => parameter.name)).toEqual([
      "q",
      "sort",
      "after",
      "size",
    ]);
    expect(model.schemas["CustomersPage"]).toMatchObject({
      required: ["items", "nextCursor", "hasMore"],
    });
  });

  it("adds row examples, custom names, ids and a prefix", () => {
    const { model } = buildApiModel(betterSupabase, {
      info,
      resources: { notes: { operations: ["get"] } },
      examples: { notes: [{ id: "n1" }] },
      componentName: (context) =>
        context.kind === "table" ? `Note${context.variant}` : undefined,
      operationId: ({ defaultId, source }) =>
        source.kind === "resource" ? `api_${defaultId}` : defaultId,
      extensionPrefix: "x-crm-",
    });

    expect(model.schemas["NoteRow"]).toMatchObject({
      examples: [{ id: "n1" }],
    });
    expect(model.schemas["NotesRow"]).toBeUndefined();
    const get = operation(model, "api_getNotes");
    expect(get.extensions).toEqual({
      "x-crm-table": "public.notes",
      "x-crm-operation": "get",
    });
    expect(get.responses["200"]).toMatchObject({
      content: {
        "application/json": {
          schema: { $ref: "#/components/schemas/NoteRow" },
        },
      },
    });
    expect(model.extensionPrefix).toBe("x-crm-");
  });

  it("replaces request and response schemas, named by their $id", () => {
    const create = standard({
      $id: "https://schemas.test/NewCustomer.json",
      type: "object",
      properties: { name: { type: "string" } },
    });

    const { model, diagnostics } = buildApiModel(betterSupabase, {
      info,
      resources: {
        customers: {
          operations: ["create", "update", "get", "list"],
          input: { create, update: standard({ type: "object" }) },
          output: { get: opaque(), list: standard({ type: "object" }) },
        },
      },
    });

    expect(model.schemas["NewCustomer"]).toEqual({
      type: "object",
      properties: { name: { type: "string" } },
    });
    expect(operation(model, "createCustomers").requestBody).toMatchObject({
      content: {
        "application/json": {
          schema: { $ref: "#/components/schemas/NewCustomer" },
        },
      },
    });
    expect(operation(model, "updateCustomers").requestBody).toMatchObject({
      content: { "application/json": { schema: { type: "object" } } },
    });
    expect(diagnostics).toEqual([
      expect.objectContaining({
        code: "schema-unconvertible",
        severity: "warning",
      }),
    ]);
  });

  it("reports two different schemas with one name", () => {
    const { diagnostics } = buildApiModel(betterSupabase, {
      info,
      resources: {
        customers: {
          operations: ["create"],
          input: { create: standard({ $id: "Problem", type: "string" }) },
        },
      },
    });

    expect(diagnostics).toContainEqual(
      expect.objectContaining({
        code: "component-conflict",
        severity: "error",
        pointer: "/components/schemas/Problem",
      }),
    );
  });

  it("documents actions with their parameters and events", () => {
    const { model } = buildApiModel(betterSupabase, {
      info,
      resources: {
        customers: {
          operations: [],
          actions: {
            send: {
              method: "POST",
              path: "/{id}/send",
              input: standard({ type: "object" }),
              output: standard({ type: "object" }),
              query: standard({
                type: "object",
                required: ["force"],
                properties: {
                  force: { type: "boolean", description: "Send again." },
                },
              }),
              emits: ["customer.sent"],
              description: "Sends it.",
              deprecated: true,
            },
            export: { method: "GET", path: "/export" },
          },
        },
      },
    });

    const send = operation(model, "sendCustomers");
    expect(send).toMatchObject({
      method: "post",
      path: "/customers/{id}/send",
      deprecated: true,
      description: "Sends it.",
      extensions: {
        "x-better-supabase-action": "send",
        "x-better-supabase-emits": ["customer.sent"],
      },
    });
    expect(send.parameters).toEqual([
      expect.objectContaining({ name: "id", in: "path" }),
      {
        name: "force",
        in: "query",
        required: true,
        description: "Send again.",
        schema: { type: "boolean", description: "Send again." },
      },
    ]);
    expect(Object.keys(send.responses)).toEqual(
      expect.arrayContaining(["200", "400", "401", "403", "404", "422"]),
    );
    const exported = operation(model, "exportCustomers");
    expect(exported.parameters).toEqual([]);
    expect(Object.keys(exported.responses)).toEqual(["204", "401", "403"]);
  });

  it("uses per-resource errors and security, and reports unknown extend keys", () => {
    const { model, diagnostics } = buildApiModel(betterSupabase, {
      info,
      resources: {
        notes: {
          operations: ["get"],
          errors: [{ name: "Gone", status: 404, description: "Gone." }],
          security: [],
          extend: { get: { "x-a": 1 }, "*": { "x-b": 2 }, nope: {} },
        },
      },
    });

    const get = operation(model, "getNotes");
    expect(get.responses["404"]).toEqual({ ref: "Gone" });
    expect(model.responses["Gone"]).toMatchObject({ description: "Gone." });
    expect(get.security).toEqual([]);
    expect(get.extend).toEqual({ "x-b": 2, "x-a": 1 });
    expect(diagnostics).toContainEqual(
      expect.objectContaining({ code: "extend-unknown" }),
    );
  });

  it("marks operations of a deprecated table", () => {
    const deprecated = structuredClone(betterSupabase.meta);
    Object.assign(deprecated.tables["notes"]!, { deprecated: true });

    const { model } = buildApiModel(
      { meta: deprecated },
      { info, resources: { notes: { operations: ["get"] } } },
    );

    expect(operation(model, "getNotes").deprecated).toBe(true);
    expect(model.schemas["NotesRow"]).toMatchObject({ deprecated: true });
  });
});

describe("buildApiModel: routes", () => {
  it("documents routes with params, query, body, output and streams", () => {
    const { model } = buildApiModel(betterSupabase, {
      info,
      basePath: "/api",
      routes: [
        {
          method: "POST",
          path: "/reports/{reportId}/run",
          tags: ["reports"],
          summary: "Run a report",
          description: "Runs it.",
          deprecated: true,
          params: standard({
            type: "object",
            properties: { reportId: { type: "integer" } },
          }),
          query: standard({
            type: "object",
            properties: { dry: { type: "boolean" } },
          }),
          input: standard({ type: "object" }),
          output: standard({ $id: "ReportRun", type: "object" }),
          extend: { "x-a": 1 },
        },
        {
          method: "get",
          path: "/events",
          operationId: "streamEvents",
          stream: { item: standard({ type: "object" }) },
          security: [],
        },
        { method: "delete", path: "/cache/{key}", status: 202 },
      ],
    });

    const run = operation(model, "postReportsReportIdRun");
    expect(run).toMatchObject({
      path: "/api/reports/{reportId}/run",
      tags: ["reports"],
      deprecated: true,
      extend: { "x-a": 1 },
      parameters: [
        {
          name: "reportId",
          in: "path",
          required: true,
          schema: { type: "integer" },
        },
        { name: "dry", in: "query", required: false },
      ],
      responses: {
        "200": {
          content: {
            "application/json": {
              schema: { $ref: "#/components/schemas/ReportRun" },
            },
          },
        },
        "400": { ref: "BadRequest" },
        "422": { ref: "Unprocessable" },
      },
    });
    expect(model.tags).toContainEqual({ name: "reports" });
    const events = operation(model, "streamEvents");
    expect(events.responses["200"]).toMatchObject({
      content: { "text/event-stream": { itemSchema: { type: "object" } } },
    });
    expect(events.responses["401"]).toBeUndefined();
    const cache = operation(model, "deleteCacheKey");
    expect(cache.parameters).toEqual([
      { name: "key", in: "path", required: true, schema: { type: "string" } },
    ]);
    expect(cache.responses["202"]).toEqual({ description: "Done." });
  });

  it("rejects unknown methods and reports duplicate ids", () => {
    expect(() =>
      buildApiModel(betterSupabase, {
        info,
        // @ts-expect-error -- not an HTTP method
        routes: [{ method: "fetch", path: "/x" }],
      }),
    ).toThrow('unknown method "fetch"');

    const { diagnostics } = buildApiModel(betterSupabase, {
      info,
      resources: { notes: { operations: ["get"] } },
      routes: [{ method: "get", path: "/x", operationId: "getNotes" }],
    });

    expect(diagnostics).toContainEqual(
      expect.objectContaining({
        code: "operation-id-duplicate",
        severity: "error",
      }),
    );
  });
});

describe("buildApiModel: security presets", () => {
  it("defaults to a bearer token", () => {
    const { model } = buildApiModel(betterSupabase, { info });
    expect(model.securitySchemes).toEqual({
      supabaseJwt: expect.objectContaining({ type: "http", scheme: "bearer" }),
    });
    expect(model.security).toEqual([{ supabaseJwt: [] }]);
  });

  it("builds oauth2, apiKey and custom schemes", () => {
    const { model } = buildApiModel(betterSupabase, {
      info,
      security: [
        "oauth2",
        "apiKey",
        {
          name: "partner",
          scheme: { type: "http", scheme: "basic" },
          scopes: ["read"],
        },
      ],
      supabaseUrl: "https://abc.supabase.co/",
    });

    expect(model.securitySchemes["supabaseOAuth"]).toMatchObject({
      type: "oauth2",
      metadataUrl:
        "https://abc.supabase.co/.well-known/oauth-authorization-server/auth/v1",
      flows: {
        authorizationCode: {
          tokenUrl: "https://abc.supabase.co/auth/v1/oauth/token",
        },
      },
    });
    expect(model.securitySchemes["supabaseApiKey"]).toEqual(
      expect.objectContaining({ type: "apiKey", name: "apikey", in: "header" }),
    );
    expect(model.security).toEqual([
      { supabaseOAuth: [] },
      { supabaseApiKey: [] },
      { partner: ["read"] },
    ]);
    expect(() =>
      buildApiModel(betterSupabase, { info, security: ["oauth2"] }),
    ).toThrow("needs supabaseUrl");
  });
});

describe("buildApiModel: permissions", () => {
  const authorizer = defineAuthorizer<{ readonly id: string }>({
    name: "test",
    key: (ref) => {
      if (ref.id === "broken") {
        throw new Error("no key");
      }

      return `perm:${ref.id}`;
    },
    forOperation: (table, op) =>
      op === "delete" ? undefined : { id: `${table}.${op}` },
    evaluate: () => ({ outcome: "granted" }),
  });

  it("documents the permission key and a 403 with every denial", () => {
    const { model } = buildApiModel(betterSupabase, {
      info,
      authorizer,
      resources: {
        notes: { operations: ["get", "delete"], permissions: true },
      },
      routes: [{ method: "post", path: "/sync", permission: { id: "sync" } }],
    });

    const get = operation(model, "getNotes");
    expect(get.permission).toBe("perm:notes.get");
    expect(get.extensions["x-better-supabase-permission"]).toBe(
      "perm:notes.get",
    );
    expect(get.responses["403"]).toEqual({ ref: "PermissionDenied" });
    expect(operation(model, "deleteNotes").responses["403"]).toEqual({
      ref: "Forbidden",
    });
    expect(operation(model, "postSync").permission).toBe("perm:sync");
    const denied = model.responses["PermissionDenied"];
    expect(
      Object.keys(
        denied?.content?.["application/problem+json"]?.examples ?? {},
      ),
    ).toEqual(["permissionDenied", "insufficientScope", "approvalRequired"]);
  });

  it("reports permissions without a key", () => {
    const { diagnostics } = buildApiModel(betterSupabase, {
      info,
      authorizer,
      resources: {
        notes: { operations: ["get"], permissions: { get: { id: "broken" } } },
      },
    });

    expect(diagnostics).toContainEqual(
      expect.objectContaining({
        code: "permission-unresolved",
        severity: "error",
      }),
    );

    const plain = buildApiModel<{ readonly id: string }>(betterSupabase, {
      info,
      resources: {
        notes: { operations: ["get"], permissions: { get: { id: "x" } } },
      },
    });

    expect(plain.diagnostics).toContainEqual(
      expect.objectContaining({ code: "permission-unresolved" }),
    );
  });

  it("turns permission keys into OAuth scopes", () => {
    const { model } = buildApiModel(betterSupabase, {
      info,
      security: ["bearer", "oauth2"],
      supabaseUrl: "https://abc.supabase.co",
      permissionScopes: "keys",
      resources: {
        notes: {
          operations: ["get", "list"],
          permissions: { get: "notes.read" },
        },
      },
      routes: [
        { method: "get", path: "/open", permission: "open.read", security: [] },
      ],
    });

    expect(model.securitySchemes["supabaseOAuth"]).toMatchObject({
      flows: {
        authorizationCode: {
          scopes: {
            "notes.read": "Permission notes.read.",
            "open.read": "Permission open.read.",
          },
        },
      },
    });
    expect(operation(model, "getNotes").security).toEqual([
      { supabaseJwt: [] },
      { supabaseOAuth: ["notes.read"] },
    ]);
    expect(operation(model, "listNotes").security).toBeUndefined();
    expect(operation(model, "getOpen").security).toEqual([]);
  });

  it("reports writes without a permission when they are required", () => {
    const { diagnostics } = buildApiModel(betterSupabase, {
      info,
      requirePermissions: true,
      resources: {
        notes: { operations: ["list", "create"], permissions: { list: "a" } },
      },
      routes: [
        { method: "get", path: "/read" },
        { method: "post", path: "/write" },
      ],
    });

    expect(
      diagnostics
        .filter((diagnostic) => diagnostic.code === "permission-missing")
        .map((diagnostic) => diagnostic.pointer),
    ).toEqual(["/operations/createNotes", "/operations/postWrite"]);
  });
});

describe("buildApiModel: enrich and passthrough", () => {
  it("lets enrich hooks replace schemas, operations, messages, channels and workflows", () => {
    const { model } = buildApiModel(betterSupabase, {
      info,
      resources: { notes: { operations: ["get"] } },
      messages: {
        noteCreated: { id: "noteCreated", payload: { type: "object" } },
      },
      channels: [
        {
          id: "notes",
          address: "notes",
          protocol: "ws",
          messages: ["noteCreated"],
          operations: [],
        },
      ],
      workflows: [{ id: "w", steps: [] }],
      webhooks: [{ id: "a", payload: {}, standardWebhooks: false }],
      realtimeUrl: "wss://abc.supabase.co/realtime/v1",
      self: "https://api.test/openapi.json",
      fragments: [{ info: { description: "x" } }],
      securityProfileRequirements: { p: { scheme: "profile" } },
      enrich: {
        schema: (schema, { name }) =>
          name === "NotesRow" ? { ...schema, title: "Note" } : undefined,
        operation: (op) => ({ ...op, summary: `${op.summary ?? ""}!` }),
        message: (message, { id }) => ({ ...message, title: id }),
        channel: (channel) => ({ ...channel, title: "Notes" }),
        workflow: (workflow) => ({ ...workflow, summary: "W" }),
      },
    });

    expect(model.schemas["NotesRow"]).toMatchObject({ title: "Note" });
    expect(model.schemas["NotesInsert"]).not.toHaveProperty("title");
    expect(operation(model, "getNotes").summary).toBe("Get a notes row!");
    expect(model.messages["noteCreated"]?.title).toBe("noteCreated");
    expect(model.channels[0]?.title).toBe("Notes");
    expect(model.workflows[0]?.summary).toBe("W");
    expect(model).toMatchObject({
      webhooks: [{ id: "a" }],
      realtimeUrl: "wss://abc.supabase.co/realtime/v1",
      self: "https://api.test/openapi.json",
      fragments: [{ info: { description: "x" } }],
      securityProfileRequirements: { p: { scheme: "profile" } },
    });
  });
});
