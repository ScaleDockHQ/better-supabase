"use client";

import type {
  TagChange,
  TagInputActions,
  TagInputSnapshot,
} from "../client.ts";

import { rpcTransport } from "../../../core/block-transport.ts";
import { useController, useLatest } from "../../react-controller.ts";
import { useBlockEnv } from "../../react-env.ts";
import { createTagInputController } from "../client.ts";
import { createTags } from "../tags.ts";

export type { TagChange } from "../client.ts";

export interface UseTagInputOptions {
  /** The organization; the input waits without one. */
  readonly organizationId: string | null | undefined;
  readonly subjectType: string;
  readonly subjectId: string;
  /** The kind of tags the input offers and creates, such as `customer`. */
  readonly kind: string;
  /** The schema the calls go to: the module schema (default `better_supabase`), or the API schema from `blocks.<module>.api`. */
  readonly schema?: string;
  /** Runs after a tag was added or removed. */
  readonly onChanged?: (change: TagChange) => void | Promise<void>;
}

export interface TagInputState extends TagInputSnapshot, TagInputActions {}

/**
 * One subject's tags through the browser client, for a tag input: the
 * tags on it, every tag of the kind for suggestions, and `add`, `remove`
 * and `create`, which show the change at once. The same hook runs in
 * React DOM and React Native.
 *
 * ```tsx
 * const { tags, available, add, remove, create } = useTagInput({ organizationId, subjectType: "customer", subjectId, kind: "customer" });
 * ```
 */
export function useTagInput(options: UseTagInputOptions): TagInputState {
  const { supabase, auth } = useBlockEnv();
  const latest = useLatest(options);
  const { organizationId, subjectType, subjectId, kind, schema } = options;

  return useController(
    () =>
      createTagInputController({
        client: createTags({
          transport: rpcTransport(supabase),
          ...(schema === undefined ? {} : { schema }),
        }),
        auth,
        organizationId: organizationId ?? null,
        subjectType,
        subjectId,
        kind,
        onChanged: async (change) => {
          await latest.current.onChanged?.(change);
        },
      }),
    [
      supabase,
      auth,
      organizationId,
      subjectType,
      subjectId,
      kind,
      schema,
      latest,
    ],
  ).view;
}
