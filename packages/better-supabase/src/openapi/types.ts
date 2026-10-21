import type { SPEC_PINS } from "../core/spec-pins.ts";

type Json = Record<string, unknown>;

/**
 * The OpenAPI versions `openapiFormat` renders. `3.3-preview` follows the
 * v3.3-dev branch.
 */
export type OpenApiVersion = "3.0" | "3.1" | "3.2" | "3.3-preview";

/** The `openapi` field `3.3-preview` emits, as in the v3.3-dev branch. */
export const OPENAPI_33_PREVIEW_VERSION = "3.3.0";

/** The file name `openapiFormat` writes for every version. */
export const OPENAPI_FILE_NAME = "openapi.json";

export interface OpenApiInfo {
  readonly title: string;
  readonly version: string;
  /** OpenAPI 3.1 and later. */
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
    /** OpenAPI 3.1 and later. */
    readonly identifier?: string;
    readonly url?: string;
  };
}

export type OpenApiSecurityRequirement = Readonly<
  Record<string, readonly string[]>
>;

export type OpenApiComponents = {
  readonly schemas: Readonly<Record<string, Json>>;
  readonly responses: Readonly<Record<string, Json>>;
  readonly securitySchemes: Readonly<Record<string, Json>>;
};

interface OpenApiDocumentBase {
  readonly info: OpenApiInfo;
  readonly servers?: readonly Json[];
  readonly tags: readonly Json[];
  /** Path templates to Path Item objects. */
  readonly paths: Readonly<Record<string, Json>>;
  readonly components: OpenApiComponents;
  readonly security: readonly OpenApiSecurityRequirement[];
  readonly [extension: `x-${string}`]: unknown;
}

/** OpenAPI 3.0 (legacy): schemas use `nullable` and `example`, no webhooks. */
export interface OpenApi30Document extends OpenApiDocumentBase {
  readonly openapi: typeof SPEC_PINS.openapi30;
}

/** OpenAPI 3.1: 3.2 fields travel as the registered `x-oai-*` extensions. */
export interface OpenApi31Document extends OpenApiDocumentBase {
  readonly openapi: typeof SPEC_PINS.openapi31;
  readonly jsonSchemaDialect: string;
  readonly webhooks?: Readonly<Record<string, Json>>;
}

/**
 * OpenAPI 3.2: native `$self`, nested tags, `itemSchema`, `oauth2MetadataUrl`
 * and `query`.
 */
export interface OpenApi32Document extends OpenApiDocumentBase {
  readonly openapi: typeof SPEC_PINS.openapi32;
  readonly $self?: string;
  readonly jsonSchemaDialect: string;
  readonly webhooks?: Readonly<Record<string, Json>>;
}

/**
 * The 3.3 draft: 3.2 plus Path Item `security` and the Security Profiles
 * proposal.
 */
export interface OpenApi33PreviewDocument extends OpenApiDocumentBase {
  readonly openapi: typeof OPENAPI_33_PREVIEW_VERSION;
  readonly $self?: string;
  readonly jsonSchemaDialect: string;
  readonly webhooks?: Readonly<Record<string, Json>>;
  readonly components: OpenApiComponents & {
    readonly securityProfileRequirements?: Readonly<Record<string, Json>>;
  };
}

export interface OpenApiDocuments {
  readonly "3.0": OpenApi30Document;
  readonly "3.1": OpenApi31Document;
  readonly "3.2": OpenApi32Document;
  readonly "3.3-preview": OpenApi33PreviewDocument;
}

/** An OpenAPI document of one version; 3.1 by default. */
export type OpenApiDocument<V extends OpenApiVersion = "3.1"> =
  OpenApiDocuments[V];

export type AnyOpenApiDocument = OpenApiDocuments[OpenApiVersion];

/** What an OpenAPI `transform` receives, discriminated by `version`. */
export type RenderedOpenApi = {
  readonly [V in OpenApiVersion]: {
    readonly format: "openapi";
    readonly version: V;
    readonly document: OpenApiDocuments[V];
  };
}[OpenApiVersion];
