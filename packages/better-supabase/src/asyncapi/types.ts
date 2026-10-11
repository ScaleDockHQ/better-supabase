import type { SPEC_PINS } from "../core/spec-pins.ts";

type Json = Record<string, unknown>;

/** The AsyncAPI versions `asyncapiFormat` renders. */
export type AsyncApiVersion = "3.0" | "3.1";

/** The file name `asyncapiFormat` writes; Arazzo source descriptions point at it. */
export const ASYNCAPI_FILE_NAME = "asyncapi.json";

export interface AsyncApiInfo {
  readonly title: string;
  readonly version: string;
  readonly description?: string;
  readonly termsOfService?: string;
  readonly contact?: {
    readonly name?: string;
    readonly url?: string;
    readonly email?: string;
  };
  readonly license?: { readonly name: string; readonly url?: string };
}

export interface AsyncApiComponents {
  readonly schemas?: Readonly<Record<string, Json>>;
  readonly messages?: Readonly<Record<string, Json>>;
  readonly messageTraits?: Readonly<Record<string, Json>>;
  readonly securitySchemes?: Readonly<Record<string, Json>>;
}

interface AsyncApiDocumentBase {
  readonly info: AsyncApiInfo;
  readonly defaultContentType: string;
  readonly servers?: Readonly<Record<string, Json>>;
  /** Channel id to Channel Object. */
  readonly channels: Readonly<Record<string, Json>>;
  /** Operation id to Operation Object. */
  readonly operations: Readonly<Record<string, Json>>;
  readonly components: AsyncApiComponents;
  readonly [extension: `x-${string}`]: unknown;
}

export interface AsyncApi30Document extends AsyncApiDocumentBase {
  readonly asyncapi: typeof SPEC_PINS.asyncapi30;
}

/** AsyncAPI 3.1 adds the `ros2` bindings; the rest matches 3.0. */
export interface AsyncApi31Document extends AsyncApiDocumentBase {
  readonly asyncapi: typeof SPEC_PINS.asyncapi31;
}

export interface AsyncApiDocuments {
  readonly "3.0": AsyncApi30Document;
  readonly "3.1": AsyncApi31Document;
}

export type AsyncApiDocument<V extends AsyncApiVersion = "3.0"> =
  AsyncApiDocuments[V];

export type AnyAsyncApiDocument = AsyncApiDocuments[AsyncApiVersion];

/** What an AsyncAPI `transform` receives, discriminated by `version`. */
export type RenderedAsyncApi = {
  readonly [V in AsyncApiVersion]: {
    readonly format: "asyncapi";
    readonly version: V;
    readonly document: AsyncApiDocuments[V];
  };
}[AsyncApiVersion];
