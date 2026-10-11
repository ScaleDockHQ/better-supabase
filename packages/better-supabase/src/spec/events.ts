import type { StandardSchemaV1 } from "@standard-schema/spec";

import type { BlockEventMap } from "../core/block-events.ts";
import type { MutationIntent } from "../core/plugin.ts";
import type { CloudEventOptions } from "../events/cloud-event.ts";
import type { SchemaMeta } from "../schema/types.ts";
import type { SpecDiagnostic } from "./format.ts";
import type {
  JsonSchema,
  ModelChannel,
  ModelChannelOperation,
  ModelMessage,
  ModelMessageTrait,
  ModelOperation,
  ModelWorkflow,
} from "./model.ts";
import type { ApiOptions } from "./options.ts";

import { isPlainObject } from "../core/clone.ts";
import { dataschemaOf } from "../events/cloud-event.ts";
import { ROW_EVENT_TYPES } from "../events/index.ts";
import {
  convertStandard,
  pascal,
  schemaRef,
  type StandardLike,
  tableSchemas,
} from "./schemas.ts";

/** A schema for a block event's data, checked against `BlockEventMap`. */
export type BlockEventSchema<T> = StandardSchemaV1<unknown, T>;

/**
 * Data schemas for block events, by event type. `true` documents the event
 * with an open payload. A block can export its own map of this type.
 */
export type BlockEventSchemas = {
  readonly [K in keyof BlockEventMap]?:
    | true
    | BlockEventSchema<BlockEventMap[K]>;
};

/**
 * A Realtime broadcast topic. A `defineTopic()` result fits; add `events`
 * to document the payloads and `send` when clients broadcast too.
 */
export interface TopicInput<Ref = string> {
  readonly template: string;
  readonly name?: string;
  readonly private?: boolean;
  readonly presence?: boolean;
  /** Payload schema per broadcast event; `true` for an open payload. */
  readonly events?: Readonly<Record<string, StandardLike | true>>;
  /** Clients may broadcast on the topic, not only receive. */
  readonly send?: boolean;
  readonly permission?: Ref;
  readonly summary?: string;
  readonly description?: string;
}

/** CloudEvents the app sends (`forwardMutations`, `forwardBlockEvents`). */
export interface CloudEventsInput extends Pick<
  CloudEventOptions,
  "source" | "typePrefix" | "dataschema"
> {
  /** The sink's address. Defaults to `events`. */
  readonly address?: string;
  /** Row events for these tables (`true` for every table). Defaults to none. */
  readonly rows?: boolean | readonly string[];
  /** Which row events. Defaults to insert, update and delete. */
  readonly intents?: readonly MutationIntent[];
  /** Block events and their data schemas. */
  readonly blocks?: BlockEventSchemas;
}

/** Channels and messages for AsyncAPI, built from the schema and the app. */
export interface EventsOptions<Ref = string> {
  /**
   * Table change signals (`bs:t:<schema>.<table>`) for the tables in
   * `realtime.tables`: `true` for all, or app keys. Defaults to `true`.
   */
  readonly tables?: boolean | readonly string[];
  /** Realtime broadcast topics, by key. */
  readonly topics?: Readonly<Record<string, TopicInput<Ref>>>;
  readonly cloudEvents?: CloudEventsInput;
}

export interface BuiltEvents {
  readonly channels: readonly ModelChannel[];
  readonly messages: Readonly<Record<string, ModelMessage>>;
  readonly messageTraits: Readonly<Record<string, ModelMessageTrait>>;
}

export interface EventsContext<Ref> {
  readonly meta: SchemaMeta;
  readonly json: Readonly<Record<string, unknown>>;
  readonly prefix: string;
  /** Served tables by key, with their component names. */
  readonly served: ReadonlyMap<
    string,
    { readonly components: { readonly Row?: string } }
  >;
  keyOf(ref: Ref, where: string): string | undefined;
  report(diagnostic: SpecDiagnostic): void;
}

const OPEN: JsonSchema = { type: "object" };
const DEFAULT_INTENTS: readonly MutationIntent[] = [
  "insert",
  "update",
  "delete",
];

/** An id safe for AsyncAPI channel, operation and component keys. */
export function safeKey(value: string): string {
  return value.replaceAll(/[^A-Za-z0-9_-]/g, "_");
}

const keyPart = (value: string): string => safeKey(pascal(value));

/** The CloudEvents attributes in HTTP binary mode (`ce-*` headers). */
export const CLOUD_EVENT_TRAIT: ModelMessageTrait = {
  description: "CloudEvents 1.0 attributes in HTTP binary mode.",
  contentType: "application/json",
  headers: {
    type: "object",
    properties: {
      "ce-specversion": { type: "string", const: "1.0" },
      "ce-id": { type: "string" },
      "ce-source": { type: "string", format: "uri-reference" },
      "ce-type": { type: "string" },
      "ce-subject": { type: "string" },
      "ce-time": { type: "string", format: "date-time" },
      "ce-dataschema": { type: "string", format: "uri" },
      "ce-partitionkey": { type: "string" },
    },
  },
};

function cloudEventHeaders(type: string, dataschema?: string): JsonSchema {
  return {
    type: "object",
    required: ["ce-specversion", "ce-id", "ce-source", "ce-type"],
    properties: {
      "ce-type": { type: "string", const: type },
      ...(dataschema
        ? { "ce-dataschema": { type: "string", const: dataschema } }
        : {}),
    },
  };
}

function convert<Ref>(
  schema: StandardLike | true,
  where: string,
  ctx: EventsContext<Ref>,
): JsonSchema {
  if (schema === true) return OPEN;
  const converted = convertStandard(schema, "output");
  if (converted) return converted.schema;
  ctx.report({
    code: "asyncapi-schema-opaque",
    severity: "warning",
    message: `${where}: the schema does not implement Standard JSON Schema; the payload is left open`,
  });
  return OPEN;
}

function tableChannels<Ref>(
  ctx: EventsContext<Ref>,
  selection: boolean | readonly string[],
  channels: ModelChannel[],
  messages: Record<string, ModelMessage>,
): void {
  if (selection === false) return;
  const realtime = ctx.meta.realtime ?? {};
  const keys = selection === true ? Object.keys(realtime) : selection;
  for (const key of keys) {
    const table = ctx.meta.tables[key];
    const config = realtime[key];
    if (!table || !config) {
      ctx.report({
        code: "asyncapi-table-unknown",
        severity: "error",
        message: `events.tables names "${key}", which is not in realtime.tables`,
      });
      continue;
    }
    const id = `table${keyPart(key)}`;
    const base = `bs:t:${table.schema}.${table.name}`;
    const address = config.user
      ? `${base}:u:{userId}`
      : config.tenant
        ? `${base}:{tenant}`
        : base;
    const messageId = `${id}Change`;
    messages[messageId] = {
      id: messageId,
      name: "change",
      title: `${key} changed`,
      summary: `A row of ${table.schema}.${table.name} was inserted, updated or deleted. Clients refetch through row-level security.`,
      contentType: "application/json",
      payload: {
        type: "object",
        required: ["schema", "table", "operation"],
        properties: {
          schema: { type: "string", const: table.schema },
          table: { type: "string", const: table.name },
          operation: { type: "string", enum: ["INSERT", "UPDATE", "DELETE"] },
        },
      },
      extensions: { [`${ctx.prefix}event`]: "change" },
    };
    channels.push({
      id,
      address,
      title: `${key} changes`,
      protocol: "ws",
      ...(config.user
        ? {
            parameters: {
              userId: { description: "The signed-in user's id." },
            },
          }
        : config.tenant
          ? {
              parameters: {
                tenant: {
                  description: `The row's \`${config.tenant}\` value.`,
                },
              },
            }
          : {}),
      messages: [messageId],
      operations: [
        {
          id: `receive${keyPart(key)}Changes`,
          action: "receive",
          summary: `Change signals for ${key}`,
        },
      ],
      extensions: { [`${ctx.prefix}table`]: `${table.schema}.${table.name}` },
    });
  }
}

function topicChannels<Ref>(
  ctx: EventsContext<Ref>,
  topics: Readonly<Record<string, TopicInput<Ref>>>,
  channels: ModelChannel[],
  messages: Record<string, ModelMessage>,
): void {
  for (const [key, topic] of Object.entries(topics)) {
    const id = `topic${keyPart(key)}`;
    const ids: string[] = [];
    const events = Object.entries(topic.events ?? {});
    if (events.length === 0) {
      ctx.report({
        code: "asyncapi-topic-open",
        severity: "info",
        message: `Topic "${key}" lists no events; it is documented with one open message`,
      });
      events.push(["*", true]);
    }
    for (const [event, schema] of events) {
      const messageId = `${id}${event === "*" ? "Any" : keyPart(event)}`;
      ids.push(messageId);
      messages[messageId] = {
        id: messageId,
        ...(event === "*" ? {} : { name: event }),
        title: event === "*" ? `${key} broadcast` : `${key} ${event}`,
        contentType: "application/json",
        payload: convert(schema, `topics.${key}.events.${event}`, ctx),
        extensions: { [`${ctx.prefix}event`]: event },
      };
    }
    if (topic.presence) {
      const messageId = `${id}Presence`;
      ids.push(messageId);
      messages[messageId] = {
        id: messageId,
        name: "presence",
        title: `${key} presence`,
        contentType: "application/json",
        payload: OPEN,
        extensions: { [`${ctx.prefix}event`]: "presence" },
      };
    }
    const permission =
      topic.permission === undefined
        ? undefined
        : ctx.keyOf(topic.permission, `topics.${key}`);
    const extra = permission === undefined ? {} : { permission };
    const operations: ModelChannelOperation[] = [
      {
        id: `receive${keyPart(key)}`,
        action: "receive",
        ...(topic.summary ? { summary: topic.summary } : {}),
        ...extra,
      },
    ];
    if (topic.send || topic.presence)
      operations.push({
        id: `send${keyPart(key)}`,
        action: "send",
        ...extra,
      });
    const params = [...topic.template.matchAll(/\{([^}]+)\}/g)].map(
      (match) => match[1] ?? "",
    );
    channels.push({
      id,
      address: topic.template,
      ...(topic.summary ? { summary: topic.summary } : {}),
      ...(topic.description ? { description: topic.description } : {}),
      title: topic.name ?? key,
      ...(params.length > 0
        ? { parameters: Object.fromEntries(params.map((name) => [name, {}])) }
        : {}),
      protocol: "ws",
      messages: ids,
      operations,
      extensions: { [`${ctx.prefix}private`]: topic.private ?? true },
    });
  }
}

function withActor(schema: JsonSchema): JsonSchema {
  const properties = schema["properties"];
  if (!isPlainObject(properties) || "actorId" in properties) return schema;
  return {
    ...schema,
    properties: {
      ...properties,
      actorId: { type: "string", description: "Who caused the event." },
    },
  };
}

function cloudEventChannel<Ref>(
  ctx: EventsContext<Ref>,
  input: CloudEventsInput,
  channels: ModelChannel[],
  messages: Record<string, ModelMessage>,
): boolean {
  const ids: string[] = [];
  const add = (
    messageId: string,
    type: string,
    title: string,
    payload: JsonSchema,
    table?: string,
  ): void => {
    const { dataschema } = dataschemaOf(input, {
      type,
      ...(table ? { table } : {}),
    });
    ids.push(messageId);
    messages[messageId] = {
      id: messageId,
      name: type,
      title,
      contentType: "application/json",
      headers: cloudEventHeaders(type, dataschema),
      payload,
      traits: ["cloudEvent"],
      extensions: {
        [`${ctx.prefix}cloudevent-type`]: type,
        ...(dataschema ? { [`${ctx.prefix}dataschema`]: dataschema } : {}),
      },
    };
  };

  const rows = input.rows ?? false;
  const rowTables =
    rows === true ? Object.keys(ctx.meta.tables) : rows === false ? [] : rows;
  const defs = rowTables.length > 0 ? tableSchemas(ctx.meta, ctx.json) : {};
  for (const table of rowTables) {
    if (!ctx.meta.tables[table]) {
      ctx.report({
        code: "asyncapi-table-unknown",
        severity: "error",
        message: `events.cloudEvents.rows names an unknown table "${table}"`,
      });
      continue;
    }
    const component = ctx.served.get(table)?.components.Row;
    const row = component
      ? schemaRef(component)
      : (defs[`${table}Row`] ?? OPEN);
    for (const intent of input.intents ?? DEFAULT_INTENTS) {
      const last = ROW_EVENT_TYPES[intent].split(".").at(-1) ?? intent;
      const type = input.typePrefix
        ? `${input.typePrefix}.row.${last}`
        : ROW_EVENT_TYPES[intent];
      add(
        `row${keyPart(table)}${keyPart(last)}`,
        type,
        `${table} ${last}`,
        {
          type: "object",
          required: ["table", "row"],
          properties: {
            table: { type: "string", const: table },
            row,
            actorId: { type: "string" },
          },
        },
        table,
      );
    }
  }

  for (const [event, schema] of Object.entries(input.blocks ?? {})) {
    const type = `${input.typePrefix ?? "dev.better-supabase"}.${event}`;
    add(
      `block${keyPart(event)}`,
      type,
      event,
      withActor(convert(schema, `events.cloudEvents.blocks.${event}`, ctx)),
    );
  }

  if (ids.length === 0) return false;
  channels.push({
    id: "cloudEvents",
    address: input.address ?? "events",
    title: "CloudEvents",
    description: `CloudEvents from \`${input.source}\`, sent to the event sink.`,
    protocol: "http",
    messages: ids,
    operations: [{ id: "sendCloudEvents", action: "send" }],
  });
  return true;
}

/** What `buildApiModel` takes from the event options and the app's own lists. */
export interface EventParts {
  readonly channels: readonly ModelChannel[];
  readonly messages: Readonly<Record<string, ModelMessage>>;
  readonly messageTraits?: Readonly<Record<string, ModelMessageTrait>>;
  readonly workflows: readonly ModelWorkflow[];
}

/**
 * The built channels and messages first, then the app's own (which win on
 * an id), and the workflows with every `WorkflowSource` run on `operations`.
 */
export function eventParts<Ref>(
  options: Pick<
    ApiOptions<Ref>,
    "events" | "channels" | "messages" | "workflows"
  >,
  ctx: EventsContext<Ref>,
  operations: readonly ModelOperation[],
): EventParts {
  const built = buildEvents(options.events, ctx);
  return {
    channels: [...built.channels, ...(options.channels ?? [])],
    messages: { ...built.messages, ...options.messages },
    ...(Object.keys(built.messageTraits).length > 0
      ? { messageTraits: built.messageTraits }
      : {}),
    workflows: (options.workflows ?? []).flatMap((workflow) =>
      typeof workflow === "function" ? workflow(operations) : [workflow],
    ),
  };
}

/** Channels and messages from the realtime tables, topics and CloudEvents. */
export function buildEvents<Ref>(
  events: EventsOptions<Ref> | undefined,
  ctx: EventsContext<Ref>,
): BuiltEvents {
  const channels: ModelChannel[] = [];
  const messages: Record<string, ModelMessage> = {};
  const messageTraits: Record<string, ModelMessageTrait> = {};
  if (!events) return { channels, messages, messageTraits };
  tableChannels(ctx, events.tables ?? true, channels, messages);
  topicChannels(ctx, events.topics ?? {}, channels, messages);
  if (
    events.cloudEvents &&
    cloudEventChannel(ctx, events.cloudEvents, channels, messages)
  )
    messageTraits["cloudEvent"] = CLOUD_EVENT_TRAIT;
  return { channels, messages, messageTraits };
}
