"use client";

import type { BlockEnv, RecordRef } from "better-supabase/blocks";
import type {
  CommentsActions,
  CommentsSnapshot,
} from "better-supabase/blocks/comments";

import { envBlockOptions, envBlockSettings } from "better-supabase/blocks";
import {
  createComments,
  createCommentsController,
} from "better-supabase/blocks/comments";
import {
  useBlockEnv,
  useBlockTenant,
  useController,
} from "better-supabase/react";

export type { CommentDraft } from "better-supabase/blocks/comments";

/** `blocks.messaging.options.topic` from the client's config. */
function topicOf(env: BlockEnv): string {
  const topic = envBlockSettings(env, "messaging")["topic"];

  return typeof topic === "string" ? topic : "messages";
}

export interface UseCommentsOptions {
  /** The subject whose thread to show; the thread waits without one. */
  readonly subject: RecordRef | null | undefined;
  /**
   * The messaging topic prefix the record conversation's pings arrive on;
   * default `blocks.messaging.options.topic` (`messages`). `null` turns
   * Realtime off.
   */
  readonly topic?: string | null;
  /** The most comments to load, default 100, at most 500. */
  readonly limit?: number;
}

export interface CommentsState extends CommentsSnapshot, CommentsActions {}

/**
 * One subject's comment thread through the browser client, kept current after
 * its own writes and live on the record conversation's topic. It acts in the
 * client's tenant and calls the schema and function names in the client's
 * `blocks` config, and waits while there is no tenant. The same hook runs in
 * React DOM and React Native.
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
  const { limit } = options;
  const topic = options.topic === undefined ? topicOf(env) : options.topic;
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
        topic,
        ...(limit === undefined ? {} : { limit }),
      }),
    [env, tenant, type, id, topic, limit],
  ).view;
}
