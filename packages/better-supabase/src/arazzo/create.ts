import type { DefineApiOptions } from "../spec/api.ts";
import type { SpecDiagnostic } from "../spec/format.ts";
import type { ApiSource } from "../spec/options.ts";
import type { ArazzoFormatOptions } from "./format.ts";
import type {
  AnyArazzoDocument,
  ArazzoDocuments,
  ArazzoVersion,
  RenderedArazzo,
} from "./types.ts";

import { defineApi } from "../spec/api.ts";
import { createArazzoFormat } from "./format.ts";

export interface ArazzoOptions<V extends ArazzoVersion = "1.0", Ref = string>
  extends DefineApiOptions<Ref>, ArazzoFormatOptions {
  /** Defaults to 1.0; channel steps and action parameters need 1.1. */
  readonly version?: V;
  /** Last change to the document before overlays; it receives a copy. */
  readonly transform?: (
    rendered: Extract<RenderedArazzo, { readonly version: V }>,
  ) => AnyArazzoDocument | undefined;
  readonly overlays?: readonly unknown[];
  /** Hears every warning and info finding. Errors throw. */
  readonly onDiagnostic?: (diagnostic: SpecDiagnostic) => void;
}

/**
 * An Arazzo document for the API's workflows: your `defineWorkflow` workflows
 * and the built-ins (`paginationWorkflows()`, `createThenGetWorkflows()`,
 * `authWorkflow()`), checked against the operations the API has. Throws when
 * building or checking the document finds an error; use
 * `defineApi(...).render(arazzoFormat)` to read every finding instead.
 *
 * ```ts
 * const doc = createArazzo(betterSupabase, {
 *   info: { title: "CRM workflows", version: "1.0.0" },
 *   resources: { customers: { pagination: "cursor" } },
 *   workflows: [paginationWorkflows(), createThenGetWorkflows()],
 * });
 * ```
 */
export function createArazzo<V extends ArazzoVersion = "1.0", Ref = string>(
  betterSupabase: ApiSource,
  options: ArazzoOptions<V, Ref>,
): ArazzoDocuments[V] {
  const {
    version,
    transform,
    overlays,
    onDiagnostic,
    openapi,
    asyncapi,
    ...apiOptions
  } = options;

  const format = createArazzoFormat({
    ...(openapi === undefined ? {} : { openapi }),
    ...(asyncapi === undefined ? {} : { asyncapi }),
  });

  const result = defineApi(betterSupabase, apiOptions).render(format, {
    ...(version === undefined ? {} : { version }),
    ...(transform === undefined
      ? {}
      : {
          transform: (rendered: RenderedArazzo) =>
            // SAFETY: render() lowers the requested version V, so the
            // rendered document is the member of the union for V.
            transform(
              rendered as Extract<RenderedArazzo, { readonly version: V }>,
            ),
        }),
    ...(overlays === undefined ? {} : { overlays }),
  });

  const errors = result.diagnostics.filter(
    (diagnostic) => diagnostic.severity === "error",
  );

  if (errors.length > 0) {
    throw new TypeError(
      `createArazzo: ${errors
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

  // SAFETY: the format lowers version V to ArazzoDocuments[V].
  return result.document as ArazzoDocuments[V];
}
