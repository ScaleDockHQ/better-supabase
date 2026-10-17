import { describe, expect, it } from "vitest";

import type { ApiModel } from "../../src/spec/model.ts";

import { defineSupabase } from "../../src/core/define.ts";
import { SPEC_PINS } from "../../src/core/spec-pins.ts";
import { openapiFormat } from "../../src/openapi/format.ts";
import { defineApi } from "../../src/spec/api.ts";
import { schema } from "../fixtures/generated-camel.ts";
import { standard } from "../spec/helpers.ts";
import { problems, validatorFor } from "./validator.ts";

type Json = Record<string, unknown>;

const api = defineApi(defineSupabase(schema), {
  info: {
    title: "CRM",
    version: "1.0.0",
    summary: "The CRM API",
    license: { name: "MIT", identifier: "MIT" },
  },
  self: "https://api.test/openapi.json",
  servers: [{ url: "https://api.test", name: "production" }],
  tags: [
    { name: "crm", summary: "CRM", kind: "nav" },
    { name: "customers", parent: "crm" },
  ],
  basePath: "/api",
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
    tags: true,
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
  dataApi: {
    tables: ["customers", "notes"],
    functions: ["customers_by_status", "my_profile", "set_my_avatar_path"],
  },
  webhooks: [
    {
      id: "invoice.paid",
      payload: { type: "object", properties: { id: { type: "string" } } },
      standardWebhooks: true,
    },
  ],
  security: ["bearer", "oauth2", "apiKey"],
  supabaseUrl: "https://abc.supabase.co",
});

const plain = (document: unknown): Json =>
  JSON.parse(JSON.stringify(document)) as Json;

const valid = (document: unknown, file: string) =>
  problems(validatorFor(file), plain(document));

describe(`OpenAPI ${SPEC_PINS.openapi30} (3.0, legacy)`, () => {
  const { document } = api.openapi({ version: "3.0" });

  it("emits SPEC_PINS.openapi30 and validates against the 3.0 schema", () => {
    expect(SPEC_PINS.openapi30).toMatch(/^3\.0\.\d+$/);
    expect(document.openapi).toBe(SPEC_PINS.openapi30);
    expect(valid(document, "openapi-3.0.json")).toEqual([]);
  });

  it("uses 3.0 Schema Objects: no type arrays, no null type", () => {
    const text = JSON.stringify(document);
    expect(text).not.toMatch(/"type":\[/);
    expect(text).not.toContain('"null"');
  });

  it("is rejected by the 3.0 schema when it carries a 3.1 field", () => {
    expect(
      valid({ ...plain(document), webhooks: {} }, "openapi-3.0.json"),
    ).not.toEqual([]);
  });
});

describe(`OpenAPI ${SPEC_PINS.openapi31} (3.1, default)`, () => {
  const { document } = api.openapi({ version: "3.1" });

  it("emits SPEC_PINS.openapi31, the default version", () => {
    expect(document.openapi).toBe(SPEC_PINS.openapi31);
    expect(openapiFormat.defaultVersion).toBe("3.1");
    expect(SPEC_PINS.openapi).toBe(SPEC_PINS.openapi31);
  });

  it("validates against the 3.1 schema", () => {
    expect(valid(document, "openapi-3.1.json")).toEqual([]);
  });

  it("carries 3.2 fields as the registered x-oai extensions", () => {
    expect(document["x-oai-$self"]).toBe("https://api.test/openapi.json");
    expect(document.servers?.[0]).toMatchObject({ "x-oai-name": "production" });
    expect(document).not.toHaveProperty("$self");
  });
});

describe(`OpenAPI ${SPEC_PINS.openapi32} (3.2)`, () => {
  const { document } = api.openapi({ version: "3.2" });

  it("emits SPEC_PINS.openapi32 and validates against the 3.2 schema", () => {
    expect(document.openapi).toBe(SPEC_PINS.openapi32);
    expect(valid(document, "openapi-3.2.json")).toEqual([]);
  });

  it("uses the native 3.2 fields", () => {
    expect(document.$self).toBe("https://api.test/openapi.json");
    expect(document.paths["/api/search"]).toHaveProperty("query");
    expect(JSON.stringify(document)).toContain('"itemSchema"');
    expect(JSON.stringify(document)).not.toContain('"x-oai-');
  });

  it("is rejected by the 3.1 schema", () => {
    expect(valid(document, "openapi-3.1.json")).not.toEqual([]);
  });
});

describe(`OpenAPI 3.3-preview (v3.3-dev at ${SPEC_PINS.openapi33Preview})`, () => {
  const profileModel: ApiModel = {
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
  };

  const document = plain(
    openapiFormat.lower(profileModel, "3.3-preview", { report: () => {} }),
  );

  it("marks the document as a preview of SPEC_PINS.openapi33Preview", () => {
    expect(SPEC_PINS.openapi33Preview).toMatch(/^[0-9a-f]{7}$/);
    expect(openapiFormat.versions["3.3-preview"]).toEqual({
      pin: SPEC_PINS.openapi33Preview,
      status: "preview",
    });
    expect(document["x-better-supabase-preview"]).toBe(
      SPEC_PINS.openapi33Preview,
    );
  });

  it("warns when it is rendered", () => {
    expect(
      api
        .openapi({ version: "3.3-preview" })
        .diagnostics.map((diagnostic) => diagnostic.code),
    ).toContain("preview-version");
  });

  it(`follows the Security Profiles proposal (${SPEC_PINS.securityProfiles})`, () => {
    expect(SPEC_PINS.securityProfiles).toMatch(/^sig-security#50@/);
    const components = document["components"] as Json;
    expect((components["securitySchemes"] as Json)["agents"]).toMatchObject({
      type: "profile",
    });
    expect(components["securityProfileRequirements"]).toEqual({
      agentLogin: { scheme: "agents", scopes: ["a"] },
    });
  });

  it("is a valid 3.2 document once the draft-only fields are removed", () => {
    const stripped = structuredClone(document);
    stripped["openapi"] = SPEC_PINS.openapi32;
    delete stripped["x-better-supabase-preview"];

    for (const item of Object.values(stripped["paths"] as Json)) {
      delete (item as Json)["security"];
    }

    const components = stripped["components"] as Json;
    delete components["securityProfileRequirements"];
    delete (components["securitySchemes"] as Json)["agents"];
    stripped["security"] = (stripped["security"] as Json[]).filter(
      (requirement) => !("agents" in requirement),
    );
    expect(valid(stripped, "openapi-3.2.json")).toEqual([]);
  });
});
