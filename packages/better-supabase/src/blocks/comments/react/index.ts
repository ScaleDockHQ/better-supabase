"use client";

import type { CommentsActions, CommentsSnapshot } from "../client.ts";

import { rpcTransport } from "../../../core/block-transport.ts";
import { useController } from "../../react-controller.ts";
import { useBlockEnv } from "../../react-env.ts";
import { createCommentsController } from "../client.ts";
import { createComments } from "../comments.ts";

export type { CommentDraft } from "../client.ts";

export interface UseCommentsOptions {
  /** The organization; the thread waits without one. */
  readonly organizationId: string | null | undefined;
  readonly subjectType: string;
  readonly subjectId: string;
  /** A private topic whose messages load the thread again; default none. */
  readonly topic?: string | null;
  /** The most comments to load, default 100, at most 500. */
  readonly limit?: number;
  /** The schema the calls go to: the module schema (default `better_supabase`), or the API schema from `blocks.<module>.api`. */
  readonly schema?: string;
}

export interface CommentsState extends CommentsSnapshot, CommentsActions {}

/**
 * One subject's comment thread through the browser client, kept current
 * after `add`, `edit` and `remove`. The same hook runs in React DOM and
 * React Native.
 *
 * ```tsx
 * const { comments, add } = useComments({ organizationId, subjectType: "customer", subjectId });
 * ```
 */
export function useComments(options: UseCommentsOptions): CommentsState {
  const { supabase, auth, ports } = useBlockEnv();

  const { organizationId, subjectType, subjectId, topic, limit, schema } =
    options;

  return useController(
    () =>
      createCommentsController({
        client: createComments({
          transport: rpcTransport(supabase),
          ...(schema === undefined ? {} : { schema }),
        }),
        auth,
        ports,
        organizationId: organizationId ?? null,
        subjectType,
        subjectId,
        ...(topic === undefined ? {} : { topic }),
        ...(limit === undefined ? {} : { limit }),
      }),
    [
      supabase,
      auth,
      ports,
      organizationId,
      subjectType,
      subjectId,
      topic,
      limit,
      schema,
    ],
  ).view;
}
