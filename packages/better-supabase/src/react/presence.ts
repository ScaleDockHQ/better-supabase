"use client";

import type { SupabaseClient } from "@supabase/supabase-js";

import { useContext, useEffect, useMemo, useRef, useState } from "react";

import type { DbError } from "../core/errors.ts";
import type {
  PresenceMember,
  PresenceOptions,
  PresenceSubscription,
  RealtimeClient,
  SubscribeOptions,
  SubscriptionStatus,
  TemplateValues,
} from "../realtime/index.ts";

import { dbError } from "../core/errors.ts";
import { ClientContext, useBroadcastAuth } from "./hooks.ts";

export interface PresenceHookOptions<I> {
  /**
   * The state this client shares while mounted. It is tracked after the
   * join and tracked again when its JSON changes; `null` stays untracked.
   */
  readonly state?: I | null;
  /** A supabase-js client for apps without `<BetterSupabaseProvider>`. */
  readonly client?: SupabaseClient;
}

export interface Presence<I, O> {
  /** Everyone on the topic, this client included, from the last sync. */
  readonly members: readonly PresenceMember<O>[];
  readonly status: SubscriptionStatus;
  /** Shares a state now; the `state` option tracks one for you. */
  readonly track: (state: I) => Promise<DbError | undefined>;
  readonly untrack: () => Promise<DbError | undefined>;
}

/** The parts of a `defineTopic(..., { presence })` topic the hook uses. */
export interface PresenceTopic<P extends string, I, O> {
  topic(values: TemplateValues<P>): string;
  match(topic: string): TemplateValues<P> | null;
  subscribe(
    client: RealtimeClient,
    values: TemplateValues<P>,
    handlers: Readonly<Record<string, never>>,
    options?: SubscribeOptions & PresenceOptions<O>,
  ): PresenceSubscription<I, O>;
}

const NONE: readonly never[] = [];
const NO_HANDLERS: Readonly<Record<string, never>> = {};

const notJoined = (): Promise<DbError> =>
  Promise.resolve(
    dbError(
      "invalid_request",
      "better-supabase: the presence topic is not joined",
    ),
  );

/**
 * Joins a presence topic while mounted and returns who is on it. Pass
 * `null` values to pause. It rejoins when the topic or the user changes.
 *
 * ```tsx
 * const { members } = usePresence(roomTopic, { roomId }, { state: { name } });
 * ```
 */
export function usePresence<P extends string, I, O>(
  topic: PresenceTopic<P, I, O>,
  values: TemplateValues<P> | null | undefined,
  options: PresenceHookOptions<I> = {},
): Presence<I, O> {
  const context = useContext(ClientContext);
  const supabase = options.client ?? context?.client.supabase;
  if (!supabase) {
    throw new Error(
      "better-supabase: usePresence needs <BetterSupabaseProvider client={bs}> or { client: supabase }",
    );
  }
  const auth = useBroadcastAuth(
    options.client === undefined ? context?.client : undefined,
    supabase,
  );
  const [members, setMembers] = useState<readonly PresenceMember<O>[]>(NONE);
  const [status, setStatus] = useState<SubscriptionStatus>("closed");
  const joinedRef = useRef<PresenceSubscription<I, O> | null>(null);
  const trackedKey = useRef<string | undefined>(undefined);
  const name = values ? topic.topic(values) : null;
  const userId = auth.userId;
  const state = options.state;
  const stateKey = state === undefined ? undefined : JSON.stringify(state);
  const latest = useRef({ state, stateKey });
  // oxlint-disable-next-line react/refs -- latest-ref pattern; the react peer range predates useEffectEvent.
  latest.current = { state, stateKey };

  useEffect(() => {
    if (!name || auth.status === "loading") return;
    const matched = topic.match(name);
    if (!matched) return;
    const joined = topic.subscribe(supabase, matched, NO_HANDLERS, {
      onStatus: setStatus,
      onPresence: setMembers,
    });
    joinedRef.current = joined;
    syncState(joined, latest.current, trackedKey);
    return () => {
      joinedRef.current = null;
      trackedKey.current = undefined;
      setMembers(NONE);
      setStatus("closed");
      void joined.unsubscribe();
    };
    // oxlint-disable-next-line react/exhaustive-effect-dependencies -- userId rejoins with the new user's token.
  }, [supabase, topic, name, userId, auth.status]);

  useEffect(() => {
    const joined = joinedRef.current;
    if (joined)
      syncState(joined, { state: latest.current.state, stateKey }, trackedKey);
  }, [stateKey]);

  const calls = useMemo(
    () => ({
      track: async (next: I) => {
        const joined = joinedRef.current;
        if (!joined) return notJoined();
        const result = await joined.track(next);
        return result.ok ? undefined : result.error;
      },
      untrack: async () => {
        const joined = joinedRef.current;
        if (!joined) return notJoined();
        const result = await joined.untrack();
        return result.ok ? undefined : result.error;
      },
    }),
    [],
  );

  return { members, status, ...calls };
}

/** Tracks or untracks the `state` option once per distinct value. */
function syncState<I>(
  joined: PresenceSubscription<I, unknown>,
  current: {
    readonly state: I | null | undefined;
    readonly stateKey: string | undefined;
  },
  tracked: { current: string | undefined },
): void {
  if (current.stateKey === undefined || current.stateKey === tracked.current)
    return;
  tracked.current = current.stateKey;
  if (current.state === null || current.state === undefined)
    void joined.untrack();
  else void joined.track(current.state);
}
