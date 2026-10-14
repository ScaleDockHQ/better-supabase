"use client";

import { useCallback, useEffect, useMemo, useState } from "react";

import type { DbError } from "../../../core/errors.ts";
import type { SubscriptionStatus } from "../../../realtime/index.ts";
import type { ReactionCount } from "../reactions.ts";

import { rpcTransport } from "../../../core/block-transport.ts";
import { useAuth, useSupabase } from "../../../react/hooks.ts";
import { watchTopic } from "../../react-topic.ts";
import { createReactions, reactionsTopic } from "../reactions.ts";

export interface UseReactionsOptions {
  readonly organizationId: string;
  readonly subjectType: string;
  /** The subjects on screen, at most 200. */
  readonly subjectIds: readonly string[];
  /** `sql.modules.reactions.options.topic`; `null` loads without listening. */
  readonly topic?: string | null;
  /** The schema the calls go to: the module schema (default `better_supabase`), or the API schema from `sql.modules.<module>.api`. */
  readonly schema?: string;
}

export interface ReactionsState {
  /** Reactions by subject id; `undefined` until the first load. */
  readonly reactions:
    | Readonly<Record<string, readonly ReactionCount[]>>
    | undefined;
  readonly status: SubscriptionStatus;
  readonly error: DbError | undefined;
  /** Adds the emoji, or removes it when the user already reacted with it. */
  readonly toggle: (subjectId: string, emoji: string) => Promise<void>;
  readonly refresh: () => Promise<void>;
}

/**
 * The reactions of the subjects on screen, loaded again when anyone in the
 * organization reacts to one of them. `toggle` feeds an emoji picker.
 *
 * ```tsx
 * const { reactions, toggle } = useReactions({ organizationId, subjectType: "comment", subjectIds });
 * ```
 */
export function useReactions(options: UseReactionsOptions): ReactionsState {
  const supabase = useSupabase();
  const auth = useAuth();
  const [reactions, setReactions] = useState<
    Readonly<Record<string, readonly ReactionCount[]>> | undefined
  >(undefined);
  const [error, setError] = useState<DbError | undefined>(undefined);
  const [status, setStatus] = useState<SubscriptionStatus>("closed");
  const { organizationId, subjectType, schema } = options;
  const topic = options.topic === undefined ? "reactions" : options.topic;
  const ids = options.subjectIds.join("\n");
  const client = useMemo(
    () =>
      createReactions({
        transport: rpcTransport(supabase),
        ...(schema === undefined ? {} : { schema }),
      }),
    [supabase, schema],
  );
  const signedIn = auth.status === "signed-in";

  const refresh = useCallback(async () => {
    const result = await client.summary(
      organizationId,
      subjectType,
      ids === "" ? [] : ids.split("\n"),
    );
    if (result.ok) {
      setReactions(result.data);
      setError(undefined);
    } else {
      setError(result.error);
    }
  }, [client, organizationId, subjectType, ids]);

  const toggle = useCallback(
    async (subjectId: string, emoji: string) => {
      const present = !reactions?.[subjectId]?.some(
        (reaction) => reaction.emoji === emoji && reaction.reacted,
      );
      const result = await client.react(
        organizationId,
        subjectType,
        subjectId,
        emoji,
        { present },
      );
      if (!result.ok) {
        setError(result.error);
        return;
      }
      setError(undefined);
      setReactions((current) => ({ ...current, [subjectId]: result.data }));
    },
    [client, organizationId, subjectType, reactions],
  );

  useEffect(() => {
    if (!signedIn) return;
    const load = () => void refresh();
    load();
    const watched = new Set(ids.split("\n"));
    const leave = topic
      ? watchTopic(supabase, reactionsTopic(organizationId, topic), {
          onMessage: (_event, payload) => {
            if (
              typeof payload === "object" &&
              payload !== null &&
              "subjectId" in payload &&
              "subjectType" in payload &&
              (payload.subjectType !== subjectType ||
                typeof payload.subjectId !== "string" ||
                !watched.has(payload.subjectId))
            ) {
              return;
            }
            load();
          },
          onRejoin: load,
          onStatus: setStatus,
        })
      : undefined;
    return () => leave?.();
  }, [supabase, topic, organizationId, subjectType, ids, signedIn, refresh]);

  return { reactions, status, error, toggle, refresh };
}
