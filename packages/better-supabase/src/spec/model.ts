/** A JSON Schema (2020-12) object. Model schemas reference components as `#/components/schemas/<Name>`. */
export type JsonSchema = Readonly<Record<string, unknown>>;

/** A JSON object, for extensions and free-form fields. */
export type JsonObject = Readonly<Record<string, unknown>>;

export type ResourceOperation = "list" | "get" | "create" | "update" | "delete";

/** HTTP methods an operation can use; `query` is an OpenAPI 3.2 method. */
export type HttpMethod =
  | "get"
  | "put"
  | "post"
  | "patch"
  | "delete"
  | "head"
  | "options"
  | "trace"
  | "query";

export interface ModelParameter {
  readonly name: string;
  readonly in: "path" | "query" | "header" | "cookie";
  readonly required?: boolean;
  readonly description?: string;
  readonly deprecated?: boolean;
  readonly schema: JsonSchema;
  /** How an array or object query value is written (`form` for `a,b`). */
  readonly style?: string;
  readonly explode?: boolean;
}

/** A named example of a media type. */
export interface ModelExample {
  readonly summary?: string;
  readonly description?: string;
  readonly value: unknown;
}

/** Media type to its schema. `itemSchema` describes each item of a stream (SSE, JSON Lines). */
export interface ModelContent {
  readonly schema?: JsonSchema;
  readonly itemSchema?: JsonSchema;
  readonly examples?: Readonly<Record<string, ModelExample>>;
}

export interface ModelBody {
  readonly required: boolean;
  readonly description?: string;
  readonly content: Readonly<Record<string, ModelContent>>;
}

export interface ModelResponse {
  readonly description: string;
  /** Short summary; native in OpenAPI 3.2. */
  readonly summary?: string;
  readonly content?: Readonly<Record<string, ModelContent>>;
  readonly headers?: Readonly<
    Record<
      string,
      { readonly description?: string; readonly schema: JsonSchema }
    >
  >;
}

/** A response, or the name of a shared one in `ApiModel.responses`. */
export type ModelResponseOrRef = ModelResponse | { readonly ref: string };

/** Scheme name to its required scopes. `[]` means no scopes. */
export type SecurityRequirement = Readonly<Record<string, readonly string[]>>;

/** Where an operation comes from, so tools and adapters can find their own. */
export type OperationSource =
  | {
      readonly kind: "resource";
      readonly table: string;
      readonly operation: ResourceOperation;
    }
  | {
      readonly kind: "action";
      readonly table: string;
      readonly action: string;
    }
  | { readonly kind: "route" }
  | { readonly kind: "fragment" };

export interface ModelOperation {
  /** The operationId: unique across the model. */
  readonly id: string;
  readonly method: HttpMethod;
  /** The OpenAPI path template, e.g. `/api/customers/{id}`. */
  readonly path: string;
  readonly summary?: string;
  readonly description?: string;
  readonly tags: readonly string[];
  readonly deprecated?: boolean;
  readonly parameters: readonly ModelParameter[];
  readonly requestBody?: ModelBody;
  readonly responses: Readonly<Record<string, ModelResponseOrRef>>;
  /** Overrides the model's `security`; `[]` makes the operation public. */
  readonly security?: readonly SecurityRequirement[];
  /** The permission key the authorizer checks, from `Authorizer.key()`. */
  readonly permission?: string;
  readonly source: OperationSource;
  /** `x-` fields, with their prefix. */
  readonly extensions: JsonObject;
  /**
   * Deep-merged into the operation object a format renders (OpenAPI), after
   * the fragments, so it wins over both the generated fields and fragments.
   */
  readonly extend?: JsonObject;
}

export interface ModelTag {
  readonly name: string;
  readonly summary?: string;
  readonly description?: string;
  /** The parent tag's name (OpenAPI 3.2 nested tags). */
  readonly parent?: string;
  /** `nav`, `badge` or another value from the OAI Tag Kind registry. */
  readonly kind?: string;
}

export interface ModelServer {
  readonly url: string;
  /** Native in OpenAPI 3.2. */
  readonly name?: string;
  readonly description?: string;
}

export interface OAuthFlow {
  readonly authorizationUrl?: string;
  readonly tokenUrl?: string;
  readonly refreshUrl?: string;
  readonly scopes: Readonly<Record<string, string>>;
}

export type ModelSecurityScheme =
  | {
      readonly type: "http";
      readonly scheme: string;
      readonly bearerFormat?: string;
      readonly description?: string;
    }
  | {
      readonly type: "apiKey";
      readonly name: string;
      readonly in: "header" | "query" | "cookie";
      readonly description?: string;
    }
  | {
      readonly type: "oauth2";
      readonly description?: string;
      readonly flows: {
        readonly authorizationCode?: OAuthFlow;
        readonly clientCredentials?: OAuthFlow;
        readonly implicit?: OAuthFlow;
        readonly password?: OAuthFlow;
      };
      /** RFC 8414 metadata URL; native in OpenAPI 3.2. */
      readonly metadataUrl?: string;
    }
  | {
      readonly type: "openIdConnect";
      readonly openIdConnectUrl: string;
      readonly description?: string;
    }
  | {
      /** The Security Profiles proposal; only `3.3-preview` emits it. */
      readonly type: "profile";
      readonly description?: string;
      readonly profileMetadata: {
        readonly profile: string;
        readonly parametersSchema?: string;
        readonly authorizationServer?: string;
        readonly servers?: readonly string[];
      };
    };

/** A Security Profile Requirement (Security Profiles proposal, preview only). */
export interface ModelSecurityProfileRequirement {
  readonly scheme: string;
  readonly operation?: string;
  readonly tokenEndpointAuthMethods?: readonly string[];
  readonly grantTypes?: readonly string[];
  readonly scopes?: readonly string[];
}

export interface ModelMessage {
  readonly id: string;
  readonly name?: string;
  readonly title?: string;
  readonly summary?: string;
  readonly description?: string;
  readonly contentType?: string;
  readonly payload: JsonSchema;
  readonly headers?: JsonSchema;
  /** A runtime expression such as `$message.payload#/id`. */
  readonly correlationId?: string;
  readonly extensions?: JsonObject;
}

export interface ModelChannelOperation {
  readonly id: string;
  readonly action: "send" | "receive";
  readonly summary?: string;
  readonly description?: string;
  /** Message ids, a subset of the channel's. */
  readonly messages?: readonly string[];
  readonly permission?: string;
  readonly extensions?: JsonObject;
}

export interface ModelChannel {
  readonly id: string;
  /** The address with `{param}` placeholders, e.g. `bs:t:{schema}.{table}`. */
  readonly address: string;
  readonly title?: string;
  readonly summary?: string;
  readonly description?: string;
  readonly parameters?: Readonly<
    Record<string, { readonly description?: string }>
  >;
  /** The protocol the channel runs on: `ws` (Realtime) or `http` (webhooks). */
  readonly protocol: "ws" | "http";
  readonly messages: readonly string[];
  readonly operations: readonly ModelChannelOperation[];
  readonly extensions?: JsonObject;
}

export interface ModelWebhook {
  /** The event name, e.g. `invoice.paid`. */
  readonly id: string;
  readonly summary?: string;
  readonly description?: string;
  readonly payload: JsonSchema;
  /** Standard Webhooks headers (`webhook-id`, `webhook-timestamp`, `webhook-signature`). */
  readonly standardWebhooks: boolean;
}

/** A step calls an operation by id or sends or receives on a channel (Arazzo 1.1). */
export interface ModelStep {
  readonly id: string;
  readonly description?: string;
  readonly operationId?: string;
  readonly channel?: {
    readonly id: string;
    readonly action: "send" | "receive";
    readonly correlationId?: string;
  };
  readonly workflowId?: string;
  readonly parameters?: readonly {
    readonly name: string;
    readonly in?: "path" | "query" | "header" | "cookie";
    readonly value: unknown;
  }[];
  readonly requestBody?: { readonly payload: unknown };
  readonly successCriteria?: readonly { readonly condition: string }[];
  readonly outputs?: Readonly<Record<string, string>>;
  readonly onSuccess?: readonly JsonObject[];
  readonly onFailure?: readonly JsonObject[];
}

export interface ModelWorkflow {
  readonly id: string;
  readonly summary?: string;
  readonly description?: string;
  readonly inputs?: JsonSchema;
  readonly steps: readonly ModelStep[];
  readonly outputs?: Readonly<Record<string, string>>;
}

export interface ModelInfo {
  readonly title: string;
  readonly version: string;
  readonly summary?: string;
  readonly description?: string;
  readonly termsOfService?: string;
  readonly contact?: {
    readonly name?: string;
    readonly url?: string;
    readonly email?: string;
  };
  readonly license?: {
    readonly name: string;
    readonly identifier?: string;
    readonly url?: string;
  };
}

/**
 * A version-neutral description of the API. `defineApi` builds it once; each
 * `DocumentFormat` lowers it to one version of its format. Formats never
 * mutate it.
 */
export interface ApiModel {
  readonly info: ModelInfo;
  /** The document's own URL (`$self` in OpenAPI 3.2). */
  readonly self?: string;
  readonly servers: readonly ModelServer[];
  readonly tags: readonly ModelTag[];
  readonly operations: readonly ModelOperation[];
  readonly schemas: Readonly<Record<string, JsonSchema>>;
  /** Shared responses, referenced by name from operations. */
  readonly responses: Readonly<Record<string, ModelResponse>>;
  readonly securitySchemes: Readonly<Record<string, ModelSecurityScheme>>;
  readonly security: readonly SecurityRequirement[];
  readonly securityProfileRequirements?: Readonly<
    Record<string, ModelSecurityProfileRequirement>
  >;
  readonly channels: readonly ModelChannel[];
  readonly messages: Readonly<Record<string, ModelMessage>>;
  readonly webhooks: readonly ModelWebhook[];
  readonly workflows: readonly ModelWorkflow[];
  /**
   * OpenAPI fragments (parsed YAML or JSON), deep-merged over the generated
   * document in order. A field they change is reported as `fragment-conflict`.
   */
  readonly fragments: readonly JsonObject[];
  /** The Realtime websocket URL, the AsyncAPI server. */
  readonly realtimeUrl?: string;
  /** Prefix of the generated `x-` fields. Defaults to `x-better-supabase-`. */
  readonly extensionPrefix: string;
}
