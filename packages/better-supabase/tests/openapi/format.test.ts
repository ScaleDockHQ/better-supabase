import { describe, expect, it } from "vitest";

import type { ApiModel, ModelOperation } from "../../src/spec/model.ts";

import { defineSupabase } from "../../src/core/define.ts";
import { SPEC_PINS } from "../../src/core/spec-pins.ts";
import { openapiFormat } from "../../src/openapi/format.ts";
import { createOpenApi } from "../../src/openapi/index.ts";
import { defineApi } from "../../src/spec/api.ts";
import { schema } from "../fixtures/generated-camel.ts";
import { refsIn, standard } from "../spec/helpers.ts";
import { problems, validatorFor } from "../standards/validator.ts";

const betterSupabase = defineSupabase(schema);

const api = defineApi(betterSupabase, {
  info: {
    title: "CRM",
    version: "1.0.0",
    summary: "The CRM API",
    license: { name: "MIT", identifier: "MIT" },
  },
  self: "https://api.test/openapi.json",
  servers: [
    { url: "https://api.test", name: "production", description: "Prod" },
  ],
  tags: [
    { name: "crm", summary: "CRM", kind: "nav" },
    { name: "customers", parent: "crm" },
  ],
  resources: {
    customers: {
      permissions: { delete: "customers.delete" },
      actions: {
        send: {
          method: "POST",
          path: "/{id}/send",
          output: standard({
            type: "object",
            properties: { at: { type: ["string", "null"] } },
          }),
        },
      },
    },
    notes: { operations: ["list", "get"] },
  },
  routes: [
    { method: "query", path: "/search", summary: "Search" },
    {
      method: "get",
      path: "/events",
      stream: { item: standard({ type: "object" }) },
      security: [{ supabaseJwt: [] }],
    },
  ],
  webhooks: [
    {
      id: "invoice.paid",
      summary: "An invoice was paid",
      payload: { type: "object", properties: { id: { type: "string" } } },
      standardWebhooks: true,
    },
    { id: "ping", payload: { type: "object" }, standardWebhooks: false },
  ],
  security: ["bearer", "oauth2"],
  supabaseUrl: "https://abc.supabase.co",
});

const valid = (
  document: unknown,
  file: "openapi-3.1.json" | "openapi-3.2.json",
) => problems(validatorFor(file), JSON.parse(JSON.stringify(document)));

describe("openapiFormat versions", () => {
  it("lists its versions with their pins", () => {
    expect(openapiFormat.apiVersion).toBe(1);
    expect(openapiFormat.defaultVersion).toBe("3.1");
    expect(openapiFormat.versions).toEqual({
      "3.0": { pin: SPEC_PINS.openapi30, status: "legacy" },
      "3.1": { pin: SPEC_PINS.openapi31, status: "stable" },
      "3.2": { pin: SPEC_PINS.openapi32, status: "stable" },
      "3.3-preview": { pin: SPEC_PINS.openapi33Preview, status: "preview" },
    });
  });

  it("3.1 validates and carries 3.2 fields as x-oai extensions", () => {
    const { document, diagnostics } = api.openapi({ version: "3.1" });
    expect(valid(document, "openapi-3.1.json")).toEqual([]);
    expect(document["x-oai-$self"]).toBe("https://api.test/openapi.json");
    expect(document.servers).toEqual([
      {
        url: "https://api.test",
        description: "Prod",
        "x-oai-name": "production",
      },
    ]);
    expect(document.tags).toContainEqual({
      name: "crm",
      "x-better-supabase-summary": "CRM",
      "x-better-supabase-kind": "nav",
    });
    expect(document.tags).toContainEqual(
      expect.objectContaining({
        name: "customers",
        "x-better-supabase-parent": "crm",
      }),
    );
    expect(document.components.securitySchemes["supabaseOAuth"]).toMatchObject({
      "x-better-supabase-oauth2MetadataUrl":
        "https://abc.supabase.co/.well-known/oauth-authorization-server/auth/v1",
    });
    expect(document.paths["/events"]).toMatchObject({
      get: {
        responses: {
          "200": {
            content: {
              "text/event-stream": { "x-oai-itemSchema": { type: "object" } },
            },
          },
        },
      },
    });
    expect(document.paths["/search"]).toBeUndefined();
    expect(diagnostics).toEqual([
      expect.objectContaining({
        code: "method-unsupported",
        pointer: "/paths/~1search",
      }),
    ]);
  });

  it("3.1 documents webhooks with Standard Webhooks headers", () => {
    const { document } = api.openapi();
    const paid = document.webhooks?.["invoice.paid"];
    expect(paid).toMatchObject({
      post: {
        operationId: "onInvoicePaid",
        summary: "An invoice was paid",
        requestBody: {
          required: true,
          content: { "application/json": { schema: { type: "object" } } },
        },
        responses: { "2XX": {} },
      },
    });
    expect(
      (paid!["post"] as { parameters: { name: string }[] }).parameters.map(
        (parameter) => parameter.name,
      ),
    ).toEqual(["webhook-id", "webhook-timestamp", "webhook-signature"]);
    expect(document.webhooks?.["ping"]?.["post"]).not.toHaveProperty(
      "parameters",
    );
  });

  it("3.2 validates and uses the native fields", () => {
    const { document, diagnostics } = api.openapi({ version: "3.2" });
    expect(diagnostics).toEqual([]);
    expect(valid(document, "openapi-3.2.json")).toEqual([]);
    expect(document.$self).toBe("https://api.test/openapi.json");
    expect(document.servers?.[0]).toMatchObject({ name: "production" });
    expect(document.tags).toContainEqual({
      name: "crm",
      summary: "CRM",
      kind: "nav",
    });
    expect(document.components.securitySchemes["supabaseOAuth"]).toHaveProperty(
      "oauth2MetadataUrl",
    );
    expect(document.paths["/search"]).toMatchObject({
      query: { operationId: "querySearch" },
    });
    expect(document.paths["/events"]).toMatchObject({
      get: {
        responses: {
          "200": {
            content: {
              "text/event-stream": { itemSchema: { type: "object" } },
            },
          },
        },
      },
    });
  });

  it("3.0 lowers schemas and leaves out what it cannot describe", () => {
    const { document, diagnostics } = api.openapi({ version: "3.0" });
    expect(document.openapi).toBe("3.0.4");
    expect(document).not.toHaveProperty("jsonSchemaDialect");
    expect(document).not.toHaveProperty("webhooks");
    expect(document.info).toEqual({
      title: "CRM",
      version: "1.0.0",
      license: { name: "MIT" },
    });
    expect(document.components.schemas["CustomersRow"]).toMatchObject({
      properties: { kvk: { type: "string", nullable: true } },
    });
    expect(JSON.stringify(document)).not.toContain('"null"');
    expect(diagnostics.map((diagnostic) => diagnostic.code)).toEqual([
      "method-unsupported",
      "webhooks-unsupported",
    ]);
  });

  it("3.3-preview adds Path Item security and the preview marker", () => {
    const { document, diagnostics } = api.openapi({ version: "3.3-preview" });
    expect(document.openapi).toBe("3.3.0");
    expect(document["x-better-supabase-preview"]).toBe(
      SPEC_PINS.openapi33Preview,
    );
    expect(document.paths["/events"]).toEqual(
      expect.objectContaining({ security: [{ supabaseJwt: [] }] }),
    );
    expect(document.paths["/events"]?.["get"]).not.toHaveProperty("security");
    expect(diagnostics.map((diagnostic) => diagnostic.code)).toEqual([
      "preview-version",
    ]);
  });

  it("hoists shared path parameters to the Path Item", () => {
    const { document } = api.openapi();
    expect(Object.keys(document.paths["/customers/{id}"] ?? {})).toEqual([
      "parameters",
      "get",
      "patch",
      "delete",
    ]);
    expect(document.paths["/customers/{id}/send"]).toMatchObject({
      parameters: [{ name: "id", in: "path" }],
      post: { responses: { "200": {} } },
    });
    expect(document.paths["/customers/{id}"]?.["delete"]).toMatchObject({
      "x-better-supabase-permission": "customers.delete",
      responses: { "403": { $ref: "#/components/responses/PermissionDenied" } },
    });
  });

  it("only references components that exist", () => {
    for (const version of ["3.0", "3.1", "3.2", "3.3-preview"] as const) {
      const { document, diagnostics } = api.openapi({ version });
      expect(refsIn(document).length).toBeGreaterThan(10);
      expect(
        diagnostics.filter(
          (diagnostic) => diagnostic.code === "ref-unresolved",
        ),
      ).toEqual([]);
    }
  });
});

describe("openapiFormat: fragments and extend", () => {
  it("merges fragments over the generated document and reports conflicts", () => {
    const fragmented = defineApi(betterSupabase, {
      info: { title: "CRM", version: "1.0.0" },
      resources: {
        notes: {
          operations: ["get"],
          extend: { get: { summary: "From extend" } },
        },
      },
      fragments: [
        {
          info: { description: "Added" },
          paths: {
            "/notes/{id}": { get: { summary: "From a fragment", "x-f": 1 } },
            "/health": { get: { responses: { "200": { description: "OK" } } } },
          },
        },
      ],
    });

    const { document, diagnostics } = fragmented.openapi();
    expect(document.info.description).toBe("Added");
    expect(document.paths["/notes/{id}"]?.["get"]).toMatchObject({
      summary: "From extend",
      "x-f": 1,
    });
    expect(document.paths["/health"]).toBeDefined();
    expect(diagnostics).toEqual([
      expect.objectContaining({
        code: "fragment-conflict",
        severity: "warning",
        pointer: "/paths/~1notes~1{id}/get/summary",
      }),
    ]);
  });

  it("throws when a fragment removes a required field", () => {
    const broken = defineApi(betterSupabase, {
      info: { title: "CRM", version: "1.0.0" },
      fragments: [{ paths: [] }],
    });

    expect(() => broken.openapi()).toThrow("removed a required document field");
  });
});

describe("openapiFormat: security profiles", () => {
  const profileModel = (): ApiModel => ({
    ...api.model,
    securitySchemes: {
      ...api.model.securitySchemes,
      agents: {
        type: "profile",
        profileMetadata: { profile: "https://profiles.test/agent" },
      },
    },
    security: [...api.model.security, { agents: [] }],
    securityProfileRequirements: {
      agentLogin: { scheme: "agents", scopes: ["a"] },
    },
  });

  it("emits profiles in 3.3-preview only", () => {
    const diagnostics: unknown[] = [];

    const ctx = {
      report: (diagnostic: unknown) => diagnostics.push(diagnostic),
    };

    const preview = openapiFormat.lower(profileModel(), "3.3-preview", ctx);
    expect(preview.components.securitySchemes["agents"]).toMatchObject({
      type: "profile",
    });
    expect(preview.security).toContainEqual({ agents: [] });
    expect(
      "securityProfileRequirements" in preview.components &&
        preview.components.securityProfileRequirements,
    ).toEqual({ agentLogin: { scheme: "agents", scopes: ["a"] } });
    expect(diagnostics).toEqual([]);

    const stable = openapiFormat.lower(profileModel(), "3.2", ctx);
    expect(stable.components.securitySchemes["agents"]).toBeUndefined();
    expect(stable.security).not.toContainEqual({ agents: [] });
    expect(stable.components).not.toHaveProperty("securityProfileRequirements");
    expect(diagnostics).toEqual([
      expect.objectContaining({
        code: "preview-only",
        severity: "info",
        pointer: "/components/securitySchemes/agents",
      }),
    ]);
  });
});

describe("openapiFormat lint", () => {
  const lint = (patch: (document: Record<string, unknown>) => void) => {
    const document = structuredClone(api.openapi().document);
    patch(document as unknown as Record<string, unknown>);

    return (openapiFormat.lint?.(document, "3.1") ?? []).map(
      (diagnostic) => diagnostic.code,
    );
  };

  it("finds nothing in a generated document", () => {
    expect(lint(() => {})).toEqual([]);
  });

  it("reports duplicate ids, path parameter mismatches, unknown schemes and refs", () => {
    expect(
      lint((document) => {
        const paths = document["paths"] as Record<
          string,
          Record<string, Record<string, unknown>>
        >;

        paths["/notes"]!["get"]!["operationId"] = "getNotes";
        paths["/notes"]!["get"]!["security"] = [{ nope: [] }];
        paths["/x/{a}"] = {
          get: {
            parameters: [{ name: "b", in: "path", required: true }],
            responses: {},
          },
        };
        paths["/y"] = {
          get: {
            responses: { "200": { $ref: "#/components/responses/Gone" } },
          },
        };
      }).toSorted(),
    ).toEqual([
      "operation-id-duplicate",
      "path-param-missing",
      "path-param-unknown",
      "ref-unresolved",
      "security-unresolved",
    ]);
  });

  it("lints a document without components or paths", () => {
    const codes = lint((document) => {
      delete document["components"];
      document["security"] = [{ bearer: [] }];
    });

    expect(new Set(codes)).toEqual(
      new Set(["security-unresolved", "ref-unresolved"]),
    );
    expect(
      lint((document) => {
        delete document["paths"];
        document["components"] = {};
        document["security"] = [];
      }),
    ).toEqual([]);
  });
});

describe("createOpenApi", () => {
  const options = {
    info: { title: "CRM", version: "1.0.0" },
    resources: { notes: { operations: ["get"] } },
  } as const;

  it("renders the requested version", () => {
    expect(createOpenApi(betterSupabase, options).openapi).toBe("3.1.2");
    expect(
      createOpenApi(betterSupabase, { ...options, version: "3.2" }).openapi,
    ).toBe("3.2.1");
  });

  it("passes transform and overlays through and reports findings", () => {
    const heard: string[] = [];

    const document = createOpenApi(betterSupabase, {
      ...options,
      version: "3.3-preview",
      transform: (rendered) => ({ ...rendered.document, "x-t": 1 }),
      overlays: [{}],
      applyOverlays: (doc) => ({ document: doc }),
      onDiagnostic: (diagnostic) => heard.push(diagnostic.code),
    });

    expect(document["x-t"]).toBe(1);
    expect(heard).toEqual(["preview-version"]);
  });

  it("throws on errors", () => {
    expect(() =>
      createOpenApi(betterSupabase, {
        ...options,
        routes: [{ method: "get", path: "/x", operationId: "getNotes" }],
      }),
    ).toThrow("operation-id-duplicate");
  });
});

describe("lowering", () => {
  it("keeps model operations untouched by lowering", () => {
    const before: readonly ModelOperation[] = structuredClone(
      api.model.operations,
    );

    api.openapi({ version: "3.0" });
    expect(api.model.operations).toEqual(before);
  });
});
