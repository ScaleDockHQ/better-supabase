import type { DbBlockSource } from "../core/db-blocks.ts";
import type { AnyPlugin, PluginDescribeApi } from "../core/plugin.ts";
import type { SchemaMeta } from "../schema/types.ts";
import type { BuildContext, ServedTable } from "./build-resource.ts";
import type {
  ApiModel,
  HttpMethod,
  JsonSchema,
  ModelMessage,
  ModelParameter,
  ModelResponse,
  OperationSource,
} from "./model.ts";
import type {
  ApiOptions,
  ApiSource,
  BuiltModel,
  ResourceInput,
} from "./options.ts";

import { isPlainObject } from "../core/clone.ts";
import { buildBlocks, READ_VERBS } from "./build-blocks.ts";
import {
  buildResource,
  createBuildContext,
  isMethod,
  jsonContent,
  jsonResponse,
} from "./build-resource.ts";
import { buildDataApi, withDataApiSchemes } from "./data-api.ts";
import { eventParts } from "./events.ts";
import { mergeJson, pointerToken } from "./merge.ts";
import { OAUTH_SCHEME, resolveSecurity } from "./presets.ts";
import { pascal } from "./schemas.ts";

type Json = Record<string, unknown>;

const READ_METHODS: ReadonlySet<HttpMethod> = new Set<HttpMethod>([
  "get",
  "head",
  "options",
  "query",
]);

const modelCache = new WeakMap<
  SchemaMeta,
  WeakMap<object, WeakMap<object, WeakMap<object, BuiltModel>>>
>();

const NO_PLUGINS: readonly AnyPlugin[] = [];
const NO_BLOCKS: object = {};

/** One `WeakMap` level of the model cache, created on first use. */
function level<K extends object, V>(
  map: WeakMap<K, V>,
  key: K,
  empty: () => V,
): V {
  let value = map.get(key);

  if (value === undefined) {
    value = empty();
    map.set(key, value);
  }

  return value;
}

/**
 * Builds the version-neutral API model once per metadata, plugin list, block
 * set and options object. Formats lower it to each version; `defineApi` wraps
 * it.
 */
export function buildApiModel<Ref = string>(
  source: ApiSource,
  options: ApiOptions<Ref>,
): BuiltModel {
  const plugins = source.plugins ?? NO_PLUGINS;
  const blocks = source.options?.blocks;

  const byOptions = level(
    level(
      level(modelCache, source.meta, () => new WeakMap()),
      plugins,
      () => new WeakMap(),
    ),
    blocks ?? NO_BLOCKS,
    () => new WeakMap<object, BuiltModel>(),
  );

  return level(byOptions, options, () =>
    build(source.meta, plugins, blocks, options),
  );
}

/** The tables `options.resources` publishes: every table unless it says so. */
export function publishedResources<Ref>(
  meta: SchemaMeta,
  options: ApiOptions<Ref>,
): Readonly<Record<string, ResourceInput<Ref>>> {
  if (options.resources === false) {
    return {};
  }

  return (
    options.resources ??
    Object.fromEntries(Object.keys(meta.tables).map((key) => [key, true]))
  );
}

function build<Ref>(
  meta: SchemaMeta,
  plugins: readonly AnyPlugin[],
  blocks: DbBlockSource | undefined,
  options: ApiOptions<Ref>,
): BuiltModel {
  const ctx = createBuildContext(meta, options);

  for (const [key, input] of Object.entries(
    publishedResources(meta, options),
  )) {
    buildResource(ctx, key, input);
  }

  buildBlocks(ctx, blocks, options.blocks);

  for (const [index, route] of (options.routes ?? []).entries()) {
    buildRoute(ctx, route, index);
  }

  if (options.dataApi) {
    buildDataApi(ctx, options.dataApi);
  }

  const security = withDataApiSchemes(
    buildSecurity(ctx),
    ctx.operations,
    options.supabaseUrl,
  );

  applyPlugins(ctx, plugins);
  validateOperations(ctx);

  return finalizeModel(ctx, security);
}

type Route<Ref> = NonNullable<ApiOptions<Ref>["routes"]>[number];

function buildRoute<Ref>(
  ctx: BuildContext<Ref>,
  route: Route<Ref>,
  index: number,
): void {
  const {
    options,
    base,
    globalErrors,
    operations,
    prefix,
    addTag,
    keyOf,
    schemaOf,
    objectParameters,
    usedErrors,
  } = ctx;

  const method = route.method.toLowerCase();

  if (!isMethod(method)) {
    throw new TypeError(
      `better-supabase/spec: routes[${index}] has an unknown method "${route.method}"`,
    );
  }

  const path = `${base}${route.path}`;

  const segments = route.path
    .split("/")
    .filter(Boolean)
    .map((segment) => segment.replaceAll(/[{}]/g, ""));

  const defaultId = `${method}${segments.map(pascal).join("")}`;
  const source: OperationSource = { kind: "route" };

  const id =
    route.operationId ??
    options.operationId?.({ source, method, path, defaultId }) ??
    defaultId;

  const declared = route.params
    ? objectParameters(route.params, "path", `${id} params`)
    : [];

  const parameters: ModelParameter[] = [];

  for (const [, param] of path.matchAll(/\{(\w+)\}/g)) {
    parameters.push(
      declared.find((entry) => entry.name === param) ?? {
        name: param!,
        in: "path",
        required: true,
        schema: { type: "string" },
      },
    );
  }

  if (route.query) {
    parameters.push(...objectParameters(route.query, "query", `${id} query`));
  }

  const permission =
    route.permission === undefined
      ? undefined
      : keyOf(route.permission, `routes[${index}]`);

  const secured = route.security === undefined || route.security.length > 0;

  const status = String(
    route.status ?? (route.output || route.stream ? 200 : 204),
  );

  const success: ModelResponse = route.stream
    ? {
        description: route.summary ?? "A stream of events.",
        content: {
          [route.stream.contentType ?? "text/event-stream"]: {
            itemSchema: schemaOf(route.stream.item, "output", "item", id),
          },
        },
      }
    : route.output
      ? jsonResponse(
          schemaOf(route.output, "output", "output", id),
          route.summary ?? "OK.",
        )
      : { description: route.summary ?? "Done." };

  const routeTags = [...(route.tags ?? [])];

  for (const tag of routeTags) {
    addTag(tag);
  }

  operations.push({
    id,
    method,
    path,
    tags: routeTags,
    source,
    ...(route.summary ? { summary: route.summary } : {}),
    ...(route.description ? { description: route.description } : {}),
    ...(route.deprecated ? { deprecated: true } : {}),
    parameters,
    ...(route.input
      ? {
          requestBody: {
            required: true,
            content: jsonContent(schemaOf(route.input, "input", "input", id)),
          },
        }
      : {}),
    responses: {
      [status]: success,
      ...usedErrors(
        route.errors ?? globalErrors,
        [
          ...(route.input || route.query ? [400, 422] : []),
          ...(secured ? [401, 403] : []),
        ],
        permission !== undefined,
      ),
    },
    ...(route.security ? { security: route.security } : {}),
    ...(permission === undefined ? {} : { permission }),
    extensions:
      permission === undefined ? {} : { [`${prefix}permission`]: permission },
    ...(route.extend ? { extend: route.extend } : {}),
  });
}

function buildSecurity<Ref>(ctx: BuildContext<Ref>) {
  const { options, operations } = ctx;
  const oauthScopes: Record<string, string> = {};

  if (options.permissionScopes === "keys") {
    for (const operation of operations) {
      if (operation.permission) {
        oauthScopes[operation.permission] =
          `Permission ${operation.permission}.`;
      }
    }
  }

  const security = resolveSecurity(
    options.security ?? ["bearer"],
    options.supabaseUrl,
    oauthScopes,
  );

  if (options.permissionScopes === "keys") {
    for (const operation of operations) {
      const key = operation.permission;

      if (!key || operation.security?.length === 0) {
        continue;
      }

      operation.security = (operation.security ?? security.requirements).map(
        (requirement) => {
          const scopes = requirement[OAUTH_SCHEME];

          return scopes
            ? { ...requirement, [OAUTH_SCHEME]: [...scopes, key] }
            : requirement;
        },
      );
    }
  }

  return security;
}

function applyPlugins<Ref>(
  ctx: BuildContext<Ref>,
  plugins: readonly AnyPlugin[],
): void {
  const { meta, prefix, served, schemas, report } = ctx;
  const describe = describeApi(meta, prefix, served, schemas);

  for (const plugin of plugins) {
    if (!plugin.describe) {
      continue;
    }

    try {
      plugin.describe(describe);
    } catch (error) {
      report({
        code: "plugin-describe-failed",
        severity: "warning",
        message: `The ${plugin.name} plugin's describe() threw: ${error instanceof Error ? error.message : String(error)}`,
      });
    }
  }
}

/** Reports writes without a permission and duplicate operation ids. */
function validateOperations<Ref>(ctx: BuildContext<Ref>): void {
  const { options, operations, report } = ctx;

  if (options.requirePermissions) {
    for (const operation of operations) {
      if (operation.source.kind === "data-api") {
        continue;
      }

      const writes =
        operation.source.kind === "resource"
          ? operation.source.operation !== "list" &&
            operation.source.operation !== "get"
          : operation.source.kind === "verb"
            ? !READ_VERBS.has(operation.source.verb)
            : !READ_METHODS.has(operation.method);

      if (writes && operation.permission === undefined) {
        report({
          code: "permission-missing",
          severity: "error",
          message: `${operation.id} writes but declares no permission`,
          pointer: `/operations/${pointerToken(operation.id)}`,
        });
      }
    }
  }

  const seen = new Set<string>();

  for (const operation of operations) {
    if (seen.has(operation.id)) {
      report({
        code: "operation-id-duplicate",
        severity: "error",
        message: `Two operations have the id "${operation.id}"`,
        pointer: `/operations/${pointerToken(operation.id)}`,
      });
    }

    seen.add(operation.id);
  }
}

function finalizeModel<Ref>(
  ctx: BuildContext<Ref>,
  security: ReturnType<typeof buildSecurity<Ref>>,
): BuiltModel {
  const {
    meta,
    options,
    prefix,
    served,
    keyOf,
    report,
    schemas,
    operations,
    tags,
    responses,
    diagnostics,
  } = ctx;

  const { enrich } = options;
  const finalSchemas: Record<string, JsonSchema> = {};

  for (const [name, schema] of Object.entries(schemas)) {
    finalSchemas[name] = enrich?.schema?.(schema, { name }) ?? schema;
  }

  const finalOperations = operations.map(
    (operation) => enrich?.operation?.(operation) ?? operation,
  );

  const json = options.json ?? {};
  const events = { meta, json, prefix, served, keyOf, report };

  const { messageTraits, ...parts } = eventParts(
    options,
    events,
    finalOperations,
  );

  const messages: Record<string, ModelMessage> = {};

  for (const [id, message] of Object.entries(parts.messages)) {
    messages[id] = enrich?.message?.(message, { id }) ?? message;
  }

  const model: ApiModel = {
    info: options.info,
    ...(options.self ? { self: options.self } : {}),
    servers: options.servers ?? [],
    tags,
    operations: finalOperations,
    schemas: finalSchemas,
    responses,
    securitySchemes: security.schemes,
    security: security.requirements,
    ...(options.securityProfileRequirements
      ? { securityProfileRequirements: options.securityProfileRequirements }
      : {}),
    channels: parts.channels.map(
      (channel) => enrich?.channel?.(channel) ?? channel,
    ),
    messages,
    ...(messageTraits ? { messageTraits } : {}),
    webhooks: options.webhooks ?? [],
    workflows: parts.workflows.map(
      (workflow) => enrich?.workflow?.(workflow) ?? workflow,
    ),
    fragments: options.fragments ?? [],
    ...(options.realtimeUrl ? { realtimeUrl: options.realtimeUrl } : {}),
    extensionPrefix: prefix,
  };

  return { model, diagnostics };
}

/** An operation's name within its resource: the operation, verb or action. */
function operationName(operation: ServedTable["operations"][number]): string {
  switch (operation.source.kind) {
    case "action": {
      return operation.source.action;
    }

    case "resource": {
      return operation.source.operation;
    }

    case "verb": {
      return operation.source.verb;
    }

    case "data-api":
    case "route":
    case "fragment": {
      return operation.id;
    }

    default: {
      const unknown: never = operation.source;
      throw new TypeError(`Unknown operation source ${String(unknown)}`);
    }
  }
}

function describeApi(
  meta: SchemaMeta,
  prefix: string,
  served: ReadonlyMap<string, ServedTable>,
  schemas: Record<string, Json>,
): PluginDescribeApi {
  const columnSchemas = (table: string, column: string) => {
    const entry = served.get(table);

    if (!entry) {
      return [];
    }

    return (["Row", "Insert", "Update"] as const).flatMap((variant) => {
      const name = entry.components[variant];
      const schema = name ? schemas[name] : undefined;
      const properties = schema?.["properties"];

      if (!schema || !isPlainObject(properties)) {
        return [];
      }

      const property = properties[column];

      if (!isPlainObject(property)) {
        return [];
      }

      return [{ variant, schema, properties, property }];
    });
  };

  const replace = (
    schema: Json,
    properties: Readonly<Record<string, unknown>>,
    column: string,
    property: Json,
  ): void => {
    schema["properties"] = { ...properties, [column]: property };
  };

  return {
    schema: meta,
    extensionPrefix: prefix,
    resources: [...served.values()].map((entry) => ({
      table: entry.table,
      operations: entry.operations.map(operationName),
    })),
    addParameter(table, parameter, names): void {
      for (const operation of served.get(table)?.operations ?? []) {
        const name = operationName(operation);

        if (names && !names.includes(name)) {
          continue;
        }

        if (
          operation.parameters.some(
            (entry) =>
              entry.name === parameter.name && entry.in === parameter.in,
          )
        ) {
          continue;
        }

        operation.parameters.push({ ...parameter });
      }
    },
    markReadOnly(table, column, description): void {
      for (const { variant, schema, properties, property } of columnSchemas(
        table,
        column,
      )) {
        replace(schema, properties, column, {
          ...property,
          readOnly: true,
          ...(description && property["description"] === undefined
            ? { description }
            : {}),
        });
        const required = schema["required"];

        if (variant !== "Row" && Array.isArray(required)) {
          schema["required"] = required.filter((name) => name !== column);
        }
      }
    },
    describeColumn(table, column, patch): void {
      for (const { schema, properties, property } of columnSchemas(
        table,
        column,
      )) {
        replace(schema, properties, column, mergeJson<Json>(property, patch));
      }
    },
  };
}
