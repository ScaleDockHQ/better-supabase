import type {
  DocumentFormat,
  LowerContext,
  SpecDiagnostic,
} from "../spec/format.ts";
import type {
  ApiModel,
  JsonObject,
  ModelContent,
  ModelOperation,
  ModelParameter,
  ModelResponse,
  ModelResponseOrRef,
  ModelSecurityScheme,
  ModelWebhook,
  SecurityRequirement,
} from "../spec/model.ts";
import type {
  AnyOpenApiDocument,
  OpenApiDocuments,
  OpenApiVersion,
} from "./types.ts";

import { isPlainObject } from "../core/clone.ts";
import { SPEC_PINS } from "../core/spec-pins.ts";
import { defineDocumentFormat } from "../spec/format.ts";
import { mergeJson, pointerToken } from "../spec/merge.ts";
import { pascal } from "../spec/schemas.ts";
import { lowerDocumentSchemas30 } from "./schema30.ts";
import { OPENAPI_33_PREVIEW_VERSION } from "./types.ts";

type Json = Record<string, unknown>;

const DIALECT = "https://json-schema.org/draft/2020-12/schema";

const OPENAPI_FIELD = {
  "3.0": SPEC_PINS.openapi30,
  "3.1": SPEC_PINS.openapi31,
  "3.2": SPEC_PINS.openapi32,
  "3.3-preview": OPENAPI_33_PREVIEW_VERSION,
} as const satisfies Record<OpenApiVersion, string>;

/** Path Item fields that hold an Operation Object. */
const METHODS: ReadonlySet<string> = new Set([
  "get",
  "put",
  "post",
  "delete",
  "options",
  "head",
  "patch",
  "trace",
  "query",
]);

interface Features {
  readonly version: OpenApiVersion;
  /** OpenAPI 3.2 fields are native (3.2 and the 3.3 preview). */
  readonly native32: boolean;
  readonly is30: boolean;
  readonly is33: boolean;
  readonly prefix: string;
  /** Security schemes this version cannot emit. */
  readonly dropped: ReadonlySet<string>;
}

const omitUndefined = (value: Json): Json =>
  Object.fromEntries(
    Object.entries(value).filter(([, entry]) => entry !== undefined),
  );

function lowerContent(
  content: Readonly<Record<string, ModelContent>>,
  features: Features,
): Json {
  return Object.fromEntries(
    Object.entries(content).map(([type, media]) => [
      type,
      omitUndefined({
        schema: media.schema,
        [features.native32 ? "itemSchema" : "x-oai-itemSchema"]:
          media.itemSchema,
        examples: media.examples
          ? Object.fromEntries(
              Object.entries(media.examples).map(([name, example]) => [
                name,
                omitUndefined({ ...example }),
              ]),
            )
          : undefined,
      }),
    ]),
  );
}

function lowerResponse(response: ModelResponse, features: Features): Json {
  return omitUndefined({
    [features.native32 ? "summary" : "x-oai-summary"]: response.summary,
    description: response.description,
    headers: response.headers
      ? Object.fromEntries(
          Object.entries(response.headers).map(([name, header]) => [
            name,
            omitUndefined({ ...header }),
          ]),
        )
      : undefined,
    content: response.content
      ? lowerContent(response.content, features)
      : undefined,
  });
}

const lowerResponseOrRef = (
  response: ModelResponseOrRef,
  features: Features,
): Json =>
  "ref" in response
    ? { $ref: `#/components/responses/${response.ref}` }
    : lowerResponse(response, features);

const lowerParameter = (parameter: ModelParameter): Json =>
  omitUndefined({ ...parameter });

function lowerSecurity(
  requirements: readonly SecurityRequirement[],
  features: Features,
): Json[] {
  return requirements
    .filter((requirement) =>
      Object.keys(requirement).every((name) => !features.dropped.has(name)),
    )
    .map((requirement) => ({ ...requirement }));
}

function lowerScheme(
  scheme: ModelSecurityScheme,
  features: Features,
): Json | undefined {
  switch (scheme.type) {
    case "http":
    case "apiKey":
    case "openIdConnect":
      return omitUndefined({ ...scheme });
    case "oauth2": {
      const { metadataUrl, ...rest } = scheme;
      return omitUndefined({
        ...rest,
        [features.native32
          ? "oauth2MetadataUrl"
          : `${features.prefix}oauth2MetadataUrl`]: metadataUrl,
      });
    }
    case "profile":
      return features.is33 ? omitUndefined({ ...scheme }) : undefined;
    default: {
      const unknown: never = scheme;
      return unknown;
    }
  }
}

function lowerOperation(operation: ModelOperation, features: Features): Json {
  return omitUndefined({
    operationId: operation.id,
    summary: operation.summary,
    description: operation.description,
    tags: operation.tags.length > 0 ? [...operation.tags] : undefined,
    deprecated: operation.deprecated,
    parameters:
      operation.parameters.length > 0
        ? operation.parameters.map(lowerParameter)
        : undefined,
    requestBody: operation.requestBody
      ? omitUndefined({
          description: operation.requestBody.description,
          required: operation.requestBody.required,
          content: lowerContent(operation.requestBody.content, features),
        })
      : undefined,
    responses: Object.fromEntries(
      Object.entries(operation.responses).map(([status, response]) => [
        status,
        lowerResponseOrRef(response, features),
      ]),
    ),
    security: operation.security
      ? lowerSecurity(operation.security, features)
      : undefined,
    ...operation.extensions,
  });
}

const sameJson = (a: unknown, b: unknown): boolean =>
  JSON.stringify(a) === JSON.stringify(b);

/**
 * Builds one Path Item. Path parameters every operation shares move to the
 * Path Item; in 3.3 a `security` every operation shares does too.
 */
function pathItem(
  operations: readonly { method: string; operation: Json }[],
  features: Features,
): Json {
  const pathParameters = (operation: Json): unknown[] =>
    Array.isArray(operation["parameters"])
      ? operation["parameters"].filter(
          (parameter: unknown) =>
            isPlainObject(parameter) && parameter["in"] === "path",
        )
      : [];
  const first = operations[0];
  const shared = first ? pathParameters(first.operation) : [];
  const hoist =
    shared.length > 0 &&
    operations.every(({ operation }) =>
      sameJson(pathParameters(operation), shared),
    );
  const firstSecurity = first?.operation["security"];
  const hoistSecurity =
    features.is33 &&
    firstSecurity !== undefined &&
    operations.every(({ operation }) =>
      sameJson(operation["security"], firstSecurity),
    );
  const item: Json = {};
  if (hoist) item["parameters"] = shared;
  if (hoistSecurity) item["security"] = firstSecurity;
  for (const { method, operation } of operations) {
    const out: Json = { ...operation };
    if (hoist) {
      const rest = Array.isArray(out["parameters"])
        ? out["parameters"].filter(
            (parameter: unknown) =>
              !isPlainObject(parameter) || parameter["in"] !== "path",
          )
        : [];
      if (rest.length > 0) out["parameters"] = rest;
      else delete out["parameters"];
    }
    if (hoistSecurity) delete out["security"];
    item[method] = out;
  }
  return item;
}

const STANDARD_WEBHOOK_HEADERS: readonly Json[] = [
  {
    name: "webhook-id",
    in: "header",
    required: true,
    description: "Unique message id; the same on every retry.",
    schema: { type: "string" },
  },
  {
    name: "webhook-timestamp",
    in: "header",
    required: true,
    description: "Unix time in seconds when the message was sent.",
    schema: { type: "string", pattern: "^[0-9]+$" },
  },
  {
    name: "webhook-signature",
    in: "header",
    required: true,
    description:
      "Space-separated signatures of `id.timestamp.body`, each `v1,<base64>`.",
    schema: { type: "string" },
  },
];

function lowerWebhook(webhook: ModelWebhook): Json {
  return {
    post: omitUndefined({
      operationId: `on${pascal(webhook.id.replaceAll(".", "_"))}`,
      summary: webhook.summary,
      description: webhook.description,
      parameters: webhook.standardWebhooks
        ? STANDARD_WEBHOOK_HEADERS.map((header) => ({ ...header }))
        : undefined,
      requestBody: {
        required: true,
        content: { "application/json": { schema: webhook.payload } },
      },
      responses: {
        "2XX": { description: "The receiver accepted the event." },
      },
    }),
  };
}

function lowerTags(model: ApiModel, features: Features): Json[] {
  return model.tags.map((tag) =>
    features.native32
      ? omitUndefined({ ...tag })
      : omitUndefined({
          name: tag.name,
          description: tag.description,
          [`${features.prefix}summary`]: tag.summary,
          [`${features.prefix}parent`]: tag.parent,
          [`${features.prefix}kind`]: tag.kind,
        }),
  );
}

function lowerOpenApi(
  model: ApiModel,
  version: OpenApiVersion,
  ctx: LowerContext,
): AnyOpenApiDocument {
  const is33 = version === "3.3-preview";
  const dropped = new Set(
    is33
      ? []
      : Object.entries(model.securitySchemes)
          .filter(([, scheme]) => scheme.type === "profile")
          .map(([name]) => name),
  );
  const features: Features = {
    version,
    native32: version === "3.2" || is33,
    is30: version === "3.0",
    is33,
    prefix: model.extensionPrefix,
    dropped,
  };
  for (const name of dropped)
    ctx.report({
      code: "preview-only",
      severity: "info",
      message: `Security scheme "${name}" uses Security Profiles, which only 3.3-preview emits; it and the requirements that name it are left out`,
      pointer: `/components/securitySchemes/${pointerToken(name)}`,
    });

  const grouped = new Map<string, { method: string; operation: Json }[]>();
  const placed: ModelOperation[] = [];
  for (const operation of model.operations) {
    if (operation.method === "query" && !features.native32) {
      ctx.report({
        code: "method-unsupported",
        severity: "warning",
        message: `Operation "${operation.id}" uses the QUERY method, which OpenAPI ${version} cannot describe; it is left out`,
        pointer: `/paths/${pointerToken(operation.path)}`,
      });
      continue;
    }
    const list = grouped.get(operation.path) ?? [];
    list.push({
      method: operation.method,
      operation: lowerOperation(operation, features),
    });
    grouped.set(operation.path, list);
    placed.push(operation);
  }
  const paths: Json = {};
  for (const [path, operations] of grouped)
    paths[path] = pathItem(operations, features);

  const securitySchemes: Json = {};
  for (const [name, scheme] of Object.entries(model.securitySchemes)) {
    const lowered = lowerScheme(scheme, features);
    if (lowered) securitySchemes[name] = lowered;
  }
  const components: Json = {
    schemas: structuredClone(model.schemas),
    responses: Object.fromEntries(
      Object.entries(model.responses).map(([name, response]) => [
        name,
        lowerResponse(response, features),
      ]),
    ),
    securitySchemes,
  };
  if (is33 && model.securityProfileRequirements)
    components["securityProfileRequirements"] = structuredClone(
      model.securityProfileRequirements,
    );

  let webhooks: Json | undefined;
  if (model.webhooks.length > 0) {
    if (features.is30)
      ctx.report({
        code: "webhooks-unsupported",
        severity: "warning",
        message: `OpenAPI 3.0 has no webhooks; ${model.webhooks.length} webhook(s) are left out`,
      });
    else
      webhooks = Object.fromEntries(
        model.webhooks.map((webhook) => [webhook.id, lowerWebhook(webhook)]),
      );
  }

  const info = features.is30
    ? omitUndefined({
        ...model.info,
        summary: undefined,
        license: model.info.license
          ? omitUndefined({ ...model.info.license, identifier: undefined })
          : undefined,
      })
    : omitUndefined({ ...model.info });

  let document: Json = omitUndefined({
    openapi: OPENAPI_FIELD[version],
    [features.native32 ? "$self" : "x-oai-$self"]: model.self,
    info: structuredClone(info),
    jsonSchemaDialect: features.is30 ? undefined : DIALECT,
    servers:
      model.servers.length > 0
        ? model.servers.map((server) =>
            omitUndefined({
              url: server.url,
              description: server.description,
              [features.native32 ? "name" : "x-oai-name"]: server.name,
            }),
          )
        : undefined,
    tags: lowerTags(model, features),
    security: lowerSecurity(model.security, features),
    paths,
    webhooks,
    components,
    [`${features.prefix}preview`]: is33
      ? SPEC_PINS.openapi33Preview
      : undefined,
  });

  model.fragments.forEach((fragment, index) => {
    document = mergeJson(document, fragment, (pointer) => {
      ctx.report({
        code: "fragment-conflict",
        severity: "warning",
        message: `Fragment ${index} replaces a generated value`,
        pointer,
      });
    });
  });
  for (const operation of placed) {
    if (!operation.extend) continue;
    const patch: JsonObject = {
      paths: { [operation.path]: { [operation.method]: operation.extend } },
    };
    document = mergeJson(document, patch);
  }
  if (features.is30) document = lowerDocumentSchemas30(document);
  if (!isOpenApiDocument(document))
    throw new TypeError(
      "better-supabase/openapi: a fragment removed a required document field",
    );
  return document;
}

/** The fields every OpenAPI document this format renders has. */
function isOpenApiDocument(value: Json): value is Json & AnyOpenApiDocument {
  return (
    typeof value["openapi"] === "string" &&
    isPlainObject(value["info"]) &&
    isPlainObject(value["paths"]) &&
    isPlainObject(value["components"]) &&
    Array.isArray(value["tags"]) &&
    Array.isArray(value["security"])
  );
}

const PATH_PARAM = /\{([^}]+)\}/g;

function resolves(document: unknown, ref: string): boolean {
  if (!ref.startsWith("#")) return true;
  let node: unknown = document;
  for (const raw of ref.slice(2).split("/")) {
    if (raw === "" && ref === "#") break;
    const key = raw.replaceAll("~1", "/").replaceAll("~0", "~");
    if (Array.isArray(node)) node = node[Number(key)];
    else if (isPlainObject(node)) node = node[key];
    else return false;
    if (node === undefined) return false;
  }
  return true;
}

function collectRefs(value: unknown, pointer: string, out: [string, string][]) {
  if (Array.isArray(value))
    value.forEach((item: unknown, index) => {
      collectRefs(item, `${pointer}/${index}`, out);
    });
  else if (isPlainObject(value))
    for (const [key, item] of Object.entries(value)) {
      if (key === "$ref" && typeof item === "string") out.push([pointer, item]);
      else collectRefs(item, `${pointer}/${pointerToken(key)}`, out);
    }
}

function lintOpenApi(document: AnyOpenApiDocument): SpecDiagnostic[] {
  const diagnostics: SpecDiagnostic[] = [];
  const ids = new Map<string, string>();
  const schemes = new Set(Object.keys(document.components.securitySchemes));
  const checkSecurity = (requirements: unknown, pointer: string) => {
    if (!Array.isArray(requirements)) return;
    const list: unknown[] = requirements;
    for (const requirement of list) {
      if (!isPlainObject(requirement)) continue;
      for (const name of Object.keys(requirement))
        if (!schemes.has(name))
          diagnostics.push({
            code: "security-unresolved",
            severity: "error",
            message: `Security requirement names an unknown scheme "${name}"`,
            pointer,
          });
    }
  };
  checkSecurity(document.security, "/security");
  for (const [path, item] of Object.entries(document.paths)) {
    const base = `/paths/${pointerToken(path)}`;
    const templated = new Set(
      [...path.matchAll(PATH_PARAM)].map((match) => match[1] ?? ""),
    );
    const shared: unknown[] = Array.isArray(item["parameters"])
      ? item["parameters"]
      : [];
    checkSecurity(item["security"], `${base}/security`);
    for (const [method, operation] of Object.entries(item)) {
      if (!METHODS.has(method) || !isPlainObject(operation)) continue;
      const pointer = `${base}/${method}`;
      const id = operation["operationId"];
      if (typeof id === "string") {
        const seen = ids.get(id);
        if (seen)
          diagnostics.push({
            code: "operation-id-duplicate",
            severity: "error",
            message: `operationId "${id}" is also used at ${seen}`,
            pointer,
          });
        else ids.set(id, pointer);
      }
      checkSecurity(operation["security"], `${pointer}/security`);
      const own: unknown[] = Array.isArray(operation["parameters"])
        ? operation["parameters"]
        : [];
      const declared = new Set<string>();
      for (const parameter of [...shared, ...own]) {
        if (!isPlainObject(parameter) || parameter["in"] !== "path") continue;
        const name = String(parameter["name"]);
        declared.add(name);
        if (!templated.has(name))
          diagnostics.push({
            code: "path-param-unknown",
            severity: "error",
            message: `Path parameter "${name}" is not in the path template`,
            pointer,
          });
      }
      for (const name of templated)
        if (!declared.has(name))
          diagnostics.push({
            code: "path-param-missing",
            severity: "error",
            message: `Path template parameter "${name}" has no parameter`,
            pointer,
          });
    }
  }
  const refs: [string, string][] = [];
  collectRefs(document, "", refs);
  for (const [pointer, ref] of refs)
    if (!resolves(document, ref))
      diagnostics.push({
        code: "ref-unresolved",
        severity: "error",
        message: `$ref "${ref}" does not resolve inside the document`,
        pointer,
      });
  return diagnostics;
}

/**
 * OpenAPI as a `DocumentFormat`. 3.1 is the default; 3.0 is legacy (schemas
 * lowered to the 3.0 Schema Object); 3.2 has native `$self`, nested tags,
 * `itemSchema`, `oauth2MetadataUrl` and `query`; `3.3-preview` follows the
 * v3.3-dev branch at `SPEC_PINS.openapi33Preview`, with Path Item
 * `security` and the Security Profiles proposal. Below 3.2, the 3.2 fields
 * travel as the registered `x-oai-*` extensions where one exists, and as
 * the model's prefixed extensions otherwise.
 */
export const openapiFormat: DocumentFormat<
  "openapi",
  OpenApiVersion,
  AnyOpenApiDocument,
  OpenApiDocuments
> = defineDocumentFormat<
  "openapi",
  OpenApiVersion,
  AnyOpenApiDocument,
  OpenApiDocuments
>({
  id: "openapi",
  versions: {
    "3.0": { pin: SPEC_PINS.openapi30, status: "legacy" },
    "3.1": { pin: SPEC_PINS.openapi31, status: "stable" },
    "3.2": { pin: SPEC_PINS.openapi32, status: "stable" },
    "3.3-preview": { pin: SPEC_PINS.openapi33Preview, status: "preview" },
  },
  defaultVersion: "3.1",
  lower: lowerOpenApi,
  lint: lintOpenApi,
  fileName: () => "openapi.json",
});
