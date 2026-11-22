import type { JSONValue } from "ai";

/** A region `inferenceRegion` can pin to (the AI Gateway's regional inference). */
export type GatewayGeoRegion = "us" | "eu" | "au" | "jp";

/**
 * Where the provider runs inference and stores data. `zone` needs a
 * `geoRegion`; `global` (or leaving the option out) lets the gateway pick.
 */
export type GatewayInferenceRegion =
  | { readonly scope: "zone"; readonly geoRegion: GatewayGeoRegion }
  | { readonly scope: "global" };

/** A capability or weight-format condition for `has`. */
export type GatewayHas =
  | "implicit-caching"
  | "reasoning"
  | "structured-output"
  | "tool-use"
  | "vision"
  | `quantization:${string}`
  | `!quantization:${string}`;

/**
 * A structural copy of `GatewayProviderOptions` from `@ai-sdk/gateway`
 * (`providerOptions.gateway`), narrowed to JSON values so it is assignable to
 * the AI SDK's `providerOptions` and to the SDK's own type. It also carries the
 * options the gateway documents but the SDK does not type yet
 * (`inferenceRegion`, `sessionId`, `sessionAffinity`). Any other key the
 * gateway adds still passes through the index signature.
 */
export interface GatewayProviderOptions {
  readonly [key: string]: JSONValue | undefined;
  /** Request-scoped BYOK credentials, used instead of cached ones. */
  readonly byok?: {
    readonly [provider: string]: {
      readonly [field: string]: JSONValue | undefined;
    }[];
  };
  /** Lets the gateway apply the provider's prompt caching strategy. */
  readonly caching?: "auto";
  /** Only providers that do not train on prompt data. */
  readonly disallowPromptTraining?: boolean;
  /**
   * Only providers whose parent company is headquartered in these ISO 3166-1
   * alpha-2 countries, or, with every code prefixed by `!`, none of them.
   */
  readonly headquarters?: string[];
  /** Only provider models with every one of these capabilities. */
  readonly has?: GatewayHas[];
  /** Replays an `experimental_startBatch` instead of creating a duplicate. */
  readonly idempotencyKey?: string;
  /** Models to try in order when the primary fails. */
  readonly models?: string[];
  /** The only providers the request may use (a hard filter, no fallback). */
  readonly only?: string[];
  /** The providers to try first, in order; others stay eligible. */
  readonly order?: string[];
  /** Per-provider BYOK timeouts in milliseconds. */
  readonly providerTimeouts?: {
    readonly byok?: { readonly [provider: string]: number };
  };
  /** The entity a quota is tracked against. */
  readonly quotaEntityId?: string;
  readonly serviceTier?: "flex" | "priority";
  readonly sort?: "cost" | "tps" | "ttft";
  /** Tags for reporting and filtering usage. */
  readonly tags?: string[];
  /** The end user spend is attributed to. */
  readonly user?: string;
  /** Only providers with a zero data retention agreement. */
  readonly zeroDataRetention?: boolean;
  /** Pins inference to a region (beta; not yet in the SDK's type). */
  readonly inferenceRegion?: GatewayInferenceRegion;
  /** Groups the requests of one conversation or run for provider affinity. */
  readonly sessionId?: string;
  /** `false` stops the gateway from pinning a session to one provider. */
  readonly sessionAffinity?: boolean;
}
