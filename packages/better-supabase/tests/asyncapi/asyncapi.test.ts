import { describe, expect, it } from "vitest";

import type {
  BlockEventSchema,
  BlockEventSchemas,
} from "../../src/asyncapi/index.ts";
import type { AnyAsyncApiDocument } from "../../src/asyncapi/types.ts";
import type { SupportEventData } from "../../src/core/block-events.ts";
import type { SpecDiagnostic } from "../../src/spec/format.ts";
import type { ApiModel } from "../../src/spec/model.ts";

import { asyncapiFormat, createAsyncApi } from "../../src/asyncapi/index.ts";
import { defineSupabase } from "../../src/core/define.ts";
import { SPEC_PINS } from "../../src/core/spec-pins.ts";
import { defineSchema } from "../../src/schema/define.ts";
import { defineApi } from "../../src/spec/api.ts";
import { schema } from "../fixtures/generated-camel.ts";
import { opaque, refsIn, standard } from "../spec/helpers.ts";
import { problems, validatorFor } from "../standards/validator.ts";

type Json = Record<string, unknown>;

const meta = {
  ...schema.meta,
  realtime: {
    customers: { tenant: "organizationId" },
    notes: { user: "authorId" },
    tags: {},
  },
};
const betterSupabase = defineSupabase(defineSchema(meta));

const info = { title: "CRM events", version: "1.0.0" };

// SAFETY: the test schema stands for one whose output is SupportEventData.
const supportStarted = standard({
  type: "object",
  properties: { sessionId: { type: "string" } },
}) as unknown as BlockEventSchema<SupportEventData>;
const realtimeUrl = "https://crm.supabase.co/realtime/v1/websocket";

const api = defineApi(betterSupabase, {
  info: { ...info, summary: "Events of the CRM", license: { name: "MIT" } },
  servers: [{ url: "https://api.test/v1", name: "production" }],
  realtimeUrl,
  security: [
    "bearer",
    "apiKey",
    "oauth2",
    {
      name: "profile",
      scheme: {
        type: "profile",
        profileMetadata: { profile: "https://profiles.test/p" },
      },
    },
  ],
  supabaseUrl: "https://crm.supabase.co",
  resources: {
    customers: {
      actions: {
        send: { method: "POST", path: "/{id}/send", emits: ["sent", "nope"] },
      },
    },
    notes: { operations: ["list", "get"] },
  },
  events: {
    topics: {
      notifications: {
        template: "organization:{organizationId}:notifications:{userId}",
        events: {
          created: standard({
            type: "object",
            properties: { id: { type: "string" } },
          }),
          dismissed: true,
        },
        presence: true,
        permission: "notifications.read",
        summary: "Notifications",
        description: "Per-user notifications",
      },
      lobby: { template: "lobby", send: true, private: false, name: "Lobby" },
      cursors: {
        template: "cursors",
        events: { moved: opaque(), sent: true },
      },
    },
    cloudEvents: {
      source: "/crm",
      rows: ["customers", "contacts"],
      intents: ["insert"],
      dataschema: ({ type }) => `https://schemas.test/${type}.json`,
      blocks: {
        "support.started": supportStarted,
        "support.ended": true,
      },
    },
  },
  webhooks: [
    {
      id: "invoice.paid",
      summary: "An invoice was paid",
      description: "Sent once per invoice",
      payload: { type: "object", properties: { id: { type: "string" } } },
      standardWebhooks: true,
    },
    { id: "ping", payload: { type: "object" }, standardWebhooks: false },
  ],
});

const codes = (diagnostics: readonly SpecDiagnostic[]) =>
  diagnostics.map((diagnostic) => diagnostic.code);

describe("asyncapiFormat", () => {
  const rendered = api.render(asyncapiFormat);
  const doc = rendered.document;
  const channels = doc.channels;
  const operations = doc.operations;

  it("renders 3.0 by default, under the pinned version and file name", () => {
    expect(rendered.version).toBe("3.0");
    expect(doc.asyncapi).toBe(SPEC_PINS.asyncapi30);
    expect(rendered.fileName).toBe("asyncapi.json");
    expect(doc.info).toEqual({
      title: "CRM events",
      version: "1.0.0",
      description: "Events of the CRM",
      license: { name: "MIT" },
    });
    expect(doc.defaultContentType).toBe("application/json");
  });

  it("validates against the official 3.0.0 and 3.1.0 schemas", () => {
    expect(problems(validatorFor("asyncapi-3.0.0.json"), doc)).toEqual([]);
    const v31 = api.render(asyncapiFormat, { version: "3.1" });
    expect(v31.document.asyncapi).toBe(SPEC_PINS.asyncapi31);
    expect(problems(validatorFor("asyncapi-3.1.0.json"), v31.document)).toEqual(
      [],
    );
    expect({ ...v31.document, asyncapi: doc.asyncapi }).toEqual(doc);
  });

  it("resolves every reference and lints clean", () => {
    for (const ref of refsIn(doc)) {
      const target = ref
        .slice(2)
        .split("/")
        .reduce<unknown>(
          (node, key) =>
            node && typeof node === "object"
              ? (node as Json)[key.replaceAll("~1", "/")]
              : undefined,
          doc,
        );
      expect({ ref, resolves: target !== undefined }).toEqual({
        ref,
        resolves: true,
      });
    }
    expect(rendered.diagnostics.filter((d) => d.severity === "error")).toEqual(
      [],
    );
  });

  it("puts the Realtime websocket and the HTTP API in servers", () => {
    expect(doc.servers?.["realtime"]).toMatchObject({
      host: "crm.supabase.co",
      protocol: "wss",
      pathname: "/realtime/v1/websocket",
      security: [
        { $ref: "#/components/securitySchemes/supabaseJwt" },
        { $ref: "#/components/securitySchemes/supabaseApiKey" },
        { $ref: "#/components/securitySchemes/supabaseOAuth" },
      ],
    });
    expect(doc.servers?.["production"]).toEqual({
      host: "api.test",
      protocol: "https",
      pathname: "/v1",
    });
  });

  it("maps the security schemes to AsyncAPI types", () => {
    const schemes = doc.components.securitySchemes ?? {};
    expect(schemes["supabaseApiKey"]).toMatchObject({ type: "httpApiKey" });
    expect(schemes["supabaseOAuth"]).toMatchObject({ type: "oauth2" });
    const flows = (schemes["supabaseOAuth"]?.["flows"] ?? {}) as Json;
    for (const flow of Object.values(flows)) {
      expect(flow).toHaveProperty("availableScopes");
      expect(flow).not.toHaveProperty("scopes");
    }
    expect(schemes).not.toHaveProperty("profile");
    expect(codes(rendered.diagnostics)).toContain(
      "asyncapi-security-unsupported",
    );
  });

  it("describes table change signals with their topic parameters", () => {
    expect(channels["tableCustomers"]).toMatchObject({
      address: "bs:t:public.customers:{tenant}",
      parameters: {
        tenant: { description: "The row's `organizationId` value." },
      },
      servers: [{ $ref: "#/servers/realtime" }],
      bindings: { ws: { method: "GET", bindingVersion: "0.1.0" } },
      "x-better-supabase-table": "public.customers",
    });
    expect(channels["tableNotes"]?.["address"]).toBe(
      "bs:t:public.notes:u:{userId}",
    );
    expect(channels["tableTags"]?.["address"]).toBe("bs:t:public.tags");
    expect(channels["tableTags"]).not.toHaveProperty("parameters");
    const message = doc.components.messages?.["tableCustomersChange"];
    expect(message).toMatchObject({
      name: "change",
      payload: {
        properties: {
          schema: { const: "public" },
          table: { const: "customers" },
          operation: { enum: ["INSERT", "UPDATE", "DELETE"] },
        },
      },
    });
    expect(operations["receiveCustomersChanges"]).toEqual({
      action: "receive",
      channel: { $ref: "#/channels/tableCustomers" },
      summary: "Change signals for customers",
    });
  });

  it("describes topics: events, presence, send and permission keys", () => {
    expect(channels["topicNotifications"]).toMatchObject({
      address: "organization:{organizationId}:notifications:{userId}",
      title: "notifications",
      summary: "Notifications",
      description: "Per-user notifications",
      parameters: { organizationId: {}, userId: {} },
      "x-better-supabase-private": true,
    });
    expect(
      Object.keys(channels["topicNotifications"]?.["messages"] as Json),
    ).toEqual([
      "topicNotificationsCreated",
      "topicNotificationsDismissed",
      "topicNotificationsPresence",
    ]);
    expect(
      doc.components.messages?.["topicNotificationsCreated"],
    ).toMatchObject({
      name: "created",
      payload: { properties: { id: { type: "string" } } },
    });
    expect(operations["receiveNotifications"]).toMatchObject({
      action: "receive",
      "x-better-supabase-permission": "notifications.read",
    });
    expect(operations["sendNotifications"]).toMatchObject({ action: "send" });
    expect(channels["topicLobby"]).toMatchObject({
      title: "Lobby",
      "x-better-supabase-private": false,
    });
    expect(Object.keys(channels["topicLobby"]?.["messages"] as Json)).toEqual([
      "topicLobbyAny",
    ]);
    expect(operations["sendLobby"]).toBeDefined();
    expect(operations["sendCursors"]).toBeUndefined();
    expect(codes(rendered.diagnostics)).toEqual(
      expect.arrayContaining(["asyncapi-topic-open", "asyncapi-schema-opaque"]),
    );
  });

  it("describes CloudEvents with the header trait and dataschema", () => {
    expect(channels["cloudEvents"]).toMatchObject({
      address: "events",
      servers: [{ $ref: "#/servers/production" }],
    });
    expect(channels["cloudEvents"]).not.toHaveProperty("bindings");
    expect(doc.components.messageTraits?.["cloudEvent"]).toMatchObject({
      headers: { properties: { "ce-specversion": { const: "1.0" } } },
    });
    const row = doc.components.messages?.["rowCustomersCreated"];
    expect(row).toMatchObject({
      name: "dev.better-supabase.row.created",
      traits: [{ $ref: "#/components/messageTraits/cloudEvent" }],
      headers: {
        properties: {
          "ce-type": { const: "dev.better-supabase.row.created" },
          "ce-dataschema": {
            const: "https://schemas.test/dev.better-supabase.row.created.json",
          },
        },
      },
      payload: {
        properties: {
          table: { const: "customers" },
          row: { $ref: "#/components/schemas/CustomersRow" },
        },
      },
      "x-better-supabase-dataschema":
        "https://schemas.test/dev.better-supabase.row.created.json",
    });
    expect(doc.components.schemas?.["CustomersRow"]).toBeDefined();
    const contacts = doc.components.messages?.["rowContactsCreated"] as Json;
    expect((contacts["payload"] as Json)["properties"]).toMatchObject({
      row: { type: "object" },
    });
    expect(doc.components.messages?.["blockSupportStarted"]).toMatchObject({
      name: "dev.better-supabase.support.started",
      payload: {
        properties: {
          sessionId: { type: "string" },
          actorId: { type: "string" },
        },
      },
    });
    expect(operations["sendCloudEvents"]).toMatchObject({ action: "send" });
  });

  it("describes outgoing webhooks with the Standard Webhooks headers", () => {
    expect(channels["webhooks"]).toMatchObject({ address: null });
    expect(doc.components.messages?.["webhookInvoicePaid"]).toMatchObject({
      name: "invoice.paid",
      summary: "An invoice was paid",
      description: "Sent once per invoice",
      headers: {
        required: ["webhook-id", "webhook-timestamp", "webhook-signature"],
      },
    });
    expect(doc.components.messages?.["webhookPing"]).not.toHaveProperty(
      "headers",
    );
    expect(operations["sendInvoicePaidWebhook"]).toMatchObject({
      action: "send",
      messages: [{ $ref: "#/channels/webhooks/messages/webhookInvoicePaid" }],
    });
  });

  it("links actions to the events they emit", () => {
    expect(operations["sendCustomersEmits"]).toEqual({
      action: "send",
      channel: { $ref: "#/channels/topicCursors" },
      summary: "Events sent by POST /customers/{id}/send",
      messages: [{ $ref: "#/channels/topicCursors/messages/topicCursorsSent" }],
      "x-better-supabase-operation": "sendCustomers",
    });
    expect(rendered.diagnostics).toContainEqual(
      expect.objectContaining({
        code: "asyncapi-emits-unknown",
        severity: "warning",
      }),
    );
  });
});

describe("asyncapiFormat: findings", () => {
  const base = (options: Partial<Parameters<typeof defineApi>[1]> = {}) =>
    defineApi(betterSupabase, { info, ...options });

  it("adds nothing without events", () => {
    const { document, diagnostics } = base().render(asyncapiFormat);
    expect(document.channels).toEqual({});
    expect(document.operations).toEqual({});
    expect(document).not.toHaveProperty("servers");
    expect(document.components).not.toHaveProperty("messages");
    expect(diagnostics.filter((d) => d.severity === "error")).toEqual([]);
  });

  it("warns when Realtime channels have no server", () => {
    const { diagnostics } = base({ events: {} }).render(asyncapiFormat);
    expect(codes(diagnostics)).toContain("asyncapi-server-missing");
  });

  it("reports an invalid realtimeUrl and unknown tables", () => {
    const { diagnostics } = base({
      realtimeUrl: "not a url",
      events: {
        tables: ["customers", "contacts"],
        cloudEvents: { source: "/crm", rows: ["missing"] },
      },
    }).render(asyncapiFormat);
    expect(codes(diagnostics)).toEqual(
      expect.arrayContaining([
        "asyncapi-realtime-url-invalid",
        "asyncapi-table-unknown",
      ]),
    );
  });

  it("documents every table and every row event with true", () => {
    const { model } = base({
      realtimeUrl: "ws://localhost:54321/realtime/v1/websocket",
      events: {
        cloudEvents: { source: "/crm", rows: true, typePrefix: "com.crm" },
      },
    });
    const doc = asyncapiFormat.lower(model, "3.0", { report: () => {} });
    expect(doc.servers?.["realtime"]).toMatchObject({ protocol: "ws" });
    expect(Object.keys(doc.channels)).toEqual([
      "tableCustomers",
      "tableNotes",
      "tableTags",
      "cloudEvents",
    ]);
    expect(doc.components.messages?.["rowNotesDeleted"]).toMatchObject({
      name: "com.crm.row.deleted",
    });
  });

  it("leaves out the tables when tables is false and CloudEvents when empty", () => {
    const { model } = base({
      events: { tables: false, cloudEvents: { source: "/crm" } },
    });
    expect(model.channels).toEqual([]);
    expect(model.messageTraits).toBeUndefined();
  });

  it("reports app channels with unknown messages and bad keys", () => {
    const { model } = base({
      messages: {
        "chat message": {
          id: "chat message",
          payload: { type: "object", $defs: { x: { type: "string" } } },
        },
      },
      channels: [
        {
          id: "chat room",
          address: "chat:{room}",
          protocol: "ws",
          messages: ["chat message", "missing"],
          operations: [
            {
              id: "receiveChat",
              action: "receive",
              messages: ["chat message", "other"],
            },
            { id: "receiveChat", action: "receive" },
          ],
        },
        {
          id: "chat_room",
          address: "dup",
          protocol: "ws",
          messages: [],
          operations: [],
        },
      ],
    });
    const found: SpecDiagnostic[] = [];
    const doc = asyncapiFormat.lower(model, "3.0", {
      report: (diagnostic) => found.push(diagnostic),
    });
    expect(codes(found)).toEqual(
      expect.arrayContaining([
        "asyncapi-key-invalid",
        "asyncapi-message-unknown",
        "asyncapi-operation-message-unknown",
        "asyncapi-operation-id-duplicate",
        "asyncapi-channel-id-duplicate",
        "asyncapi-schema-dialect",
        "asyncapi-server-missing",
      ]),
    );
    expect(doc.channels["chat_room"]).toMatchObject({
      address: "chat:{room}",
      parameters: { room: {} },
    });
  });

  it("reports combined security requirements", () => {
    const { model } = base();
    const combined: ApiModel = {
      ...model,
      realtimeUrl,
      security: [{ supabaseJwt: [], other: [] }],
      channels: [
        { id: "c", address: "c", protocol: "ws", messages: [], operations: [] },
      ],
    };
    const found: SpecDiagnostic[] = [];
    const doc = asyncapiFormat.lower(combined, "3.0", {
      report: (diagnostic) => found.push(diagnostic),
    });
    expect(codes(found)).toContain("asyncapi-security-combined");
    expect(doc.servers?.["realtime"]?.["security"]).toEqual([
      { $ref: "#/components/securitySchemes/supabaseJwt" },
    ]);
  });

  it("keeps openIdConnect schemes and app extensions", () => {
    const { model } = base({
      security: [
        {
          name: "oidc",
          scheme: {
            type: "openIdConnect",
            openIdConnectUrl: "https://id.test",
          },
        },
      ],
      messages: {
        m: {
          id: "m",
          payload: { type: "object" },
          extensions: { owner: "crm" },
        },
      },
    });
    const doc = asyncapiFormat.lower(model, "3.1", { report: () => {} });
    expect(doc.components.securitySchemes?.["oidc"]).toEqual({
      type: "openIdConnect",
      openIdConnectUrl: "https://id.test",
    });
    expect(doc.components.messages?.["m"]).toMatchObject({
      "x-better-supabase-owner": "crm",
    });
  });
});

describe("asyncapiFormat: lint", () => {
  const lint = (doc: AnyAsyncApiDocument) =>
    asyncapiFormat.lint?.(doc, "3.0") ?? [];
  const doc = api.render(asyncapiFormat).document;

  it("finds broken references, parameters, channels and messages", () => {
    const broken = structuredClone(doc) as unknown as Json;
    const channels = broken["channels"] as Record<string, Json>;
    const operations = broken["operations"] as Record<string, Json>;
    channels["bad key"] = { address: "x:{a}", parameters: { b: {} } };
    channels["noAddress"] = { address: null, messages: {} };
    operations["orphan"] = { action: "send", channel: { $ref: "#/elsewhere" } };
    operations["stray"] = {
      action: "send",
      channel: { $ref: "#/channels/tableTags" },
      messages: [
        { $ref: "#/channels/tableCustomers/messages/tableCustomersChange" },
      ],
    };
    const found = codes(lint(broken as unknown as AnyAsyncApiDocument));
    expect(found).toEqual(
      expect.arrayContaining([
        "asyncapi-ref-unresolved",
        "asyncapi-key-invalid",
        "asyncapi-parameter-unknown",
        "asyncapi-parameter-missing",
        "asyncapi-operation-channel-unknown",
        "asyncapi-operation-message-unknown",
      ]),
    );
  });
});

describe("BlockEventSchemas", () => {
  it("checks schemas against BlockEventMap", () => {
    const wrong = {} as BlockEventSchema<{ readonly adminId: number }>;
    // @ts-expect-error: adminId is a string in SupportEventData
    const schemas: BlockEventSchemas = { "support.started": wrong };
    expect(schemas).toBeDefined();
    // @ts-expect-error: not a block event
    const unknown: BlockEventSchemas = { "nope.event": true };
    expect(unknown).toBeDefined();
  });
});

describe("createAsyncApi", () => {
  it("returns the document and passes findings to onDiagnostic", () => {
    const heard: string[] = [];
    const doc = createAsyncApi(betterSupabase, {
      info,
      realtimeUrl,
      events: { tables: ["customers"] },
      onDiagnostic: (diagnostic) => heard.push(diagnostic.code),
    });
    expect(doc.asyncapi).toBe(SPEC_PINS.asyncapi30);
    expect(Object.keys(doc.channels)).toEqual(["tableCustomers"]);
    expect(Array.isArray(heard)).toBe(true);
  });

  it("renders 3.1 and runs transform and overlays", () => {
    const doc = createAsyncApi(betterSupabase, {
      info,
      realtimeUrl,
      version: "3.1",
      events: {},
      transform: ({ version, document }) => {
        expect(version).toBe("3.1");
        return { ...document, info: { ...document.info, title: "Changed" } };
      },
      overlays: [],
    });
    expect(doc.asyncapi).toBe(SPEC_PINS.asyncapi31);
    expect(doc.info.title).toBe("Changed");
  });

  it("throws on errors", () => {
    expect(() =>
      createAsyncApi(betterSupabase, {
        info,
        events: { tables: ["contacts"] },
      }),
    ).toThrow(/createAsyncApi: asyncapi-table-unknown/);
  });
});
