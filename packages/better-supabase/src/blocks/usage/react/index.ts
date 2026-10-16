"use client";

import type { UsageMeterActions, UsageMeterSnapshot } from "../client.ts";

import { rpcTransport } from "../../../core/block-transport.ts";
import { useController } from "../../react-controller.ts";
import { useBlockEnv } from "../../react-env.ts";
import { createUsageMeterController } from "../client.ts";
import { createUsage } from "../usage.ts";

export type { MeterReading } from "../client.ts";

export interface UseUsageMeterOptions {
  /** The organization whose usage to read; the meter waits without one. */
  readonly organizationId: string | null | undefined;
  /** Only these meters, in this order. Default every meter with usage or a quota. */
  readonly meters?: readonly string[];
  /** The schema the calls go to: the module schema (default `better_supabase`), or the API schema from `blocks.<module>.api`. */
  readonly schema?: string;
}

export interface UsageMeterState
  extends UsageMeterSnapshot, UsageMeterActions {}

/**
 * This period's usage of an organization against its plan's quotas,
 * through the browser client (`usage.read`). The same hook runs in React
 * DOM and React Native.
 *
 * ```tsx
 * const { meters } = useUsageMeter({ organizationId });
 * ```
 */
export function useUsageMeter(options: UseUsageMeterOptions): UsageMeterState {
  const { supabase, auth } = useBlockEnv();
  const { organizationId, meters, schema } = options;
  const key = meters?.join("\n");
  return useController(
    () =>
      createUsageMeterController({
        client: createUsage({
          transport: rpcTransport(supabase),
          ...(schema === undefined ? {} : { schema }),
        }),
        auth,
        organizationId: organizationId ?? null,
        ...(key === undefined ? {} : { meters: key.split("\n") }),
      }),
    [supabase, auth, organizationId, key, schema],
  ).view;
}
