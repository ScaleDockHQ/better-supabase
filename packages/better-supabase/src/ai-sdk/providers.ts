import type { Experimental_SandboxSession, JSONValue } from "ai";

import type { AiSandboxes } from "../blocks/ai-chat/sandboxes.ts";
import type {
  AiProviders,
  ResolvedProviderKey,
} from "../blocks/ai-providers/ai-providers.ts";
import type { AsyncResult } from "../core/result.ts";

import {
  gatewayOptions,
  type GatewayContext,
  type GatewayOptions,
} from "./gateway.ts";

/** The `settings` key that names the credential field, `apiKey` unless set. */
export const BYOK_FIELD = "credentialField";

function jsonOf(value: unknown): JSONValue {
  // SAFETY: a JSON round trip leaves only JSON values.
  return JSON.parse(JSON.stringify(value ?? null)) as JSONValue;
}

/**
 * The AI Gateway's `byok` option for a tenant's resolved keys: each key
 * becomes `{ apiKey: token, ...settings }` under its provider, in order. A
 * provider whose credential field isn't `apiKey` names it in the key's
 * `settings.credentialField`.
 */
export function byokOptions(
  keys: readonly ResolvedProviderKey[],
): GatewayOptions {
  const byok: Record<string, JSONValue[]> = {};
  for (const key of keys) {
    const { [BYOK_FIELD]: field, ...settings } = key.settings;
    const name =
      typeof field === "string" && field.length > 0 ? field : "apiKey";
    const entry: Record<string, JSONValue> = {};
    for (const [option, value] of Object.entries(settings))
      if (value !== undefined) entry[option] = jsonOf(value);
    entry[name] = key.token;
    (byok[key.provider] ??= []).push(entry);
  }
  return Object.keys(byok).length === 0 ? {} : { byok };
}

/**
 * `providerOptions` for a tenant's request: `gatewayOptions(context, extra)`
 * with the tenant's own keys as `byok`, resolved through the providers block
 * (service role) for this request only. Without keys, the gateway uses the
 * app's credentials.
 */
export function tenantGatewayOptions(
  providers: Pick<AiProviders, "keys">,
  context: GatewayContext & { readonly organizationId: string },
  extra: GatewayOptions = {},
  options: {
    readonly providers?: readonly string[];
    readonly signal?: AbortSignal;
  } = {},
): AsyncResult<{ readonly gateway: GatewayOptions }> {
  return providers.keys
    .resolve(context.organizationId, options)
    .map((keys) => gatewayOptions(context, { ...extra, ...byokOptions(keys) }));
}

export interface TrackedSandboxOptions {
  /** The ai-chat block's sandboxes, with a service transport. */
  readonly sandboxes: Pick<AiSandboxes, "touch">;
  /** The `ai_sandboxes` row id from `sandboxes.register`. */
  readonly id: string;
  /** Milliseconds between two touches. Default 30000. */
  readonly every?: number;
  /** The clock, for tests. */
  readonly now?: () => number;
}

/**
 * Wraps an `experimental_sandbox` session so each use marks its registry row
 * used (`sandboxes.touch`, at most every `every` milliseconds). The idle-stop
 * job then stops only sandboxes nobody used for their `idle_seconds`.
 */
export function trackedSandbox(
  session: Experimental_SandboxSession,
  options: TrackedSandboxOptions,
): Experimental_SandboxSession {
  const every = options.every ?? 30_000;
  const now = options.now ?? Date.now;
  let last = Number.NEGATIVE_INFINITY;
  const touch = (): void => {
    const at = now();
    if (at - last < every) return;
    last = at;
    void options.sandboxes.touch(options.id);
  };
  return new Proxy(session, {
    get(target, property) {
      // SAFETY: the proxy only forwards reads of the session's own members.
      const value: unknown =
        target[property as keyof Experimental_SandboxSession];
      if (typeof value !== "function") return value;
      return (...args: unknown[]): unknown => {
        touch();
        return value.apply(target, args);
      };
    },
  });
}
