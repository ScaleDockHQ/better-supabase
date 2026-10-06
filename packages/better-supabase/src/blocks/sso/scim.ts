import type { BlockTransport } from "../../core/block-transport.ts";
import type { DbError } from "../../core/errors.ts";
import type { ApiKeys } from "../api-keys/api-keys.ts";

import {
  blockCall,
  isRecord,
  optionalText,
  recordOf,
  recordsOf,
  textOf,
  toInstant,
  type BlockTemporalOptions,
  applyTemporal,
} from "../shared.ts";
import {
  matches,
  parseFilter,
  type ScimFilter,
  ScimFilterError,
} from "./scim-filter.ts";
import { applyPatch, ScimPatchError } from "./scim-patch.ts";
import {
  ATTRIBUTES,
  resourceTypes,
  SCIM_ERROR,
  SCIM_GROUP,
  SCIM_LIST,
  SCIM_PATCH,
  SCIM_SEARCH,
  SCIM_USER,
  schemas,
  serviceProviderConfig,
} from "./scim-schema.ts";

export interface ScimHandlerOptions extends BlockTemporalOptions {
  /** A service-role transport: the SCIM functions are granted to `service_role` only. */
  readonly transport: BlockTransport;
  /** Verifies the bearer token: an organization API key with the `scim` scope. */
  readonly keys: Pick<ApiKeys, "verify">;
  /** The path the handler is mounted at, such as `/scim/v2`. Default empty. */
  readonly basePath?: string;
  /** The API key scope SCIM needs. Default `scim`. */
  readonly scope?: string;
  /** Page size and the largest `count`. Default 100. */
  readonly maxResults?: number;
  readonly documentationUri?: string;
  readonly schema?: string;
}

type Kind = "User" | "Group";
type Doc = Record<string, unknown>;

const MEDIA_TYPE = "application/scim+json";
const MAX_BODY = 1_048_576;

class ScimError extends Error {
  override readonly name = "ScimError";
  readonly status: number;
  readonly scimType: string | undefined;
  readonly headers: Readonly<Record<string, string>>;

  constructor(
    status: number,
    detail: string,
    scimType?: string,
    headers: Readonly<Record<string, string>> = {},
  ) {
    super(detail);
    this.status = status;
    this.scimType = scimType;
    this.headers = headers;
  }
}

function json(
  status: number,
  body: unknown,
  headers: Readonly<Record<string, string>> = {},
): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": MEDIA_TYPE, ...headers },
  });
}

function errorResponse(error: ScimError): Response {
  return json(
    error.status,
    {
      schemas: [SCIM_ERROR],
      status: String(error.status),
      ...(error.scimType === undefined ? {} : { scimType: error.scimType }),
      detail: error.message,
    },
    error.headers,
  );
}

function fromDbError(error: DbError): ScimError {
  if (error.hint === "SCIM_NOT_FOUND") return new ScimError(404, error.message);
  if (error.hint === "SCIM_PRECONDITION") {
    return new ScimError(412, "The resource changed; read it again");
  }
  if (error.kind === "conflict") {
    return new ScimError(
      409,
      "A resource with this value exists",
      "uniqueness",
    );
  }
  if (
    error.hint === "SCIM_INVALID" ||
    error.kind === "invalid_input" ||
    error.kind === "check" ||
    error.kind === "not_null"
  ) {
    return new ScimError(400, error.message, "invalidValue");
  }
  return new ScimError(500, "The service provider failed");
}

const etag = (version: unknown): string => `W/"${String(version)}"`;

/** The version an `If-Match` header requires; `undefined` for none or `*`. */
function ifMatch(request: Request): number | undefined {
  const header = request.headers.get("if-match")?.trim();
  if (!header || header === "*") return undefined;
  const version = /^(?:W\/)?"(\d+)"$/.exec(header)?.[1];
  if (version === undefined) {
    throw new ScimError(412, "If-Match names no current version");
  }
  return Number(version);
}

function meta(row: Doc, kind: Kind, location: string): Doc {
  return {
    resourceType: kind,
    created: toInstant(textOf(row["created_at"])).toString(),
    lastModified: toInstant(textOf(row["updated_at"])).toString(),
    location,
    version: etag(row["version"]),
  };
}

function compact(doc: Doc): Doc {
  return Object.fromEntries(
    Object.entries(doc).filter(([, value]) => value !== undefined),
  );
}

function userOf(value: unknown, base: string): Doc {
  const row = recordOf(value, "scim_users");
  const id = textOf(row["id"]);
  const givenName = optionalText(row["given_name"]);
  const familyName = optionalText(row["family_name"]);
  return compact({
    schemas: [SCIM_USER],
    id,
    externalId: optionalText(row["external_id"]),
    userName: textOf(row["user_name"]),
    name:
      givenName === undefined && familyName === undefined
        ? undefined
        : compact({
            givenName,
            familyName,
            formatted: [givenName, familyName].filter(Boolean).join(" "),
          }),
    displayName: optionalText(row["display_name"]),
    emails: Array.isArray(row["emails"]) ? row["emails"] : [],
    active: row["active"] !== false,
    groups: recordsOf(row["groups"], "scim_users.groups").map((group) => ({
      value: textOf(group["value"]),
      display: textOf(group["display"]),
      $ref: `${base}/Groups/${textOf(group["value"])}`,
    })),
    meta: meta(row, "User", `${base}/Users/${id}`),
  });
}

function groupOf(value: unknown, base: string): Doc {
  const row = recordOf(value, "scim_groups");
  const id = textOf(row["id"]);
  return compact({
    schemas: [SCIM_GROUP],
    id,
    externalId: optionalText(row["external_id"]),
    displayName: textOf(row["display_name"]),
    members: recordsOf(row["members"], "scim_groups.members").map((member) => ({
      value: textOf(member["value"]),
      display: textOf(member["display"]),
      type: "User",
      $ref: `${base}/Users/${textOf(member["value"])}`,
    })),
    meta: meta(row, "Group", `${base}/Groups/${id}`),
  });
}

function stringField(doc: Doc, key: string): string | undefined {
  const value = doc[key];
  if (value === undefined || value === null) return undefined;
  if (typeof value !== "string") {
    throw new ScimError(400, `${key} is a string`, "invalidValue");
  }
  return value;
}

function booleanField(value: unknown): boolean {
  if (value === undefined || value === null) return true;
  if (typeof value === "boolean") return value;
  if (typeof value === "string" && /^(true|false)$/i.test(value)) {
    return value.toLowerCase() === "true";
  }
  throw new ScimError(400, "active is a boolean", "invalidValue");
}

/** Attribute names are case-insensitive: `UserName` reads as `userName`. */
function canonical(doc: Doc, kind: Kind): Doc {
  const names = [
    ...ATTRIBUTES[kind].map((attribute) => attribute.name),
    "schemas",
    "id",
    "meta",
  ];
  const out: Doc = {};
  for (const [key, value] of Object.entries(doc)) {
    const name = names.find((n) => n.toLowerCase() === key.toLowerCase());
    out[name ?? key] = value;
  }
  return out;
}

function userData(input: Doc): Doc {
  const doc = canonical(input, "User");
  const userName = stringField(doc, "userName");
  if (userName === undefined || userName.trim() === "") {
    throw new ScimError(400, "userName is required", "invalidValue");
  }
  const name = isRecord(doc["name"]) ? doc["name"] : {};
  const raw: unknown = doc["emails"] ?? [];
  const emails = Array.isArray(raw) ? raw.filter(isRecord) : [];
  if (
    !Array.isArray(raw) ||
    emails.length !== raw.length ||
    !emails.every((email) => typeof email["value"] === "string")
  ) {
    throw new ScimError(400, "emails are objects with a value", "invalidValue");
  }
  return {
    userName,
    externalId: stringField(doc, "externalId") ?? null,
    displayName: stringField(doc, "displayName") ?? null,
    givenName: stringField(name, "givenName") ?? null,
    familyName: stringField(name, "familyName") ?? null,
    emails: emails.map((email) =>
      compact({
        value: email["value"],
        type: optionalText(email["type"]),
        display: optionalText(email["display"]),
        primary: email["primary"] === true ? true : undefined,
      }),
    ),
    active: booleanField(doc["active"]),
  };
}

function groupData(input: Doc): Doc {
  const doc = canonical(input, "Group");
  const displayName = stringField(doc, "displayName");
  if (displayName === undefined || displayName.trim() === "") {
    throw new ScimError(400, "displayName is required", "invalidValue");
  }
  const raw: unknown = doc["members"] ?? [];
  const members = Array.isArray(raw) ? raw.filter(isRecord) : [];
  if (
    !Array.isArray(raw) ||
    members.length !== raw.length ||
    !members.every((member) => typeof member["value"] === "string")
  ) {
    throw new ScimError(
      400,
      "members are objects with a value",
      "invalidValue",
    );
  }
  return {
    displayName,
    externalId: stringField(doc, "externalId") ?? null,
    members: members.map((member) => String(member["value"])),
  };
}

/** `attributes` and `excludedAttributes` (RFC 7644 §3.4.2.5); `id` and `schemas` always stay. */
function project(
  doc: Doc,
  attributes: readonly string[] | undefined,
  excluded: readonly string[] | undefined,
): Doc {
  const always = new Set(["id", "schemas"]);
  const top = (path: string): string => {
    const local = path.slice(path.lastIndexOf(":") + 1);
    return (local.split(".")[0] ?? local).toLowerCase();
  };
  if (attributes && attributes.length > 0) {
    const wanted = new Set(attributes.map(top));
    return Object.fromEntries(
      Object.entries(doc).filter(
        ([key]) => always.has(key) || wanted.has(key.toLowerCase()),
      ),
    );
  }
  if (excluded && excluded.length > 0) {
    const dropped = new Set(excluded.map(top));
    return Object.fromEntries(
      Object.entries(doc).filter(
        ([key]) => always.has(key) || !dropped.has(key.toLowerCase()),
      ),
    );
  }
  return doc;
}

const list = (value: string | null): readonly string[] | undefined =>
  value === null
    ? undefined
    : value
        .split(",")
        .map((part) => part.trim())
        .filter(Boolean);

interface Query {
  readonly filter: ScimFilter | undefined;
  readonly startIndex: number;
  readonly count: number;
  readonly attributes: readonly string[] | undefined;
  readonly excluded: readonly string[] | undefined;
}

function integer(value: unknown): number | undefined {
  const number = typeof value === "string" ? Number(value) : value;
  return typeof number === "number" && Number.isInteger(number)
    ? number
    : undefined;
}

function queryOf(
  source: {
    readonly filter?: unknown;
    readonly startIndex?: unknown;
    readonly count?: unknown;
    readonly attributes?: readonly string[] | undefined;
    readonly excluded?: readonly string[] | undefined;
  },
  maxResults: number,
): Query {
  if (source.attributes?.length && source.excluded?.length) {
    throw new ScimError(
      400,
      "attributes and excludedAttributes are mutually exclusive",
      "invalidSyntax",
    );
  }
  let filter: ScimFilter | undefined;
  if (typeof source.filter === "string" && source.filter.trim() !== "") {
    try {
      filter = parseFilter(source.filter);
    } catch (cause) {
      throw new ScimError(
        400,
        cause instanceof Error ? cause.message : String(cause),
        "invalidFilter",
      );
    }
  }
  return {
    filter,
    startIndex: Math.max(1, integer(source.startIndex) ?? 1),
    count: Math.min(
      maxResults,
      Math.max(0, integer(source.count) ?? maxResults),
    ),
    attributes: source.attributes,
    excluded: source.excluded,
  };
}

async function readBody(request: Request): Promise<unknown> {
  const text = await request.text();
  if (text.length > MAX_BODY) {
    throw new ScimError(413, "The request body is too large");
  }
  try {
    return JSON.parse(text);
  } catch {
    throw new ScimError(400, "The body is not JSON", "invalidSyntax");
  }
}

function resourceBody(body: unknown, urn: string): Doc {
  if (!isRecord(body)) {
    throw new ScimError(400, "The body is a JSON object", "invalidSyntax");
  }
  const declared = Array.isArray(body["schemas"]) ? body["schemas"] : [];
  if (
    !declared.some(
      (schema) => String(schema).toLowerCase() === urn.toLowerCase(),
    )
  ) {
    throw new ScimError(400, `schemas must include ${urn}`, "invalidSyntax");
  }
  return body;
}

const KINDS = {
  User: {
    endpoint: "Users",
    urn: SCIM_USER,
    list: "scim_list_users",
    get: "scim_get_user",
    save: "scim_save_user",
    remove: "scim_delete_user",
    of: userOf,
    data: userData,
  },
  Group: {
    endpoint: "Groups",
    urn: SCIM_GROUP,
    list: "scim_list_groups",
    get: "scim_get_group",
    save: "scim_save_group",
    remove: "scim_delete_group",
    of: groupOf,
    data: groupData,
  },
} as const;

/**
 * A SCIM 2.0 service provider (RFC 7644) as a web handler: `/Users` and
 * `/Groups` with filters, PATCH and ETags, plus the discovery endpoints.
 * Each request authenticates with an organization API key that has the
 * `scim` scope, and only touches that organization.
 */
export function scimHandler(
  options: ScimHandlerOptions,
): (request: Request) => Promise<Response> {
  applyTemporal(options);
  const call = blockCall(options.transport, options.schema);
  const basePath = (options.basePath ?? "").replace(/\/+$/, "");
  const scope = options.scope ?? "scim";
  const maxResults = options.maxResults ?? 100;
  const discovery = {
    maxResults,
    ...(options.documentationUri === undefined
      ? {}
      : { documentationUri: options.documentationUri }),
  };

  const rpc = async (fn: string, args: Readonly<Record<string, unknown>>) => {
    const result = await call(fn, args, (value) => value);
    if (!result.ok) throw fromDbError(result.error);
    return result.data;
  };

  const authenticate = async (request: Request): Promise<string> => {
    const challenge = { "www-authenticate": 'Bearer realm="SCIM"' };
    const token = request.headers
      .get("authorization")
      ?.match(/^Bearer\s+(.+)$/i)?.[1]
      ?.trim();
    if (!token)
      throw new ScimError(401, "Send a bearer token", undefined, challenge);
    const checked = await options.keys.verify(token);
    if (!checked.ok) throw new ScimError(500, "Could not check the token");
    const check = checked.data;
    switch (check.status) {
      case "invalid":
        throw new ScimError(
          401,
          "The token is not valid",
          undefined,
          challenge,
        );
      case "rate_limited":
        throw new ScimError(429, "Too many requests", undefined, {
          "retry-after": String(check.retryAfter),
        });
      case "ok": {
        const { key } = check;
        if (key.organizationId === undefined) {
          throw new ScimError(403, "SCIM needs an organization API key");
        }
        if (!key.scopes.includes(scope) && !key.scopes.includes("*")) {
          throw new ScimError(403, `The key lacks the ${scope} scope`);
        }
        return key.organizationId;
      }
      default: {
        const exhaustive: never = check;
        return exhaustive;
      }
    }
  };

  const discover = (
    request: Request,
    url: URL,
    base: string,
    segments: readonly string[],
  ): Response | undefined => {
    const [head, ...rest] = segments;
    const ids = rest.join("/");
    const listed = (items: readonly Doc[]): Response =>
      json(200, {
        schemas: [SCIM_LIST],
        totalResults: items.length,
        startIndex: 1,
        itemsPerPage: items.length,
        Resources: items,
      });
    const one = (items: readonly Doc[]): Response => {
      const found = items.find((item) => item["id"] === ids);
      if (!found) throw new ScimError(404, `No ${head} ${ids}`);
      return json(200, found);
    };
    if (
      head !== "ServiceProviderConfig" &&
      head !== "ResourceTypes" &&
      head !== "Schemas"
    ) {
      return undefined;
    }
    if (request.method !== "GET") {
      throw new ScimError(405, `${head} is read-only`);
    }
    if (url.searchParams.has("filter")) {
      throw new ScimError(403, "Discovery endpoints do not filter");
    }
    if (head === "ServiceProviderConfig") {
      return json(200, serviceProviderConfig(base, discovery));
    }
    const items =
      head === "ResourceTypes" ? resourceTypes(base) : schemas(base);
    return ids === "" ? listed(items) : one(items);
  };

  const fetchAll = async (
    kind: Kind,
    tenant: string,
    base: string,
  ): Promise<Doc[]> => {
    const value = await rpc(KINDS[kind].list, { tenant });
    return recordsOf(value, KINDS[kind].list).map((row) =>
      KINDS[kind].of(row, base),
    );
  };

  const fetchOne = async (
    kind: Kind,
    tenant: string,
    id: string,
    base: string,
  ): Promise<Doc> => {
    if (!/^[0-9a-f-]{36}$/i.test(id)) {
      throw new ScimError(404, `No ${kind} ${id}`);
    }
    const value = await rpc(KINDS[kind].get, { tenant, id });
    if (!isRecord(value)) throw new ScimError(404, `No ${kind} ${id}`);
    return KINDS[kind].of(value, base);
  };

  const search = async (
    kind: Kind,
    tenant: string,
    base: string,
    query: Query,
  ): Promise<Response> => {
    let all = await fetchAll(kind, tenant, base);
    if (query.filter) {
      const filter = query.filter;
      try {
        all = all.filter((doc) => matches(doc, filter));
      } catch (cause) {
        if (cause instanceof ScimFilterError) {
          throw new ScimError(400, cause.message, "invalidFilter");
        }
        throw cause;
      }
    }
    const page = all
      .slice(query.startIndex - 1, query.startIndex - 1 + query.count)
      .map((doc) => project(doc, query.attributes, query.excluded));
    return json(200, {
      schemas: [SCIM_LIST],
      totalResults: all.length,
      startIndex: query.startIndex,
      itemsPerPage: page.length,
      Resources: page,
    });
  };

  const save = async (
    kind: Kind,
    tenant: string,
    id: string | null,
    doc: Doc,
    version: number | undefined,
    base: string,
  ): Promise<Doc> => {
    const value = await rpc(KINDS[kind].save, {
      tenant,
      id,
      data: KINDS[kind].data(doc),
      version: version ?? null,
    });
    return KINDS[kind].of(value, base);
  };

  const respond = (
    status: number,
    doc: Doc,
    url: URL,
    extra: Readonly<Record<string, string>> = {},
  ): Response => {
    const metaOf = isRecord(doc["meta"]) ? doc["meta"] : {};
    return json(
      status,
      project(
        doc,
        list(url.searchParams.get("attributes")),
        list(url.searchParams.get("excludedAttributes")),
      ),
      { etag: String(metaOf["version"]), ...extra },
    );
  };

  const resource = async (
    request: Request,
    url: URL,
    base: string,
    kind: Kind,
    id: string | undefined,
    tenant: string,
  ): Promise<Response> => {
    const spec = KINDS[kind];
    const method = request.method;
    if (id === undefined || id === ".search") {
      if (id === ".search") {
        if (method !== "POST") throw new ScimError(405, "Use POST for .search");
        const body = await readBody(request);
        if (
          !isRecord(body) ||
          !Array.isArray(body["schemas"]) ||
          !body["schemas"].includes(SCIM_SEARCH)
        ) {
          throw new ScimError(
            400,
            `schemas must include ${SCIM_SEARCH}`,
            "invalidSyntax",
          );
        }
        const strings = (value: unknown): readonly string[] | undefined =>
          Array.isArray(value) ? value.map(String) : undefined;
        return search(
          kind,
          tenant,
          base,
          queryOf(
            {
              filter: body["filter"],
              startIndex: body["startIndex"],
              count: body["count"],
              attributes: strings(body["attributes"]),
              excluded: strings(body["excludedAttributes"]),
            },
            maxResults,
          ),
        );
      }
      if (method === "GET") {
        return search(
          kind,
          tenant,
          base,
          queryOf(
            {
              filter: url.searchParams.get("filter") ?? undefined,
              startIndex: url.searchParams.get("startIndex") ?? undefined,
              count: url.searchParams.get("count") ?? undefined,
              attributes: list(url.searchParams.get("attributes")),
              excluded: list(url.searchParams.get("excludedAttributes")),
            },
            maxResults,
          ),
        );
      }
      if (method === "POST") {
        const doc = resourceBody(await readBody(request), spec.urn);
        const created = await save(kind, tenant, null, doc, undefined, base);
        const location = String(
          isRecord(created["meta"]) ? created["meta"]["location"] : "",
        );
        return respond(201, created, url, { location });
      }
      throw new ScimError(405, `${method} is not allowed on /${spec.endpoint}`);
    }
    const current = await fetchOne(kind, tenant, id, base);
    const currentMeta = isRecord(current["meta"]) ? current["meta"] : {};
    const currentVersion = Number(
      /\d+/.exec(String(currentMeta["version"]))?.[0],
    );
    const required = ifMatch(request);
    if (
      method !== "GET" &&
      required !== undefined &&
      required !== currentVersion
    ) {
      throw new ScimError(412, "The resource changed; read it again");
    }
    switch (method) {
      case "GET": {
        const unchanged = request.headers.get("if-none-match")?.trim();
        if (unchanged !== undefined && unchanged === currentMeta["version"]) {
          return new Response(null, {
            status: 304,
            headers: { etag: unchanged },
          });
        }
        return respond(200, current, url);
      }
      case "PUT": {
        const doc = resourceBody(await readBody(request), spec.urn);
        return respond(
          200,
          await save(kind, tenant, id, doc, currentVersion, base),
          url,
        );
      }
      case "PATCH": {
        const body = await readBody(request);
        let patched: Doc;
        try {
          patched = applyPatch(
            current,
            body,
            spec.urn,
            ATTRIBUTES[kind],
            SCIM_PATCH,
          );
        } catch (cause) {
          if (cause instanceof ScimPatchError) {
            throw new ScimError(400, cause.message, cause.scimType);
          }
          throw cause;
        }
        return respond(
          200,
          await save(kind, tenant, id, patched, currentVersion, base),
          url,
        );
      }
      case "DELETE": {
        const removed = await rpc(spec.remove, { tenant, id });
        if (removed !== true) throw new ScimError(404, `No ${kind} ${id}`);
        return new Response(null, { status: 204 });
      }
      default:
        throw new ScimError(405, `${method} is not allowed`);
    }
  };

  return async (request) => {
    try {
      const url = new URL(request.url);
      if (!url.pathname.startsWith(basePath)) {
        throw new ScimError(404, "Not a SCIM endpoint");
      }
      const base = `${url.origin}${basePath}`;
      const segments = url.pathname
        .slice(basePath.length)
        .split("/")
        .filter(Boolean)
        .map(decodeURIComponent);
      const [head, id, ...rest] = segments;
      const discovered = discover(request, url, base, segments);
      if (discovered) return discovered;
      const tenant = await authenticate(request);
      if (head === "Me") {
        throw new ScimError(501, "/Me is not supported");
      }
      if (head === "Bulk") {
        throw new ScimError(501, "Bulk operations are not supported");
      }
      if (rest.length > 0) throw new ScimError(404, "Not a SCIM endpoint");
      if (head === "Users") {
        return await resource(request, url, base, "User", id, tenant);
      }
      if (head === "Groups") {
        return await resource(request, url, base, "Group", id, tenant);
      }
      throw new ScimError(404, "Not a SCIM endpoint");
    } catch (cause) {
      if (cause instanceof ScimError) return errorResponse(cause);
      return errorResponse(new ScimError(500, "The service provider failed"));
    }
  };
}
