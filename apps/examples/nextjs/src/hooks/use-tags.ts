"use client";

import type { RecordRef } from "better-supabase/blocks";
import type {
  TagChange,
  TagInputActions,
  TagInputSnapshot,
} from "better-supabase/blocks/tags";

import { envBlockOptions } from "better-supabase/blocks";
import {
  createTagInputController,
  createTags,
} from "better-supabase/blocks/tags";
import {
  useBlockEnv,
  useBlockTenant,
  useController,
  useLatest,
} from "better-supabase/react";

export type { TagChange } from "better-supabase/blocks/tags";

export interface UseTagInputOptions {
  /** The subject whose tags to show; the input waits without one. */
  readonly subject: RecordRef | null | undefined;
  /** The kind of tags the input offers and creates, such as `customer`. */
  readonly kind: string;
  /** Runs after a tag was added or removed. */
  readonly onChanged?: (change: TagChange) => void | Promise<void>;
}

export interface TagInputState extends TagInputSnapshot, TagInputActions {}

/**
 * One subject's tags through the browser client, for a tag input: the tags on
 * it, every tag of the kind for suggestions, and `add`, `remove` and `create`,
 * which show the change at once. It acts in the client's tenant and calls the
 * schema and function names in the client's `blocks` config, and waits while
 * there is no tenant. The same hook runs in React DOM and React Native.
 *
 * ```tsx
 * const { tags, available, add, remove, create } = useTagInput({
 *   subject: { type: "customer", id: customerId },
 *   kind: "customer",
 * });
 * ```
 */
export function useTagInput(options: UseTagInputOptions): TagInputState {
  const env = useBlockEnv();
  const tenant = useBlockTenant(env);
  const latest = useLatest(options);
  const { kind } = options;
  const type = options.subject?.type;
  const id = options.subject?.id;

  return useController(
    () =>
      createTagInputController({
        client: createTags({
          ...envBlockOptions(env, "tags"),
          ...(tenant === undefined ? {} : { tenant }),
        }),
        auth: env.auth,
        subject:
          tenant === undefined || type === undefined || id === undefined
            ? null
            : { type, id },
        kind,
        onChanged: async (change) => {
          await latest.current.onChanged?.(change);
        },
      }),
    [env, tenant, type, id, kind, latest],
  ).view;
}
