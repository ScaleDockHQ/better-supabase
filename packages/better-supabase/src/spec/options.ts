import type { Authorizer } from "../core/authorizer.ts";
import type { AnyPlugin } from "../core/plugin.ts";
import type { SchemaMeta } from "../schema/types.ts";
import type { SpecDiagnostic } from "./format.ts";
import type {
  ApiModel,
  HttpMethod,
  JsonObject,
  JsonSchema,
  ModelChannel,
  ModelInfo,
  ModelMessage,
  ModelOperation,
  ModelSecurityProfileRequirement,
  ModelServer,
  ModelTag,
  ModelWebhook,
  ModelWorkflow,
  OperationSource,
  SecurityRequirement,
} from "./model.ts";
import type { SecurityPreset } from "./presets.ts";
import type {
  ErrorResponse,
  ResourceDescription,
  ResourcePlan,
} from "./resource.ts";
import type { StandardLike } from "./schemas.ts";

/** What `defineApi` reads from a `defineSupabase()` result. */
export interface ApiSource {
  readonly meta: SchemaMeta;
  readonly plugins?: readonly AnyPlugin[];
}

/** A resource: its description, `true` for the defaults, or a handler that carries its plan. */
export type ResourceInput<Ref = string> =
  | ResourceDescription<Ref>
  | true
  | { readonly plan: ResourcePlan<Ref> };

/** A custom route, documented from its Standard Schemas (Standard JSON Schema). */
export interface RouteSpec<Ref = string> {
  readonly method: HttpMethod | Uppercase<HttpMethod>;
  /** Relative to `basePath`, with `{name}` path parameters. */
  readonly path: string;
  readonly operationId?: string;
  readonly summary?: string;
  readonly description?: string;
  readonly tags?: readonly string[];
  readonly deprecated?: boolean;
  /** The path parameters, as an object schema. Unlisted ones are strings. */
  readonly params?: StandardLike;
  /** The query parameters, as an object schema. */
  readonly query?: StandardLike;
  /** The JSON body. */
  readonly input?: StandardLike;
  /** The JSON response. Without it (and without `stream`) the route answers 204. */
  readonly output?: StandardLike;
  /** A stream response: each item's schema (`itemSchema`), by default as `text/event-stream`. */
  readonly stream?: {
    readonly item: StandardLike;
    readonly contentType?: string;
  };
  /** Success status. Defaults to 200 with an output or stream, 204 without. */
  readonly status?: number;
  /** Overrides the API's security; `[]` makes the route public. */
  readonly security?: readonly SecurityRequirement[];
  readonly permission?: Ref;
  /** The shared error responses. Defaults to the API's `errors`. */
  readonly errors?: readonly ErrorResponse[];
  /** Deep-merged into the rendered operation. */
  readonly extend?: JsonObject;
}

export interface OperationIdContext {
  readonly source: OperationSource;
  readonly method: HttpMethod;
  readonly path: string;
  /** The id better-supabase would use, e.g. `listCustomers`. */
  readonly defaultId: string;
}

export type ComponentNameContext =
  | {
      readonly kind: "table";
      readonly table: string;
      readonly variant: "Row" | "Insert" | "Update" | "Page";
      readonly defaultName: string;
    }
  | {
      readonly kind: "schema";
      /** The name from the schema's own `$id` or `id` metadata. */
      readonly id: string | undefined;
      readonly schema: JsonSchema;
      readonly role: "input" | "output" | "item";
      readonly operationId: string;
    };

/** Version-neutral hooks on the model. Return a replacement, or nothing to keep it. */
export interface EnrichHooks {
  readonly operation?: (
    operation: ModelOperation,
  ) => ModelOperation | undefined;
  readonly schema?: (
    schema: JsonSchema,
    context: { readonly name: string },
  ) => JsonSchema | undefined;
  readonly channel?: (channel: ModelChannel) => ModelChannel | undefined;
  readonly message?: (
    message: ModelMessage,
    context: { readonly id: string },
  ) => ModelMessage | undefined;
  readonly workflow?: (workflow: ModelWorkflow) => ModelWorkflow | undefined;
}

export interface ApiOptions<Ref = string> {
  readonly info: ModelInfo;
  /** The document's own URL (`$self`). */
  readonly self?: string;
  readonly servers?: readonly ModelServer[];
  /** Prefix for every path, e.g. `/api`. */
  readonly basePath?: string;
  /** Tags listed before the resource tags, with summaries and parents. */
  readonly tags?: readonly ModelTag[];
  /** Tables to publish, by app key. */
  readonly resources?: Readonly<Record<string, ResourceInput<Ref>>>;
  readonly routes?: readonly RouteSpec<Ref>[];
  /** Parsed OpenAPI fragments, merged over the generated document. */
  readonly fragments?: readonly JsonObject[];
  /** Defaults to `['bearer']`. */
  readonly security?: readonly SecurityPreset[];
  /** The project URL, for the `oauth2` preset. */
  readonly supabaseUrl?: string;
  /** Shared error responses. Defaults to `DEFAULT_ERRORS`. */
  readonly errors?: readonly ErrorResponse[];
  readonly operationId?: (context: OperationIdContext) => string;
  /** Names a component; `undefined` keeps the default (tables) or inlines it (schemas). */
  readonly componentName?: (
    context: ComponentNameContext,
  ) => string | undefined;
  /** Prefix of generated `x-` fields. Defaults to `x-better-supabase-`. */
  readonly extensionPrefix?: string;
  /** Example rows per table (app-cased), set as the Row schema's `examples`. */
  readonly examples?: Readonly<Record<string, readonly JsonObject[]>>;
  readonly enrich?: EnrichHooks;
  /** Resolves permission references to keys (`key()`) and `permissions: true`. */
  readonly authorizer?: Authorizer<Ref>;
  /** Report `permission-missing` for writes that declare no permission. */
  readonly requirePermissions?: boolean;
  /** `keys`: each permission key is also an OAuth scope of the `oauth2` preset. */
  readonly permissionScopes?: "keys";
  /** Security Profile Requirements (preview; only `3.3-preview` renders them). */
  readonly securityProfileRequirements?: Readonly<
    Record<string, ModelSecurityProfileRequirement>
  >;
  /** The Realtime websocket URL, for AsyncAPI. */
  readonly realtimeUrl?: string;
  readonly channels?: readonly ModelChannel[];
  readonly messages?: Readonly<Record<string, ModelMessage>>;
  readonly webhooks?: readonly ModelWebhook[];
  readonly workflows?: readonly ModelWorkflow[];
  /** Tables with a JSON column typed in `better-supabase.config.ts`. */
  readonly json?: Readonly<Record<string, unknown>>;
}

export interface BuiltModel {
  readonly model: ApiModel;
  /** Findings while building: permissions, components, schemas, plugins. */
  readonly diagnostics: readonly SpecDiagnostic[];
}
