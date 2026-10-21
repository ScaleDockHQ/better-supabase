"use client";

import type { SubjectRef } from "../../../schema/types.ts";
import type { CommentsActions, CommentsSnapshot } from "../client.ts";

import { envBlockOptions } from "../../block-env.ts";
import { useController } from "../../react-controller.ts";
import { useBlockEnv, useBlockTenant } from "../../react-env.ts";
import { createCommentsController } from "../client.ts";
import { createComments } from "../comments.ts";

export type { CommentDraft } from "../client.ts";

export interface UseCommentsOptions {
  /** The subject whose thread to show; the thread waits without one. */
  readonly subject: SubjectRef | null | undefined;
  /** A private topic whose messages load the thread again; default none. */
  readonly topic?: string | null;
  /** The most comments to load, default 100, at most 500. */
  readonly limit?: number;
}

export interface CommentsState extends CommentsSnapshot, CommentsActions {}

/**
 * One subject's comment thread through the browser client, kept current after
 * `add`, `edit` and `remove`. It acts in the client's tenant and calls the
 * schema and function names in the client's `blocks` config, and waits while
 * there is no tenant. The same hook runs in React DOM and React Native.
 *
 * ```tsx
 * const { comments, add } = useComments({
 *   subject: { type: "customer", id: customerId },
 * });
 * ```
 */
export function useComments(options: UseCommentsOptions): CommentsState {
  const env = useBlockEnv();
  const tenant = useBlockTenant(env);
  const { topic, limit } = options;
  const type = options.subject?.type;
  const id = options.subject?.id;

  return useController(
    () =>
      createCommentsController({
        client: createComments({
          ...envBlockOptions(env, "comments"),
          ...(tenant === undefined ? {} : { tenant }),
        }),
        auth: env.auth,
        ports: env.ports,
        subject:
          tenant === undefined || type === undefined || id === undefined
            ? null
            : { type, id },
        ...(topic === undefined ? {} : { topic }),
        ...(limit === undefined ? {} : { limit }),
      }),
    [env, tenant, type, id, topic, limit],
  ).view;
}
