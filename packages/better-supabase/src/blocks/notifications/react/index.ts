"use client";

import type { SupabaseClient } from "@supabase/supabase-js";

import { REALTIME_SUBSCRIBE_STATES } from "@supabase/supabase-js";
import { useCallback, useEffect, useRef, useState } from "react";

import type { SubscriptionStatus } from "../../../realtime/index.ts";

import { useAuth, useSupabase } from "../../../react/hooks.ts";

/** Loads one list of items, e.g. a server action that calls `notifications.list()`. */
export type NotificationSource<T> = () => Promise<readonly T[]>;

export interface UseNotificationsOptions<T> {
  /**
   * The private topic the `notifications` module broadcasts to, e.g.
   * `notifications:${userId}` (`sql.modules.notifications.options.topic`). `null`
   * loads once without realtime.
   */
  readonly topic: string | null;
  /** The notifications, newest first. */
  readonly load: NotificationSource<T>;
  /** More items merged in, such as running jobs or pending approvals. */
  readonly sources?: readonly NotificationSource<T>[];
  /** Orders the merged list. Defaults to the order the sources return. */
  readonly sort?: (a: T, b: T) => number;
  /** The badge number. Defaults to the items without a `readAt`. */
  readonly count?: (items: readonly T[]) => number;
  /** Runs for each broadcast, e.g. to show a toast for `notification_created`. */
  readonly onMessage?: (event: string, payload: unknown) => void;
}

export interface NotificationsState<T> {
  /** `undefined` until the first load. */
  readonly items: readonly T[] | undefined;
  readonly count: number;
  readonly status: SubscriptionStatus;
  readonly error: unknown;
  /** Loads again, e.g. after marking items read. */
  readonly refresh: () => Promise<void>;
}

const unread = (items: readonly unknown[]): number =>
  items.filter(
    (item) =>
      typeof item === "object" &&
      item !== null &&
      "readAt" in item &&
      item.readAt === null,
  ).length;

interface TopicWatch {
  readonly onMessage: (event: string, payload: unknown) => void;
  readonly onRejoin: () => void;
  readonly onStatus: (status: SubscriptionStatus) => void;
}

/** Joins a private topic and returns the function that leaves it. */
function watchTopic(
  supabase: SupabaseClient,
  topic: string,
  watch: TopicWatch,
): () => void {
  let closed = false;
  let joined = false;
  const channel = supabase.channel(topic, { config: { private: true } });
  channel.on("broadcast", { event: "*" }, (message) => {
    watch.onMessage(message.event, message["payload"]);
  });
  void (async () => {
    watch.onStatus("joining");
    await supabase.realtime.setAuth();
    // oxlint-disable-next-line typescript/no-unnecessary-condition -- the cleanup can run while setAuth is awaited.
    if (closed) return;
    channel.subscribe((state) => {
      switch (state) {
        case REALTIME_SUBSCRIBE_STATES.SUBSCRIBED:
          // Broadcasts sent while disconnected are lost: reload on rejoin.
          if (joined) watch.onRejoin();
          joined = true;
          watch.onStatus("subscribed");
          return;
        case REALTIME_SUBSCRIBE_STATES.CLOSED:
          watch.onStatus("closed");
          return;
        case REALTIME_SUBSCRIBE_STATES.CHANNEL_ERROR:
        case REALTIME_SUBSCRIBE_STATES.TIMED_OUT:
          watch.onStatus("error");
          return;
        default: {
          const unknown: never = state;
          throw new Error(`Unknown realtime status ${String(unknown)}`);
        }
      }
    });
  })();
  return () => {
    closed = true;
    void supabase.removeChannel(channel);
    watch.onStatus("closed");
  };
}

/**
 * The signed-in user's notifications, kept current: loads them, then loads
 * again after each broadcast on `topic` and after the channel rejoins.
 *
 * ```tsx
 * const { items, count } = useNotifications({
 *   topic: `organization:${organizationId}:notifications:${userId}`,
 *   load: () => listNotifications(organizationId),
 * });
 * ```
 */
export function useNotifications<T>(
  options: UseNotificationsOptions<T>,
): NotificationsState<T> {
  const supabase = useSupabase();
  const auth = useAuth();
  const [items, setItems] = useState<readonly T[] | undefined>(undefined);
  const [error, setError] = useState<unknown>(undefined);
  const [status, setStatus] = useState<SubscriptionStatus>("closed");
  const latest = useRef(options);
  // oxlint-disable-next-line react/refs -- latest-ref pattern; the react peer range predates useEffectEvent.
  latest.current = options;
  const userId = auth.user?.id ?? null;

  const refresh = useCallback(async () => {
    const current = latest.current;
    try {
      const lists = await Promise.all(
        [current.load, ...(current.sources ?? [])].map((source) => source()),
      );
      const merged = lists.flat();
      setItems(current.sort ? [...merged].sort(current.sort) : merged);
      setError(undefined);
    } catch (cause) {
      setError(cause);
    }
  }, []);

  const topic = options.topic;
  useEffect(() => {
    if (auth.status !== "signed-in") return;
    void refresh();
    if (!topic) return;
    return watchTopic(supabase, topic, {
      onMessage: (event, payload) => {
        latest.current.onMessage?.(event, payload);
        void refresh();
      },
      onRejoin: () => void refresh(),
      onStatus: setStatus,
    });
    // oxlint-disable-next-line react/exhaustive-effect-dependencies -- userId reloads and resubscribes for the new user.
  }, [supabase, topic, userId, auth.status, refresh]);

  const list = items ?? [];
  return {
    items,
    count: (options.count ?? unread)(list),
    status,
    error,
    refresh,
  };
}
