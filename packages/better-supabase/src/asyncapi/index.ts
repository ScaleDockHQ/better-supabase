import type { SpecDiagnostic } from "../spec/format.ts";
import type { ApiSource } from "../spec/options.ts";
import type {
  AnyAsyncApiDocument,
  AsyncApiDocuments,
  AsyncApiVersion,
  RenderedAsyncApi,
} from "./types.ts";

import { type DefineApiOptions, defineApi } from "../spec/api.ts";
import { asyncapiFormat } from "./format.ts";

export { asyncapiFormat } from "./format.ts";

export { CLOUD_EVENT_TRAIT } from "../spec/events.ts";

export type {
  BlockEventSchema,
  BlockEventSchemas,
  CloudEventsInput,
  EventsOptions,
  TopicInput,
} from "../spec/events.ts";

export type {
  AnyAsyncApiDocument,
  AsyncApi30Document,
  AsyncApi31Document,
  AsyncApiComponents,
  AsyncApiDocument,
  AsyncApiDocuments,
  AsyncApiInfo,
  AsyncApiVersion,
  RenderedAsyncApi,
} from "./types.ts";

export { ASYNCAPI_FILE_NAME } from "./types.ts";

export interface AsyncApiOptions<
  V extends AsyncApiVersion = "3.0",
  Ref = string,
> extends DefineApiOptions<Ref> {
  /** Defaults to 3.0, which more tools read; 3.1 only adds `ros2` bindings. */
  readonly version?: V;
  /** Last change to the document before overlays; it receives a copy. */
  readonly transform?: (
    rendered: Extract<RenderedAsyncApi, { readonly version: V }>,
  ) => AnyAsyncApiDocument | undefined;
  readonly overlays?: readonly unknown[];
  /** Hears every warning and info finding. Errors throw. */
  readonly onDiagnostic?: (diagnostic: SpecDiagnostic) => void;
}

/**
 * An AsyncAPI document for the app's events: Realtime table change signals
 * and broadcast topics, CloudEvents for row and block events, outgoing
 * webhooks and the events HTTP operations emit. Pass `events` (and
 * `realtimeUrl` for the websocket server). Throws when building or checking
 * the document finds an error; use `defineApi(...).render(asyncapiFormat)`
 * to read every finding instead.
 *
 * ```ts
 * const doc = createAsyncApi(betterSupabase, {
 *   info: { title: "CRM events", version: "1.0.0" },
 *   realtimeUrl: "wss://example.supabase.co/realtime/v1/websocket",
 *   events: { tables: ["customers"], cloudEvents: { source: "/crm", blocks: { "support.started": true } } },
 * });
 * ```
 */
export function createAsyncApi<V extends AsyncApiVersion = "3.0", Ref = string>(
  betterSupabase: ApiSource,
  options: AsyncApiOptions<V, Ref>,
): AsyncApiDocuments[V] {
  const { version, transform, overlays, onDiagnostic, ...apiOptions } = options;
  const api = defineApi(betterSupabase, apiOptions);

  const result = api.render(asyncapiFormat, {
    ...(version === undefined ? {} : { version }),
    ...(transform === undefined
      ? {}
      : {
          transform: (rendered: RenderedAsyncApi) =>
            // SAFETY: render() lowers the requested version V, so the
            // rendered document is the member of the union for V.
            transform(
              rendered as Extract<RenderedAsyncApi, { readonly version: V }>,
            ),
        }),
    ...(overlays === undefined ? {} : { overlays }),
  });

  const errors = result.diagnostics.filter(
    (diagnostic) => diagnostic.severity === "error",
  );

  if (errors.length > 0) {
    throw new TypeError(
      `createAsyncApi: ${errors
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

  // SAFETY: asyncapiFormat.lower(model, V) returns AsyncApiDocuments[V];
  // the two versions differ only in the `asyncapi` field.
  return result.document as AsyncApiDocuments[V];
}
