import type {
  DocumentFormat,
  LowerContext,
  SpecDiagnostic,
} from "../spec/format.ts";
import type {
  ApiModel,
  JsonSchema,
  ModelChannel,
  ModelMessage,
  ModelMessageTrait,
  ModelSecurityScheme,
  ModelWebhook,
} from "../spec/model.ts";
import type {
  AnyAsyncApiDocument,
  AsyncApiDocuments,
  AsyncApiVersion,
} from "./types.ts";

import { isPlainObject } from "../core/clone.ts";
import { SPEC_PINS } from "../core/spec-pins.ts";
import { safeKey } from "../spec/events.ts";
import { defineDocumentFormat } from "../spec/format.ts";
import { pointerToken } from "../spec/merge.ts";
import { pascal } from "../spec/schemas.ts";
import { ASYNCAPI_FILE_NAME } from "./types.ts";

type Json = Record<string, unknown>;

const ASYNCAPI_FIELD = {
  "3.0": SPEC_PINS.asyncapi30,
  "3.1": SPEC_PINS.asyncapi31,
} as const satisfies Record<AsyncApiVersion, string>;

const SCHEMA_PREFIX = "#/components/schemas/";
const KEY = /^[A-Za-z0-9_-]+$/;
const PARAM = /\{([^}]+)\}/g;

/** JSON Schema 2020-12 keywords the AsyncAPI Schema Object (draft-07) lacks. */
const KEYWORDS_2020: ReadonlySet<string> = new Set([
  "$defs",
  "$anchor",
  "$dynamicRef",
  "$dynamicAnchor",
  "prefixItems",
  "dependentSchemas",
  "dependentRequired",
  "unevaluatedProperties",
  "unevaluatedItems",
]);

/** The query Supabase Realtime reads on the websocket upgrade. */
const WS_BINDING: Json = {
  ws: {
    method: "GET",
    query: {
      type: "object",
      required: ["apikey"],
      properties: {
        apikey: {
          type: "string",
          description: "The project's publishable (anon) key.",
        },
        vsn: { type: "string", description: "Realtime protocol version." },
      },
    },
    bindingVersion: "0.1.0",
  },
};

const STANDARD_WEBHOOK_HEADERS: JsonSchema = {
  type: "object",
  required: ["webhook-id", "webhook-timestamp", "webhook-signature"],
  properties: {
    "webhook-id": {
      type: "string",
      description: "Unique message id; the same on every retry.",
    },
    "webhook-timestamp": {
      type: "string",
      pattern: "^[0-9]+$",
      description: "Unix time in seconds when the message was sent.",
    },
    "webhook-signature": {
      type: "string",
      description:
        "Space-separated signatures of `id.timestamp.body`, each `v1,<base64>`.",
    },
  },
};

const omitUndefined = (value: Json): Json =>
  Object.fromEntries(
    Object.entries(value).filter(([, entry]) => entry !== undefined),
  );

function collectRefs(value: unknown, out: Set<string>): void {
  if (Array.isArray(value)) {
    // SAFETY: Array.isArray narrows to any[]; each item is read as unknown.
    for (const item of value as readonly unknown[]) {
      collectRefs(item, out);
    }
  } else if (isPlainObject(value)) {
    for (const [key, item] of Object.entries(value)) {
      if (key === "$ref" && typeof item === "string") {
        out.add(item);
      } else {
        collectRefs(item, out);
      }
    }
  }
}

function uses2020(value: unknown): boolean {
  if (Array.isArray(value)) {
    // SAFETY: Array.isArray narrows to any[]; each item is read as unknown.
    const items = value as readonly unknown[];
    return items.some(uses2020);
  }
  if (!isPlainObject(value)) {
    return false;
  }
  return Object.entries(value).some(
    ([key, item]) => KEYWORDS_2020.has(key) || uses2020(item),
  );
}

/** Component names a set of values references, with everything they reference. */
function referencedSchemas(
  model: ApiModel,
  roots: readonly unknown[],
): Record<string, JsonSchema> {
  const out: Record<string, JsonSchema> = {};
  const pending: string[] = [];
  const visit = (value: unknown) => {
    const refs = new Set<string>();
    collectRefs(value, refs);
    for (const ref of refs) {
      if (!ref.startsWith(SCHEMA_PREFIX)) {
        continue;
      }
      const name = ref
        .slice(SCHEMA_PREFIX.length)
        .replaceAll("~1", "/")
        .replaceAll("~0", "~");
      if (name in out || !model.schemas[name]) {
        continue;
      }
      out[name] = model.schemas[name];
      pending.push(name);
    }
  };
  for (const root of roots) {
    visit(root);
  }
  while (pending.length > 0) {
    const name = pending.pop();
    if (name !== undefined) {
      visit(out[name]);
    }
  }
  const sorted: Record<string, JsonSchema> = {};
  for (const name of Object.keys(out).toSorted()) {
    const schema = out[name];
    if (schema) {
      sorted[name] = structuredClone(schema);
    }
  }
  return sorted;
}

function lowerScheme(
  name: string,
  scheme: ModelSecurityScheme,
  ctx: LowerContext,
): Json | undefined {
  switch (scheme.type) {
    case "http": {
      return omitUndefined({ ...scheme });
    }
    case "apiKey": {
      return omitUndefined({
        type: "httpApiKey",
        name: scheme.name,
        in: scheme.in,
        description: scheme.description,
      });
    }
    case "openIdConnect": {
      return omitUndefined({ ...scheme });
    }
    case "oauth2": {
      const flows: Json = {};
      for (const [flow, value] of Object.entries(scheme.flows)) {
        const { scopes, ...rest } = value;
        flows[flow] = omitUndefined({
          ...rest,
          availableScopes: { ...scopes },
        });
      }
      return omitUndefined({
        type: "oauth2",
        description: scheme.description,
        flows,
      });
    }
    case "profile": {
      ctx.report({
        code: "asyncapi-security-unsupported",
        severity: "info",
        message: `Security scheme "${name}" uses Security Profiles, which AsyncAPI cannot describe; it is left out`,
        pointer: `/components/securitySchemes/${pointerToken(name)}`,
      });
      return undefined;
    }
    default: {
      const unknown: never = scheme;
      return unknown;
    }
  }
}

function lowerMessage(message: ModelMessage, prefix: string): Json {
  return omitUndefined({
    name: message.name,
    title: message.title,
    summary: message.summary,
    description: message.description,
    contentType: message.contentType,
    headers: message.headers ? structuredClone(message.headers) : undefined,
    payload: structuredClone(message.payload),
    correlationId: message.correlationId
      ? { location: message.correlationId }
      : undefined,
    traits: message.traits?.map((trait) => ({
      $ref: `#/components/messageTraits/${safeKey(trait)}`,
    })),
    ...Object.fromEntries(
      Object.entries(message.extensions ?? {}).map(([key, value]) => [
        key.startsWith("x-") ? key : `${prefix}${key}`,
        value,
      ]),
    ),
  });
}

function lowerTrait(trait: ModelMessageTrait): Json {
  return omitUndefined({
    ...trait,
    headers: trait.headers ? structuredClone(trait.headers) : undefined,
  });
}

function webhookMessage(webhook: ModelWebhook): ModelMessage {
  return {
    id: `webhook${safeKey(pascal(webhook.id))}`,
    name: webhook.id,
    title: webhook.id,
    ...(webhook.summary ? { summary: webhook.summary } : {}),
    ...(webhook.description ? { description: webhook.description } : {}),
    contentType: "application/json",
    ...(webhook.standardWebhooks ? { headers: STANDARD_WEBHOOK_HEADERS } : {}),
    payload: webhook.payload,
  };
}

/** A server from a URL: `host` and `pathname` split, the scheme as protocol. */
function serverFrom(
  url: string,
  fields: Json,
  wsDefault: boolean,
): Json | undefined {
  let parsed: URL;
  try {
    parsed = new URL(url);
  } catch {
    return undefined;
  }
  const scheme = parsed.protocol.slice(0, -1);
  const protocol = wsDefault
    ? scheme === "http" || scheme === "ws"
      ? "ws"
      : "wss"
    : scheme;
  const pathname = parsed.pathname === "/" ? undefined : parsed.pathname;
  return omitUndefined({
    host: parsed.host,
    protocol,
    pathname,
    ...fields,
  });
}

interface Placed {
  readonly key: string;
  readonly channel: ModelChannel;
}

function lowerAsyncApi(
  model: ApiModel,
  version: AsyncApiVersion,
  ctx: LowerContext,
): AnyAsyncApiDocument {
  const prefix = model.extensionPrefix;
  const keyOf = (id: string, where: string): string => {
    if (KEY.test(id)) {
      return id;
    }
    const key = safeKey(id);
    ctx.report({
      code: "asyncapi-key-invalid",
      severity: "info",
      message: `${where} "${id}" is written as "${key}"; AsyncAPI keys allow letters, digits, "_" and "-"`,
    });
    return key;
  };

  const securitySchemes: Json = {};
  for (const [name, scheme] of Object.entries(model.securitySchemes)) {
    const lowered = lowerScheme(name, scheme, ctx);
    if (lowered) {
      securitySchemes[safeKey(name)] = lowered;
    }
  }
  const security: Json[] = [];
  for (const requirement of model.security) {
    const names = Object.keys(requirement);
    if (names.length > 1) {
      ctx.report({
        code: "asyncapi-security-combined",
        severity: "info",
        message: `A requirement that needs ${names.join(" and ")} together is listed as alternatives; AsyncAPI security lists have no AND`,
        pointer: "/security",
      });
    }
    for (const name of names) {
      const key = safeKey(name);
      if (
        key in securitySchemes &&
        !security.some(
          (entry) => entry["$ref"] === `#/components/securitySchemes/${key}`,
        )
      ) {
        security.push({ $ref: `#/components/securitySchemes/${key}` });
      }
    }
  }

  const webhookMessages = model.webhooks.map(webhookMessage);
  const allMessages: Record<string, ModelMessage> = { ...model.messages };
  for (const message of webhookMessages) {
    allMessages[message.id] = message;
  }
  const channels: ModelChannel[] = [...model.channels];
  if (webhookMessages.length > 0) {
    channels.push({
      id: "webhooks",
      address: "",
      title: "Outgoing webhooks",
      description:
        "Webhooks the app sends to each receiver's URL, signed per Standard Webhooks when the headers are listed.",
      protocol: "http",
      messages: webhookMessages.map((message) => message.id),
      operations: model.webhooks.map((webhook, index) => ({
        id: `send${safeKey(pascal(webhook.id))}Webhook`,
        action: "send",
        ...(webhook.summary ? { summary: webhook.summary } : {}),
        messages: [webhookMessages[index]?.id ?? webhook.id],
      })),
    });
  }

  const servers: Json = {};
  const wsServers: Json[] = [];
  const httpServers: Json[] = [];
  const hasWs = channels.some((channel) => channel.protocol === "ws");
  const hasHttp = channels.some((channel) => channel.protocol === "http");
  if (hasWs && model.realtimeUrl) {
    const server = serverFrom(
      model.realtimeUrl,
      {
        title: "Supabase Realtime",
        description:
          "The Realtime websocket. Private channels need the user's access token.",
        security: security.length > 0 ? security : undefined,
      },
      true,
    );
    if (server) {
      servers["realtime"] = server;
      wsServers.push({ $ref: "#/servers/realtime" });
    } else {
      ctx.report({
        code: "asyncapi-realtime-url-invalid",
        severity: "error",
        message: `realtimeUrl "${model.realtimeUrl}" is not an absolute URL`,
        pointer: "/servers/realtime",
      });
    }
  } else if (hasWs) {
    ctx.report({
      code: "asyncapi-server-missing",
      severity: "warning",
      message:
        "Realtime channels are described without a server; set realtimeUrl to add the Realtime websocket",
      pointer: "/servers",
    });
  }
  if (hasHttp) {
    model.servers.forEach((entry, index) => {
      const key = safeKey(
        entry.name ?? (index === 0 ? "api" : `api${String(index + 1)}`),
      );
      const server = serverFrom(
        entry.url,
        omitUndefined({ description: entry.description }),
        false,
      );
      if (!server || key in servers) {
        return;
      }
      servers[key] = server;
      httpServers.push({ $ref: `#/servers/${key}` });
    });
  }

  const messageKeys = new Map<string, string>();
  const messages: Json = {};
  for (const [id, message] of Object.entries(allMessages)) {
    const key = keyOf(id, "Message");
    messageKeys.set(id, key);
    messages[key] = lowerMessage(message, prefix);
    if (uses2020(message.payload) || uses2020(message.headers)) {
      ctx.report({
        code: "asyncapi-schema-dialect",
        severity: "warning",
        message: `Message "${id}" uses JSON Schema 2020-12 keywords that the AsyncAPI Schema Object (draft-07) does not define`,
        pointer: `/components/messages/${pointerToken(key)}`,
      });
    }
  }

  const channelObjects: Json = {};
  const operations: Json = {};
  const placed: Placed[] = [];
  const addOperation = (key: string, operation: Json, pointer: string) => {
    if (key in operations) {
      ctx.report({
        code: "asyncapi-operation-id-duplicate",
        severity: "error",
        message: `Two operations have the id "${key}"; the first one is kept`,
        pointer,
      });
      return;
    }
    operations[key] = operation;
  };
  for (const channel of channels) {
    const key = keyOf(channel.id, "Channel");
    if (key in channelObjects) {
      ctx.report({
        code: "asyncapi-channel-id-duplicate",
        severity: "error",
        message: `Two channels have the id "${key}"; the first one is kept`,
        pointer: `/channels/${pointerToken(key)}`,
      });
      continue;
    }
    placed.push({ key, channel });
    const channelMessages: Json = {};
    for (const id of channel.messages) {
      const messageKey = messageKeys.get(id);
      if (messageKey === undefined) {
        ctx.report({
          code: "asyncapi-message-unknown",
          severity: "error",
          message: `Channel "${channel.id}" lists an unknown message "${id}"`,
          pointer: `/channels/${pointerToken(key)}/messages`,
        });
        continue;
      }
      channelMessages[messageKey] = {
        $ref: `#/components/messages/${messageKey}`,
      };
    }
    const names = [...channel.address.matchAll(PARAM)].map(
      (match) => match[1] ?? "",
    );
    const parameters =
      names.length > 0
        ? Object.fromEntries(
            names.map((name) => [
              name,
              omitUndefined({ ...channel.parameters?.[name] }),
            ]),
          )
        : undefined;
    const serverRefs = channel.protocol === "ws" ? wsServers : httpServers;
    channelObjects[key] = omitUndefined({
      address: channel.address === "" ? null : channel.address,
      title: channel.title,
      summary: channel.summary,
      description: channel.description,
      servers:
        serverRefs.length > 0
          ? serverRefs.map((ref) => ({ ...ref }))
          : undefined,
      parameters,
      messages: channelMessages,
      bindings:
        channel.protocol === "ws" ? structuredClone(WS_BINDING) : undefined,
      ...channel.extensions,
    });
    for (const operation of channel.operations) {
      const operationKey = keyOf(operation.id, "Operation");
      const refs: Json[] = [];
      for (const id of operation.messages ?? []) {
        const messageKey = messageKeys.get(id);
        if (messageKey === undefined || !channel.messages.includes(id)) {
          ctx.report({
            code: "asyncapi-operation-message-unknown",
            severity: "error",
            message: `Operation "${operation.id}" lists "${id}", which is not a message of channel "${channel.id}"`,
            pointer: `/operations/${pointerToken(operationKey)}`,
          });
          continue;
        }
        refs.push({
          $ref: `#/channels/${key}/messages/${messageKey}`,
        });
      }
      addOperation(
        operationKey,
        omitUndefined({
          action: operation.action,
          channel: { $ref: `#/channels/${key}` },
          summary: operation.summary,
          description: operation.description,
          messages: operation.messages ? refs : undefined,
          [`${prefix}permission`]: operation.permission,
          ...operation.extensions,
        }),
        `/operations/${pointerToken(operationKey)}`,
      );
    }
  }

  for (const operation of model.operations) {
    const emits = operation.extensions[`${prefix}emits`];
    if (!Array.isArray(emits)) {
      continue;
    }
    const byChannel = new Map<string, string[]>();
    // SAFETY: Array.isArray narrowed it; each entry is checked to be a string.
    for (const event of emits as readonly unknown[]) {
      if (typeof event !== "string") {
        continue;
      }
      const target = placed.find(({ channel }) =>
        channel.messages.some((id) => {
          const message = allMessages[id];
          return (
            id === event ||
            message?.name === event ||
            message?.name?.endsWith(`.${event}`) === true
          );
        }),
      );
      const id = target?.channel.messages.find((candidate) => {
        const message = allMessages[candidate];
        return (
          candidate === event ||
          message?.name === event ||
          message?.name?.endsWith(`.${event}`) === true
        );
      });
      if (!target || id === undefined) {
        ctx.report({
          code: "asyncapi-emits-unknown",
          severity: "warning",
          message: `Operation "${operation.id}" emits "${event}", which no message describes`,
          pointer: `/operations/${pointerToken(operation.id)}`,
        });
        continue;
      }
      const list = byChannel.get(target.key) ?? [];
      list.push(messageKeys.get(id) ?? id);
      byChannel.set(target.key, list);
    }
    const many = byChannel.size > 1;
    for (const [channelKey, keys] of byChannel) {
      const operationKey = safeKey(
        many
          ? `${operation.id}Emits${pascal(channelKey)}`
          : `${operation.id}Emits`,
      );
      addOperation(
        operationKey,
        {
          action: "send",
          channel: { $ref: `#/channels/${channelKey}` },
          summary: `Events sent by ${operation.method.toUpperCase()} ${operation.path}`,
          messages: [...new Set(keys)].map((messageKey) => ({
            $ref: `#/channels/${channelKey}/messages/${messageKey}`,
          })),
          [`${prefix}operation`]: operation.id,
        },
        `/operations/${pointerToken(operationKey)}`,
      );
    }
  }

  const traits: Json = {};
  for (const [name, trait] of Object.entries(model.messageTraits ?? {})) {
    traits[safeKey(name)] = lowerTrait(trait);
  }

  const schemas = referencedSchemas(model, [
    Object.values(messages),
    Object.values(traits),
  ]);
  const { info } = model;
  const document: Json = omitUndefined({
    asyncapi: ASYNCAPI_FIELD[version],
    info: omitUndefined({
      title: info.title,
      version: info.version,
      description: info.description ?? info.summary,
      termsOfService: info.termsOfService,
      contact: info.contact ? omitUndefined({ ...info.contact }) : undefined,
      license: info.license
        ? omitUndefined({ name: info.license.name, url: info.license.url })
        : undefined,
    }),
    defaultContentType: "application/json",
    servers: Object.keys(servers).length > 0 ? servers : undefined,
    channels: channelObjects,
    operations,
    components: omitUndefined({
      schemas: Object.keys(schemas).length > 0 ? schemas : undefined,
      messages: Object.keys(messages).length > 0 ? messages : undefined,
      messageTraits: Object.keys(traits).length > 0 ? traits : undefined,
      securitySchemes:
        Object.keys(securitySchemes).length > 0 ? securitySchemes : undefined,
    }),
  });
  if (!isAsyncApiDocument(document)) {
    throw new TypeError(
      "better-supabase/asyncapi: lowering lost a required field",
    );
  }
  return document;
}

function isAsyncApiDocument(value: Json): value is Json & AnyAsyncApiDocument {
  return (
    typeof value["asyncapi"] === "string" &&
    isPlainObject(value["info"]) &&
    isPlainObject(value["channels"]) &&
    isPlainObject(value["operations"]) &&
    isPlainObject(value["components"])
  );
}

function resolve(document: unknown, ref: string): unknown {
  if (!ref.startsWith("#/")) {
    return undefined;
  }
  let node: unknown = document;
  for (const raw of ref.slice(2).split("/")) {
    const key = raw.replaceAll("~1", "/").replaceAll("~0", "~");
    if (!isPlainObject(node)) {
      return undefined;
    }
    node = node[key];
  }
  return node;
}

function refOf(value: unknown): string | undefined {
  return isPlainObject(value) && typeof value["$ref"] === "string"
    ? value["$ref"]
    : undefined;
}

function lintAsyncApi(document: AnyAsyncApiDocument): SpecDiagnostic[] {
  const diagnostics: SpecDiagnostic[] = [];
  const refs = new Set<string>();
  collectRefs(document, refs);
  for (const ref of refs) {
    if (ref.startsWith("#") && resolve(document, ref) === undefined) {
      diagnostics.push({
        code: "asyncapi-ref-unresolved",
        severity: "error",
        message: `$ref "${ref}" does not resolve inside the document`,
      });
    }
  }
  for (const [key, channel] of Object.entries(document.channels)) {
    const pointer = `/channels/${pointerToken(key)}`;
    if (!KEY.test(key)) {
      diagnostics.push({
        code: "asyncapi-key-invalid",
        severity: "error",
        message: `Channel id "${key}" has characters AsyncAPI keys do not allow`,
        pointer,
      });
    }
    const address = channel["address"];
    const names = new Set(
      typeof address === "string"
        ? [...address.matchAll(PARAM)].map((match) => match[1] ?? "")
        : [],
    );
    const parameters = isPlainObject(channel["parameters"])
      ? Object.keys(channel["parameters"])
      : [];
    for (const name of parameters) {
      if (!names.has(name)) {
        diagnostics.push({
          code: "asyncapi-parameter-unknown",
          severity: "error",
          message: `Parameter "${name}" is not in the address of channel "${key}"`,
          pointer: `${pointer}/parameters`,
        });
      }
    }
    for (const name of names) {
      if (!parameters.includes(name)) {
        diagnostics.push({
          code: "asyncapi-parameter-missing",
          severity: "error",
          message: `Address expression "{${name}}" of channel "${key}" has no parameter`,
          pointer: `${pointer}/parameters`,
        });
      }
    }
  }
  for (const [key, operation] of Object.entries(document.operations)) {
    const pointer = `/operations/${pointerToken(key)}`;
    const channelRef = refOf(operation["channel"]);
    if (!channelRef?.startsWith("#/channels/")) {
      diagnostics.push({
        code: "asyncapi-operation-channel-unknown",
        severity: "error",
        message: `Operation "${key}" does not reference a root channel`,
        pointer: `${pointer}/channel`,
      });
      continue;
    }
    const list: unknown[] = Array.isArray(operation["messages"])
      ? operation["messages"]
      : [];
    for (const entry of list) {
      const ref = refOf(entry);
      if (!ref?.startsWith(`${channelRef}/messages/`)) {
        diagnostics.push({
          code: "asyncapi-operation-message-unknown",
          severity: "error",
          message: `Operation "${key}" lists a message outside its channel`,
          pointer: `${pointer}/messages`,
        });
      }
    }
  }
  return diagnostics;
}

/**
 * AsyncAPI as a `DocumentFormat`, for the events the API model describes:
 * Realtime table change signals and broadcast topics on the Supabase
 * Realtime websocket (`ws` bindings), CloudEvents (headers as the
 * `cloudEvent` message trait), outgoing webhooks over HTTP and the events
 * HTTP operations emit. 3.0 is the default; 3.1 only adds `ros2` bindings,
 * so the two documents differ in the `asyncapi` field.
 */
export const asyncapiFormat: DocumentFormat<
  "asyncapi",
  AsyncApiVersion,
  AnyAsyncApiDocument,
  AsyncApiDocuments
> = defineDocumentFormat<
  "asyncapi",
  AsyncApiVersion,
  AnyAsyncApiDocument,
  AsyncApiDocuments
>({
  id: "asyncapi",
  versions: {
    "3.0": { pin: SPEC_PINS.asyncapi30, status: "stable" },
    "3.1": { pin: SPEC_PINS.asyncapi31, status: "stable" },
  },
  defaultVersion: "3.0",
  lower: lowerAsyncApi,
  lint: lintAsyncApi,
  fileName: () => ASYNCAPI_FILE_NAME,
});
