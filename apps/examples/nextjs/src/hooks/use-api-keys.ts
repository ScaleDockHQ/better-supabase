"use client";

import type {
  ApiKeyChange,
  ApiKeysActions,
  ApiKeysSnapshot,
} from "better-supabase/blocks/api-keys";

import { rpcTransport } from "better-supabase/blocks";
import {
  createApiKeys,
  createApiKeysController,
} from "better-supabase/blocks/api-keys";
import { useBlockEnv, useController, useLatest } from "better-supabase/react";

export type {
  ApiKeyChange,
  ApiKeyDraft,
} from "better-supabase/blocks/api-keys";

export interface UseApiKeysOptions {
  /**
   * The organization whose keys to list and create; without one the hook lists
   * the caller's personal keys.
   */
  readonly organizationId: string | null | undefined;
  /**
   * The schema the calls go to: the module schema (default `better_supabase`),
   * or the API schema from `blocks.<module>.api`.
   */
  readonly schema?: string;
  /** The token's first segment, `blocks.api-keys.options.prefix` (default `bs`). */
  readonly prefix?: string;
  /** Runs after a key was created or revoked. */
  readonly onChanged?: (change: ApiKeyChange) => void | Promise<void>;
}

export interface ApiKeysState extends ApiKeysSnapshot, ApiKeysActions {}

/**
 * An organization's API keys through the browser client, for an API keys table:
 * `create` keeps the new token in `created`, which is the only time it is
 * shown, and `revoke` revokes a key. The same hook runs in React DOM and React
 * Native.
 *
 * ```tsx
 * const { keys, created, create, revoke } = useApiKeys({ organizationId });
 * ```
 */
export function useApiKeys(options: UseApiKeysOptions): ApiKeysState {
  const { supabase, auth } = useBlockEnv();
  const latest = useLatest(options);
  const { organizationId, schema, prefix } = options;

  return useController(
    () =>
      createApiKeysController({
        client: createApiKeys({
          transport: rpcTransport(supabase),
          ...(schema === undefined ? {} : { schema }),
          ...(prefix === undefined ? {} : { prefix }),
        }),
        auth,
        organizationId: organizationId ?? null,
        onChanged: async (change) => {
          await latest.current.onChanged?.(change);
        },
      }),
    [supabase, auth, organizationId, schema, prefix, latest],
  ).view;
}
