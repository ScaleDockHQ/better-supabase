import type { SPEC_PINS } from "../core/spec-pins.ts";

type Json = Record<string, unknown>;

/** The Arazzo versions `arazzoFormat` renders. */
export type ArazzoVersion = "1.0" | "1.1";

/** A document the workflows call: the emitted OpenAPI or AsyncAPI file. */
export interface ArazzoSourceDescription {
  readonly name: string;
  readonly url: string;
  readonly type: "openapi" | "asyncapi" | "arazzo";
}

export interface ArazzoInfo {
  readonly title: string;
  readonly version: string;
  readonly summary?: string;
  readonly description?: string;
}

export interface ArazzoStep {
  readonly stepId: string;
  readonly description?: string;
  readonly operationId?: string;
  readonly operationPath?: string;
  /** Arazzo 1.1: a JSON Pointer to an AsyncAPI channel. */
  readonly channelPath?: string;
  readonly workflowId?: string;
  /** Arazzo 1.1, AsyncAPI steps only. */
  readonly action?: "send" | "receive";
  /** Arazzo 1.1, AsyncAPI receive steps only. */
  readonly correlationId?: string;
  readonly parameters?: readonly Json[];
  readonly requestBody?: Json;
  readonly successCriteria?: readonly Json[];
  readonly onSuccess?: readonly Json[];
  readonly onFailure?: readonly Json[];
  readonly outputs?: Readonly<Record<string, string>>;
}

export interface ArazzoWorkflow {
  readonly workflowId: string;
  readonly summary?: string;
  readonly description?: string;
  readonly inputs?: Json;
  readonly steps: readonly ArazzoStep[];
  readonly outputs?: Readonly<Record<string, string>>;
}

interface ArazzoDocumentBase {
  readonly info: ArazzoInfo;
  readonly sourceDescriptions: readonly ArazzoSourceDescription[];
  readonly workflows: readonly ArazzoWorkflow[];
  readonly components?: Json;
  readonly [extension: `x-${string}`]: unknown;
}

export interface Arazzo10Document extends ArazzoDocumentBase {
  readonly arazzo: typeof SPEC_PINS.arazzo10;
}

/** Arazzo 1.1 adds AsyncAPI steps, action parameters and `querystring`. */
export interface Arazzo11Document extends ArazzoDocumentBase {
  readonly arazzo: typeof SPEC_PINS.arazzo11;
  readonly $self?: string;
}

export interface ArazzoDocuments {
  readonly "1.0": Arazzo10Document;
  readonly "1.1": Arazzo11Document;
}

export type ArazzoDocument<V extends ArazzoVersion = "1.0"> =
  ArazzoDocuments[V];

export type AnyArazzoDocument = ArazzoDocuments[ArazzoVersion];

/** What an Arazzo `transform` receives, discriminated by `version`. */
export type RenderedArazzo = {
  readonly [V in ArazzoVersion]: {
    readonly format: "arazzo";
    readonly version: V;
    readonly document: ArazzoDocuments[V];
  };
}[ArazzoVersion];
