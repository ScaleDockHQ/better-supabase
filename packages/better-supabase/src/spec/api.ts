import type {
  OpenApiDocuments,
  OpenApiVersion,
  RenderedOpenApi,
} from "../openapi/types.ts";
import type {
  AnyDocumentFormat,
  DocumentOf,
  RenderedOf,
  SpecDiagnostic,
  VersionOf,
} from "./format.ts";
import type { ApiModel } from "./model.ts";
import type { ApiOptions, ApiSource } from "./options.ts";

import { openapiFormat } from "../openapi/format.ts";
import { buildApiModel } from "./build.ts";

/**
 * Applies Overlay documents in order to a rendered document and reports what it
 * found. `better-supabase/overlay` provides one: `(doc, overlays) =>
 * applyOverlays(doc, overlays, { jsonpath })`.
 */
export type OverlayEngine = (
  document: unknown,
  overlays: readonly unknown[],
) => {
  readonly document: unknown;
  readonly diagnostics?: readonly SpecDiagnostic[];
};

export interface RenderOptions<F extends AnyDocumentFormat> {
  /** Defaults to the format's default version. */
  readonly version?: VersionOf<F>;
  /**
   * Last change to the lowered document, before overlays. It receives a copy,
   * typed per version; return a replacement or change it in place.
   */
  readonly transform?: (rendered: RenderedOf<F>) => DocumentOf<F> | undefined;
  readonly overlays?: readonly unknown[];
  /** Overrides the API's `applyOverlays`. */
  readonly applyOverlays?: OverlayEngine;
}

export interface RenderResult<F extends AnyDocumentFormat> {
  readonly format: F["id"];
  readonly version: VersionOf<F>;
  readonly document: DocumentOf<F>;
  /** Building, lowering, overlay and lint findings, without duplicates. */
  readonly diagnostics: readonly SpecDiagnostic[];
  readonly fileName: string;
}

export interface OpenApiRenderOptions<V extends OpenApiVersion> {
  readonly version?: V;
  readonly transform?: (
    rendered: Extract<RenderedOpenApi, { readonly version: V }>,
  ) => OpenApiDocuments[OpenApiVersion] | undefined;
  readonly overlays?: readonly unknown[];
  readonly applyOverlays?: OverlayEngine;
}

export interface OpenApiRenderResult<V extends OpenApiVersion> {
  readonly format: "openapi";
  readonly version: V;
  readonly document: OpenApiDocuments[V];
  readonly diagnostics: readonly SpecDiagnostic[];
  readonly fileName: string;
}

export interface DefineApiOptions<Ref = string> extends ApiOptions<Ref> {
  /** The default overlay engine for `overlays` in `render`. */
  readonly applyOverlays?: OverlayEngine;
}

export interface Api {
  readonly model: ApiModel;
  /** Findings while building the model. */
  readonly diagnostics: readonly SpecDiagnostic[];
  /**
   * Lowers the model to a version of any `DocumentFormat`, then runs
   * `transform`, overlays and the format's lint.
   */
  render<F extends AnyDocumentFormat>(
    format: F,
    options?: RenderOptions<F>,
  ): RenderResult<F>;
  /** `render(openapiFormat, options)`, typed per version. Defaults to 3.1. */
  openapi<V extends OpenApiVersion = "3.1">(
    options?: OpenApiRenderOptions<V>,
  ): OpenApiRenderResult<V>;
}

function dedupe(diagnostics: readonly SpecDiagnostic[]): SpecDiagnostic[] {
  const seen = new Set<string>();

  return diagnostics.filter((diagnostic) => {
    const key = `${diagnostic.code}\u0000${diagnostic.pointer ?? ""}\u0000${diagnostic.message}`;

    if (seen.has(key)) {
      return false;
    }

    seen.add(key);

    return true;
  });
}

interface Lowered {
  readonly document: unknown;
  readonly diagnostics: readonly SpecDiagnostic[];
}

/**
 * The API model for a `defineSupabase()` result, and the documents it renders.
 * The model is built once per options object; each format and version is
 * lowered once and copied for every render.
 *
 * ```ts
 * const api = defineApi(betterSupabase, {
 *   info: { title: "CRM API", version: "1.0.0" },
 *   resources: { customers: { list: customerList } },
 * });
 * const { document } = api.openapi({ version: "3.2" });
 * ```
 */
export function defineApi<Ref = string>(
  source: ApiSource,
  options: DefineApiOptions<Ref>,
): Api {
  const built = buildApiModel(source, options);
  const lowered = new WeakMap<AnyDocumentFormat, Map<string, Lowered>>();

  const lower = (format: AnyDocumentFormat, version: string): Lowered => {
    let byVersion = lowered.get(format);

    if (!byVersion) {
      byVersion = new Map();
      lowered.set(format, byVersion);
    }

    let hit = byVersion.get(version);

    if (!hit) {
      const diagnostics: SpecDiagnostic[] = [];

      const document: unknown = format.lower(built.model, version, {
        report: (diagnostic) => {
          diagnostics.push(diagnostic);
        },
      });

      hit = { document, diagnostics };
      byVersion.set(version, hit);
    }

    return hit;
  };

  const render = <F extends AnyDocumentFormat>(
    format: F,
    renderOptions: RenderOptions<F> = {},
  ): RenderResult<F> => {
    // oxlint-disable-next-line typescript/no-unsafe-assignment -- AnyDocumentFormat types the default as `any`; VersionOf<F> is its real type
    const fallback: VersionOf<F> = format.defaultVersion;
    const version = renderOptions.version ?? fallback;
    const status = format.versions[version];

    if (!status) {
      throw new TypeError(
        `Document format "${format.id}" has no version "${String(version)}"`,
      );
    }

    const diagnostics: SpecDiagnostic[] = [...built.diagnostics];

    if (status.status === "preview") {
      diagnostics.push({
        code: "preview-version",
        severity: "warning",
        message: `${format.id} ${String(version)} follows a draft (${status.pin}); its fields may change before release`,
      });
    }

    const base = lower(format, version);
    diagnostics.push(...base.diagnostics);
    let document: unknown = structuredClone(base.document);

    if (renderOptions.transform) {
      // SAFETY: lower() returned the document of this format and version,
      // which is what RenderedOf<F> pairs with the version.
      const rendered = {
        format: format.id,
        version,
        document,
      } as RenderedOf<F>;

      document = renderOptions.transform(rendered) ?? document;
    }

    const overlays = renderOptions.overlays ?? [];

    if (overlays.length > 0) {
      const engine = renderOptions.applyOverlays ?? options.applyOverlays;

      if (!engine) {
        throw new TypeError(
          "better-supabase/spec: overlays need applyOverlays (from better-supabase/overlay)",
        );
      }

      const result = engine(document, overlays);
      document = result.document;
      diagnostics.push(...(result.diagnostics ?? []));
    }

    diagnostics.push(...(format.lint?.(document, version) ?? []));

    return {
      format: format.id,
      version,
      // SAFETY: the document came from this format's lower(), a transform
      // typed to return the format's document, or overlays that keep its shape.
      document: document as DocumentOf<F>,
      diagnostics: dedupe(diagnostics),
      fileName: format.fileName(version),
    };
  };

  return {
    model: built.model,
    diagnostics: built.diagnostics,
    render,
    openapi<V extends OpenApiVersion = "3.1">(
      openapiOptions: OpenApiRenderOptions<V> = {},
    ): OpenApiRenderResult<V> {
      const { transform, version, overlays, applyOverlays } = openapiOptions;

      const renderOptions: RenderOptions<typeof openapiFormat> = {
        ...(version === undefined ? {} : { version }),
        ...(overlays === undefined ? {} : { overlays }),
        ...(applyOverlays === undefined ? {} : { applyOverlays }),
        ...(transform === undefined
          ? {}
          : {
              transform: (rendered: RenderedOf<typeof openapiFormat>) =>
                // SAFETY: render() lowers the requested version V, so the
                // rendered document is the member of the union for V.
                transform(
                  rendered as Extract<RenderedOpenApi, { readonly version: V }>,
                ),
            }),
      };

      const result = render(openapiFormat, renderOptions);

      return {
        format: "openapi",
        // SAFETY: render() uses the requested version, or 3.1 when V is the default.
        version: result.version as V,
        // SAFETY: openapiFormat.lower(model, V) returns OpenApiDocuments[V].
        document: result.document as OpenApiDocuments[V],
        diagnostics: result.diagnostics,
        fileName: result.fileName,
      };
    },
  };
}
