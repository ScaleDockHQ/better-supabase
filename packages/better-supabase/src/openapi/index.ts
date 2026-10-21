import type { DefineApiOptions, OverlayEngine } from "../spec/api.ts";
import type { SpecDiagnostic } from "../spec/format.ts";
import type { ApiSource } from "../spec/options.ts";
import type { ResourceDescription } from "../spec/resource.ts";
import type {
  OpenApiDocuments,
  OpenApiVersion,
  RenderedOpenApi,
} from "./types.ts";

import { defineApi } from "../spec/api.ts";

export type { ResourceOperation } from "../spec/model.ts";

export { PROBLEM_SCHEMA } from "../spec/presets.ts";

export { openapiFormat } from "./format.ts";

export { toOpenApi30Schema } from "./schema30.ts";

export type {
  AnyOpenApiDocument,
  OpenApi30Document,
  OpenApi31Document,
  OpenApi32Document,
  OpenApi33PreviewDocument,
  OpenApiComponents,
  OpenApiDocument,
  OpenApiDocuments,
  OpenApiInfo,
  OpenApiSecurityRequirement,
  OpenApiVersion,
  RenderedOpenApi,
} from "./types.ts";

export { OPENAPI_33_PREVIEW_VERSION } from "./types.ts";

/** How one table is published; see `defineApi`'s `resources`. */
export type ResourceOptions<Ref = string> = ResourceDescription<Ref>;

export interface OpenApiOptions<
  V extends OpenApiVersion = "3.1",
  Ref = string,
> extends DefineApiOptions<Ref> {
  /** Defaults to 3.1. `3.3-preview` follows a draft. */
  readonly version?: V;
  /** Last change to the document before overlays; see `RenderOptions.transform`. */
  readonly transform?: (
    rendered: Extract<RenderedOpenApi, { readonly version: V }>,
  ) => OpenApiDocuments[OpenApiVersion] | undefined;
  readonly overlays?: readonly unknown[];
  /** Hears every warning and info finding. Errors throw. */
  readonly onDiagnostic?: (diagnostic: SpecDiagnostic) => void;
}

/**
 * An OpenAPI document for REST resources over your tables, with schemas from
 * the generated metadata, list-query parameters, Supabase security schemes and
 * Problem Details errors. Throws when building or checking the document finds
 * an error; use `defineApi` to read every finding instead.
 *
 * ```ts
 * const doc = createOpenApi(betterSupabase, {
 *   info: { title: "CRM API", version: "1.0.0" },
 *   resources: {
 *     customers: { list: customerList },
 *     notes: { operations: ["list", "get"] },
 *   },
 * });
 * ```
 */
export function createOpenApi<V extends OpenApiVersion = "3.1", Ref = string>(
  betterSupabase: ApiSource,
  options: OpenApiOptions<V, Ref>,
): OpenApiDocuments[V] {
  const { version, transform, overlays, onDiagnostic, ...apiOptions } = options;
  const api = defineApi(betterSupabase, apiOptions);
  const engine: OverlayEngine | undefined = options.applyOverlays;

  const result = api.openapi<V>({
    ...(version === undefined ? {} : { version }),
    ...(transform === undefined ? {} : { transform }),
    ...(overlays === undefined ? {} : { overlays }),
    ...(engine === undefined ? {} : { applyOverlays: engine }),
  });

  const errors = result.diagnostics.filter(
    (diagnostic) => diagnostic.severity === "error",
  );

  if (errors.length > 0) {
    throw new TypeError(
      `createOpenApi: ${errors
        .map(
          (error) =>
            `${error.code}: ${error.message}${error.pointer ? ` (${error.pointer})` : ""}`,
        )
        .join("; ")}`,
    );
  }

  if (onDiagnostic) {
    for (const diagnostic of result.diagnostics) {
      onDiagnostic(diagnostic);
    }
  }

  return result.document;
}
