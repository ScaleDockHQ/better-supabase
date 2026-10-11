import type { AnyPlugin, PluginDescribeApi } from "../core/plugin.ts";
import type { SchemaMeta, TableMeta } from "../schema/types.ts";
import type { SpecDiagnostic } from "./format.ts";
import type {
  ApiModel,
  HttpMethod,
  JsonObject,
  JsonSchema,
  ModelBody,
  ModelMessage,
  ModelParameter,
  ModelResponse,
  ModelResponseOrRef,
  ModelTag,
  OperationSource,
  ResourceOperation,
  SecurityRequirement,
} from "./model.ts";
import type {
  ApiOptions,
  ApiSource,
  BuiltModel,
  ResourceInput,
} from "./options.ts";
import type { ErrorResponse, ResourcePlan } from "./resource.ts";

import { isPlainObject } from "../core/clone.ts";
import { mergeJson, pointerToken } from "./merge.ts";
import {
  DEFAULT_ERRORS,
  errorResponse,
  OAUTH_SCHEME,
  PERMISSION_DENIED,
  permissionDeniedResponse,
  PROBLEM_SCHEMA,
  resolveSecurity,
} from "./presets.ts";
import { planResource } from "./resource.ts";
import {
  convertStandard,
  pascal,
  schemaRef,
  type StandardLike,
  tableSchemas,
} from "./schemas.ts";

type Json = Record<string, unknown>;

interface DraftOperation {
  id: string;
  method: HttpMethod;
  path: string;
  summary?: string;
  description?: string;
  tags: string[];
  deprecated?: boolean;
  parameters: ModelParameter[];
  requestBody?: ModelBody;
  responses: Record<string, ModelResponseOrRef>;
  security?: readonly SecurityRequirement[];
  permission?: string;
  source: OperationSource;
  extensions: Json;
  extend?: JsonObject;
}

interface ServedTable {
  readonly table: TableMeta;
  readonly components: Partial<Record<"Row" | "Insert" | "Update", string>>;
  readonly operations: DraftOperation[];
}

const METHODS: ReadonlySet<string> = new Set<HttpMethod>([
  "get",
  "put",
  "post",
  "patch",
  "delete",
  "head",
  "options",
  "trace",
  "query",
]);

function isMethod(value: string): value is HttpMethod {
  return METHODS.has(value);
}

const READ_METHODS: ReadonlySet<HttpMethod> = new Set<HttpMethod>([
  "get",
  "head",
  "options",
  "query",
]);

/** The error statuses each operation can answer with. */
const OPERATION_STATUSES: Readonly<
  Record<ResourceOperation, readonly number[]>
> = {
  list: [400, 401, 403],
  create: [400, 401, 403, 409, 422],
  get: [401, 403, 404],
  update: [400, 401, 403, 404, 409, 422],
  delete: [401, 403, 404, 409],
};

/** Statuses an operation only documents when it can answer with them; other errors apply everywhere. */
const SCOPED_STATUSES: ReadonlySet<number> = new Set([
  400, 401, 403, 404, 409, 422,
]);

const JSON_TYPE = "application/json";

function pageParameters(
  cursor: boolean,
  maxPageSize: number,
): ModelParameter[] {
  return [
    cursor
      ? {
          name: "after",
          in: "query",
          required: false,
          description:
            "`nextCursor` of the previous page. Leave it out for the first page.",
          schema: { type: "string" },
        }
      : {
          name: "page",
          in: "query",
          required: false,
          description: "1-based page number.",
          schema: { type: "integer", minimum: 1, default: 1 },
        },
    {
      name: "size",
      in: "query",
      required: false,
      description: "Page size.",
      schema: {
        type: "integer",
        minimum: 1,
        maximum: maxPageSize,
        default: 50,
      },
    },
  ];
}

function pageSchema(row: JsonSchema, cursor: boolean): Json {
  const items = { type: "array", items: row };
  return cursor
    ? {
        type: "object",
        required: ["items", "nextCursor", "hasMore"],
        properties: {
          items,
          nextCursor: { type: ["string", "null"] },
          hasMore: { type: "boolean" },
        },
      }
    : {
        type: "object",
        required: ["items", "page"],
        properties: {
          items,
          page: {
            type: "object",
            required: ["number", "size", "total", "pages", "hasMore"],
            properties: {
              number: { type: "integer" },
              size: { type: "integer" },
              total: { type: ["integer", "null"] },
              pages: { type: ["integer", "null"] },
              hasMore: { type: "boolean" },
            },
          },
        },
      };
}

function isParameter(value: unknown): value is ModelParameter {
  return (
    isPlainObject(value) &&
    typeof value["name"] === "string" &&
    typeof value["in"] === "string" &&
    isPlainObject(value["schema"])
  );
}

function isPlanCarrier<Ref>(
  input: ResourceInput<Ref>,
): input is { readonly plan: ResourcePlan<Ref> } {
  return typeof input === "object" && "plan" in input;
}

/** `description` and `deprecated` from comments, read structurally so older metadata still works. */
function docsOf(value: object | undefined): {
  readonly description?: string;
  readonly deprecated?: true;
} {
  if (!value) return {};
  const description = "description" in value ? value.description : undefined;
  const deprecated = "deprecated" in value ? value.deprecated : undefined;
  return {
    ...(typeof description === "string" && description !== ""
      ? { description }
      : {}),
    ...(deprecated === true ? { deprecated: true } : {}),
  };
}

function jsonContent(schema: JsonSchema): ModelBody["content"] {
  return { [JSON_TYPE]: { schema } };
}

function jsonResponse(schema: JsonSchema, description: string): ModelResponse {
  return { description, content: jsonContent(schema) };
}

function mutableProperties(schema: Json): Record<string, Json> | undefined {
  const properties = schema["properties"];
  if (!isPlainObject(properties)) return undefined;
  const copy: Record<string, Json> = {};
  for (const [key, value] of Object.entries(properties))
    if (isPlainObject(value)) copy[key] = { ...value };
  schema["properties"] = copy;
  return copy;
}

const modelCache = new WeakMap<
  SchemaMeta,
  WeakMap<object, WeakMap<object, BuiltModel>>
>();
const NO_PLUGINS: readonly AnyPlugin[] = [];

/**
 * Builds the version-neutral API model once per metadata, plugin list and
 * options object. Formats lower it to each version; `defineApi` wraps it.
 */
export function buildApiModel<Ref = string>(
  source: ApiSource,
  options: ApiOptions<Ref>,
): BuiltModel {
  const plugins = source.plugins ?? NO_PLUGINS;
  let byPlugins = modelCache.get(source.meta);
  if (!byPlugins) {
    byPlugins = new WeakMap();
    modelCache.set(source.meta, byPlugins);
  }
  let byOptions = byPlugins.get(plugins);
  if (!byOptions) {
    byOptions = new WeakMap();
    byPlugins.set(plugins, byOptions);
  }
  let built = byOptions.get(options);
  if (!built) {
    built = build(source.meta, plugins, options);
    byOptions.set(options, built);
  }
  return built;
}

function build<Ref>(
  meta: SchemaMeta,
  plugins: readonly AnyPlugin[],
  options: ApiOptions<Ref>,
): BuiltModel {
  const prefix = options.extensionPrefix ?? "x-better-supabase-";
  const diagnostics: SpecDiagnostic[] = [];
  const report = (diagnostic: SpecDiagnostic): void => {
    diagnostics.push(diagnostic);
  };
  const base = (options.basePath ?? "").replace(/\/$/, "");
  const globalErrors = options.errors ?? DEFAULT_ERRORS;
  const schemas: Record<string, Json> = {
    Problem: structuredClone(PROBLEM_SCHEMA),
  };
  const responses: Record<string, ModelResponse> = {};
  for (const error of globalErrors)
    responses[error.name] = errorResponse(error);
  const operations: DraftOperation[] = [];
  const tags: ModelTag[] = [...(options.tags ?? [])];
  const served = new Map<string, ServedTable>();
  const { authorizer } = options;

  const addTag = (name: string, description?: string): void => {
    if (tags.some((tag) => tag.name === name)) return;
    tags.push({ name, ...(description ? { description } : {}) });
  };

  const addComponent = (name: string, schema: Json): void => {
    const existing = schemas[name];
    if (existing && JSON.stringify(existing) !== JSON.stringify(schema)) {
      report({
        code: "component-conflict",
        severity: "error",
        message: `Two different schemas are named "${name}"; the first one is kept`,
        pointer: `/components/schemas/${pointerToken(name)}`,
      });
      return;
    }
    schemas[name] = schema;
  };

  const keyOf = (ref: Ref, where: string): string | undefined => {
    if (authorizer) {
      try {
        return authorizer.key(ref);
      } catch {
        report({
          code: "permission-unresolved",
          severity: "error",
          message: `${where}: the authorizer has no key for this permission`,
        });
        return undefined;
      }
    }
    if (typeof ref === "string") return ref;
    report({
      code: "permission-unresolved",
      severity: "error",
      message: `${where}: a permission that is not a string needs an authorizer`,
    });
    return undefined;
  };

  const converted = (
    standard: StandardLike,
    direction: "input" | "output",
    where: string,
  ) => {
    const result = convertStandard(standard, direction);
    if (!result) {
      report({
        code: "schema-unconvertible",
        severity: "warning",
        message: `${where}: the schema does not implement Standard JSON Schema, so the spec allows any value`,
      });
    }
    return result;
  };

  const schemaOf = (
    standard: StandardLike,
    direction: "input" | "output",
    role: "input" | "output" | "item",
    operationId: string,
  ): JsonSchema => {
    const result = converted(standard, direction, `${operationId} ${role}`);
    if (!result) return {};
    const name = options.componentName
      ? options.componentName({
          kind: "schema",
          id: result.name,
          schema: result.schema,
          role,
          operationId,
        })
      : result.name;
    if (!name) return structuredClone(result.schema);
    addComponent(name, structuredClone(result.schema));
    return schemaRef(name);
  };

  const objectParameters = (
    standard: StandardLike,
    location: "path" | "query",
    where: string,
  ): ModelParameter[] => {
    const result = converted(standard, "input", where);
    const properties = result?.schema["properties"];
    if (!result || !isPlainObject(properties)) return [];
    const required = result.schema["required"];
    const requiredNames = Array.isArray(required) ? required : [];
    return Object.entries(properties).flatMap(([name, schema]) => {
      if (!isPlainObject(schema)) return [];
      const description = schema["description"];
      return [
        {
          name,
          in: location,
          required: location === "path" || requiredNames.includes(name),
          ...(typeof description === "string" ? { description } : {}),
          schema: structuredClone(schema),
        },
      ];
    });
  };

  const usedErrors = (
    errors: readonly ErrorResponse[],
    statuses: readonly number[],
    permission: boolean,
  ): Record<string, ModelResponseOrRef> => {
    const out: Record<string, ModelResponseOrRef> = {};
    for (const error of errors) {
      if (SCOPED_STATUSES.has(error.status) && !statuses.includes(error.status))
        continue;
      const status = String(error.status);
      if (Object.hasOwn(out, status)) continue;
      if (error.status === 403 && permission) continue;
      responses[error.name] ??= errorResponse(error);
      out[status] = { ref: error.name };
    }
    if (permission) {
      responses[PERMISSION_DENIED] ??= permissionDeniedResponse();
      out["403"] = { ref: PERMISSION_DENIED };
    }
    return out;
  };

  const extendFor = (
    extend: Readonly<Record<string, JsonObject>> | undefined,
    name: string,
  ): JsonObject | undefined => {
    if (!extend) return undefined;
    const all = extend["*"];
    const own = extend[name];
    if (!all && !own) return undefined;
    return mergeJson<JsonObject>(all ?? {}, own ?? {});
  };

  for (const [key, input] of Object.entries(options.resources ?? {})) {
    let plan: ResourcePlan<Ref>;
    if (isPlanCarrier(input)) plan = input.plan;
    else {
      if (!meta.tables[key])
        throw new TypeError(`better-supabase/spec: unknown table "${key}"`);
      plan = planResource(meta, key, input === true ? {} : input, authorizer);
    }
    const tableKey = plan.table;
    const table = plan.meta;
    const description = plan.description;
    const name = pascal(tableKey);
    const tableDocs = docsOf(table);
    const defs = tableSchemas(meta, options.json ?? {});
    const componentFor = (
      variant: "Row" | "Insert" | "Update" | "Page",
    ): string => {
      const defaultName = `${name}${variant}`;
      return (
        options.componentName?.({
          kind: "table",
          table: tableKey,
          variant,
          defaultName,
        }) ?? defaultName
      );
    };
    const components: ServedTable["components"] = {};
    for (const variant of ["Row", "Insert", "Update"] as const) {
      const def = defs[`${tableKey}${variant}`];
      if (!def) continue;
      const schema: Json = structuredClone(def);
      if (tableDocs.description && schema["description"] === undefined)
        schema["description"] = tableDocs.description;
      if (tableDocs.deprecated) schema["deprecated"] = true;
      const properties = mutableProperties(schema);
      for (const [column, property] of Object.entries(properties ?? {})) {
        const docs = docsOf(table.columns[column]);
        if (docs.description && property["description"] === undefined)
          property["description"] = docs.description;
        if (docs.deprecated) property["deprecated"] = true;
      }
      const examples = options.examples?.[tableKey];
      if (variant === "Row" && examples && examples.length > 0)
        schema["examples"] = structuredClone(examples);
      const componentName = componentFor(variant);
      components[variant] = componentName;
      addComponent(componentName, schema);
    }
    const rowName = components.Row ?? componentFor("Row");
    const cursor = plan.pagination === "cursor";
    const pageName = componentFor("Page");
    addComponent(pageName, pageSchema(schemaRef(rowName), cursor));

    const tag = description.tag ?? tableKey;
    addTag(tag, description.description ?? tableDocs.description);
    const collection = `${base}${description.path ?? `/${tableKey}`}`;
    const keyParam = plan.keyParam;
    const rowProperties = defs[`${tableKey}Row`]?.["properties"];
    const keySchema =
      keyParam && isPlainObject(rowProperties)
        ? rowProperties[keyParam]
        : undefined;
    const idParameter: ModelParameter | undefined = keyParam
      ? {
          name: keyParam,
          in: "path",
          required: true,
          schema: isPlainObject(keySchema)
            ? structuredClone(keySchema)
            : { type: "string" },
        }
      : undefined;
    const item = keyParam ? `${collection}/{${keyParam}}` : undefined;
    const errors = description.errors ?? globalErrors;
    const servedTable: ServedTable = { table, components, operations: [] };
    served.set(tableKey, servedTable);
    const names = new Set<string>([
      ...plan.operations,
      ...plan.actions.map((action) => action.name),
    ]);
    for (const extendKey of Object.keys(description.extend ?? {})) {
      if (extendKey !== "*" && !names.has(extendKey)) {
        report({
          code: "extend-unknown",
          severity: "warning",
          message: `${tableKey}.extend.${extendKey} names no operation or action of the resource`,
        });
      }
    }

    const add = (
      opName: string,
      source: OperationSource,
      method: HttpMethod,
      path: string,
      fields: Omit<
        DraftOperation,
        "id" | "method" | "path" | "tags" | "source" | "extensions"
      > & { readonly extensions?: Json },
    ): void => {
      const defaultId = `${opName}${name}`;
      const id =
        options.operationId?.({ source, method, path, defaultId }) ?? defaultId;
      const ref = plan.permissions[opName];
      const permission =
        ref === undefined ? undefined : keyOf(ref, `${tableKey}.${opName}`);
      const extend = extendFor(description.extend, opName);
      const { extensions, ...rest } = fields;
      const operation: DraftOperation = {
        id,
        method,
        path,
        tags: [tag],
        source,
        ...rest,
        extensions: {
          [`${prefix}table`]: `${table.schema}.${table.name}`,
          ...extensions,
          ...(permission === undefined
            ? {}
            : { [`${prefix}permission`]: permission }),
        },
        ...(permission === undefined ? {} : { permission }),
        ...(description.security ? { security: description.security } : {}),
        ...(extend ? { extend } : {}),
        ...(tableDocs.deprecated ? { deprecated: true } : {}),
      };
      operations.push(operation);
      servedTable.operations.push(operation);
    };

    const outputOf = (
      operation: ResourceOperation,
      fallback: JsonSchema,
    ): JsonSchema => {
      const output = description.output?.[operation];
      return output
        ? schemaOf(output, "output", "output", `${operation}${name}`)
        : fallback;
    };
    const resourceOp = (operation: ResourceOperation): OperationSource => ({
      kind: "resource",
      table: tableKey,
      operation,
    });
    const errorsFor = (operation: ResourceOperation) =>
      usedErrors(
        errors,
        OPERATION_STATUSES[operation],
        plan.permissions[operation] !== undefined,
      );
    const opExtension = (operation: string): Json => ({
      [`${prefix}operation`]: operation,
    });

    for (const operation of plan.operations) {
      switch (operation) {
        case "list": {
          const listOutput = description.output?.list;
          const pageRef = listOutput
            ? pageSchema(
                schemaOf(listOutput, "output", "item", `list${name}`),
                cursor,
              )
            : schemaRef(pageName);
          add("list", resourceOp("list"), "get", collection, {
            summary: `List ${tableKey}`,
            extensions: opExtension("list"),
            parameters: description.list
              ? description.list.openapi.filter(isParameter)
              : pageParameters(cursor, plan.maxPageSize),
            responses: {
              "200": jsonResponse(pageRef, `A page of ${tableKey}.`),
              ...errorsFor("list"),
            },
          });
          break;
        }
        case "create": {
          const body = description.input?.create
            ? schemaOf(
                description.input.create,
                "input",
                "input",
                `create${name}`,
              )
            : schemaRef(components.Insert ?? componentFor("Insert"));
          add("create", resourceOp("create"), "post", collection, {
            summary: `Create a ${tableKey} row`,
            extensions: opExtension("create"),
            parameters: [],
            requestBody: { required: true, content: jsonContent(body) },
            responses: {
              "201": jsonResponse(
                outputOf("create", schemaRef(rowName)),
                "Created.",
              ),
              ...errorsFor("create"),
            },
          });
          break;
        }
        case "get":
          if (!item || !idParameter) break;
          add("get", resourceOp("get"), "get", item, {
            summary: `Get a ${tableKey} row`,
            extensions: opExtension("get"),
            parameters: [idParameter],
            responses: {
              "200": jsonResponse(
                outputOf("get", schemaRef(rowName)),
                "The row.",
              ),
              ...errorsFor("get"),
            },
          });
          break;
        case "update": {
          if (!item || !idParameter) break;
          const body = description.input?.update
            ? schemaOf(
                description.input.update,
                "input",
                "input",
                `update${name}`,
              )
            : schemaRef(components.Update ?? componentFor("Update"));
          add("update", resourceOp("update"), "patch", item, {
            summary: `Update a ${tableKey} row`,
            extensions: opExtension("update"),
            parameters: [idParameter],
            requestBody: { required: true, content: jsonContent(body) },
            responses: {
              "200": jsonResponse(
                outputOf("update", schemaRef(rowName)),
                "Updated.",
              ),
              ...errorsFor("update"),
            },
          });
          break;
        }
        case "delete":
          if (!item || !idParameter) break;
          add("delete", resourceOp("delete"), "delete", item, {
            summary: `Delete a ${tableKey} row`,
            extensions: opExtension("delete"),
            parameters: [idParameter],
            responses: {
              "204": { description: "Deleted." },
              ...errorsFor("delete"),
            },
          });
          break;
        default: {
          const unknown: never = operation;
          throw new TypeError(
            `better-supabase/spec: unknown operation "${String(unknown)}"`,
          );
        }
      }
    }

    for (const action of plan.actions) {
      const method = action.method.toLowerCase();
      if (!isMethod(method))
        throw new TypeError(
          `${tableKey}.actions.${action.name}: unknown method`,
        );
      const operationId = `${action.name}${name}`;
      const parameters: ModelParameter[] = [
        ...(action.params.length > 0 && idParameter ? [idParameter] : []),
        ...(action.query
          ? objectParameters(action.query, "query", `${operationId} query`)
          : []),
      ];
      const status = String(action.status ?? (action.output ? 200 : 204));
      const statuses = [
        ...(action.input || action.query ? [400] : []),
        401,
        403,
        ...(action.params.length > 0 ? [404] : []),
        ...(action.input ? [422] : []),
      ];
      add(
        action.name,
        { kind: "action", table: tableKey, action: action.name },
        method,
        `${collection}${action.path}`,
        {
          ...(action.summary ? { summary: action.summary } : {}),
          ...(action.description ? { description: action.description } : {}),
          ...(action.deprecated ? { deprecated: true } : {}),
          extensions: {
            [`${prefix}action`]: action.name,
            ...(action.emits ? { [`${prefix}emits`]: [...action.emits] } : {}),
          },
          parameters,
          ...(action.input
            ? {
                requestBody: {
                  required: true,
                  content: jsonContent(
                    schemaOf(action.input, "input", "input", operationId),
                  ),
                },
              }
            : {}),
          responses: {
            [status]: action.output
              ? jsonResponse(
                  schemaOf(action.output, "output", "output", operationId),
                  action.summary ?? "Done.",
                )
              : { description: action.summary ?? "Done." },
            ...usedErrors(errors, statuses, action.permission !== undefined),
          },
        },
      );
    }
  }

  for (const [index, route] of (options.routes ?? []).entries()) {
    const method = route.method.toLowerCase();
    if (!isMethod(method))
      throw new TypeError(
        `better-supabase/spec: routes[${index}] has an unknown method "${route.method}"`,
      );
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
    if (route.query)
      parameters.push(...objectParameters(route.query, "query", `${id} query`));
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
    for (const tag of routeTags) addTag(tag);
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

  const oauthScopes: Record<string, string> = {};
  if (options.permissionScopes === "keys") {
    for (const operation of operations)
      if (operation.permission)
        oauthScopes[operation.permission] =
          `Permission ${operation.permission}.`;
  }
  const security = resolveSecurity(
    options.security ?? ["bearer"],
    options.supabaseUrl,
    oauthScopes,
  );
  if (options.permissionScopes === "keys") {
    for (const operation of operations) {
      const key = operation.permission;
      if (!key || operation.security?.length === 0) continue;
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

  const describe = describeApi(meta, prefix, served, schemas);
  for (const plugin of plugins) {
    if (!plugin.describe) continue;
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

  if (options.requirePermissions) {
    for (const operation of operations) {
      const writes =
        operation.source.kind === "resource"
          ? operation.source.operation !== "list" &&
            operation.source.operation !== "get"
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

  const { enrich } = options;
  const finalSchemas: Record<string, JsonSchema> = {};
  for (const [name, schema] of Object.entries(schemas))
    finalSchemas[name] = enrich?.schema?.(schema, { name }) ?? schema;
  const finalOperations = operations.map(
    (operation) => enrich?.operation?.(operation) ?? operation,
  );
  const messages: Record<string, ModelMessage> = {};
  for (const [id, message] of Object.entries(options.messages ?? {}))
    messages[id] = enrich?.message?.(message, { id }) ?? message;

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
    channels: (options.channels ?? []).map(
      (channel) => enrich?.channel?.(channel) ?? channel,
    ),
    messages,
    webhooks: options.webhooks ?? [],
    workflows: (options.workflows ?? []).map(
      (workflow) => enrich?.workflow?.(workflow) ?? workflow,
    ),
    fragments: options.fragments ?? [],
    ...(options.realtimeUrl ? { realtimeUrl: options.realtimeUrl } : {}),
    extensionPrefix: prefix,
  };
  return { model, diagnostics };
}

function describeApi(
  meta: SchemaMeta,
  prefix: string,
  served: ReadonlyMap<string, ServedTable>,
  schemas: Record<string, Json>,
): PluginDescribeApi {
  const columnSchemas = (table: string, column: string) => {
    const entry = served.get(table);
    if (!entry) return [];
    return (["Row", "Insert", "Update"] as const).flatMap((variant) => {
      const name = entry.components[variant];
      const schema = name ? schemas[name] : undefined;
      const properties = schema?.["properties"];
      if (!schema || !isPlainObject(properties)) return [];
      const property = properties[column];
      if (!isPlainObject(property)) return [];
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
      operations: entry.operations.map((operation) =>
        operation.source.kind === "action"
          ? operation.source.action
          : operation.source.kind === "resource"
            ? operation.source.operation
            : operation.id,
      ),
    })),
    addParameter(table, parameter, names): void {
      for (const operation of served.get(table)?.operations ?? []) {
        const name =
          operation.source.kind === "action"
            ? operation.source.action
            : operation.source.kind === "resource"
              ? operation.source.operation
              : operation.id;
        if (names && !names.includes(name)) continue;
        if (
          operation.parameters.some(
            (entry) =>
              entry.name === parameter.name && entry.in === parameter.in,
          )
        )
          continue;
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
        if (variant !== "Row" && Array.isArray(required))
          schema["required"] = required.filter((name) => name !== column);
      }
    },
    describeColumn(table, column, patch): void {
      for (const { schema, properties, property } of columnSchemas(
        table,
        column,
      ))
        replace(schema, properties, column, mergeJson<Json>(property, patch));
    },
  };
}
