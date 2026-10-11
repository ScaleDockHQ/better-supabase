import type { ApiModel } from "./model.ts";

/** How a version of a format is supported. `preview` follows a draft and is never a default. */
export type VersionStatus = "stable" | "legacy" | "preview";

export interface FormatVersion {
  /** The exact version or commit the output follows (a `SPEC_PINS` value). */
  readonly pin: string;
  readonly status: VersionStatus;
}

export type DiagnosticSeverity = "error" | "warning" | "info";

/**
 * A finding from building, lowering or checking a document. `code` is
 * stable: tools and `--fail-on` read it, and a retired code stays reserved.
 */
export interface SpecDiagnostic {
  readonly code: string;
  readonly severity: DiagnosticSeverity;
  readonly message: string;
  /** A JSON Pointer into the document or the model, when there is one. */
  readonly pointer?: string;
}

export interface LowerContext {
  /** Records a diagnostic; lowering continues. */
  report(diagnostic: SpecDiagnostic): void;
}

/**
 * The plugin contract every document format implements, the first-party
 * ones included (API v1). `lower` is pure: it reads the model and returns a
 * new document, so the same model renders to every version. `Docs` maps
 * each version to its document type, so `transform` hooks can switch on the
 * version; it defaults to `Doc` for every version.
 */
export interface DocumentFormat<
  Id extends string = string,
  V extends string = string,
  Doc = unknown,
  Docs extends Readonly<Record<V, Doc>> = Readonly<Record<V, Doc>>,
> {
  readonly apiVersion: 1;
  readonly id: Id;
  readonly versions: Readonly<Record<V, FormatVersion>>;
  readonly defaultVersion: V;
  lower(model: ApiModel, version: V, ctx: LowerContext): Doc;
  /** Semantic checks a schema cannot express (unique ids, resolvable references). */
  lint?(doc: Doc, version: V): readonly SpecDiagnostic[];
  /** Default file name for a version, e.g. `openapi.json`. */
  fileName(version: V): string;
  /** Phantom carrying the per-version document types. */
  readonly "~documents"?: Docs;
}

// oxlint-disable-next-line typescript/no-explicit-any -- the version and document types are invariant in lower(), so `unknown` would reject typed formats
export type AnyDocumentFormat = DocumentFormat<string, any, any, any>;

export type VersionOf<F> =
  F extends DocumentFormat<string, infer V> ? V : never;
export type DocumentOf<F> =
  // oxlint-disable-next-line typescript/no-explicit-any -- see AnyDocumentFormat
  F extends DocumentFormat<string, any, infer D, any> ? D : never;

/**
 * What a `transform` hook receives: the document with its format and
 * version, a union discriminated by `version`.
 */
export type RenderedOf<F> =
  // oxlint-disable-next-line typescript/no-explicit-any -- see AnyDocumentFormat
  F extends DocumentFormat<infer Id, infer V, any, infer Docs>
    ? {
        [K in V]: {
          readonly format: Id;
          readonly version: K;
          readonly document: K extends keyof Docs ? Docs[K] : never;
        };
      }[V]
    : never;

/** Identity helper that fixes `apiVersion` and checks that the default version exists. */
export function defineDocumentFormat<
  const Id extends string,
  const V extends string,
  Doc,
  Docs extends Readonly<Record<V, Doc>> = Readonly<Record<V, Doc>>,
>(format: {
  readonly apiVersion?: 1;
  readonly id: Id;
  readonly versions: Readonly<Record<V, FormatVersion>>;
  readonly defaultVersion: NoInfer<V>;
  lower(model: ApiModel, version: NoInfer<V>, ctx: LowerContext): Doc;
  lint?(doc: Doc, version: NoInfer<V>): readonly SpecDiagnostic[];
  fileName(version: NoInfer<V>): string;
  readonly "~documents"?: Docs;
}): DocumentFormat<Id, V, Doc, Docs> {
  if (!Object.hasOwn(format.versions, format.defaultVersion)) {
    throw new TypeError(
      `Document format "${format.id}": the default version "${format.defaultVersion}" is not in versions`,
    );
  }
  if (format.versions[format.defaultVersion].status === "preview") {
    throw new TypeError(
      `Document format "${format.id}": a preview version cannot be the default`,
    );
  }
  return { ...format, apiVersion: 1 };
}
