"use client";

import type {
  NotificationsActions,
  NotificationFeedOptions,
  NotificationsSnapshot,
} from "../client.ts";

import { useController, useLatest } from "../../react-controller.ts";
import { useBlockEnv } from "../../react-env.ts";
import { createNotificationsController, unreadCount } from "../client.ts";

export type { NotificationSource } from "../client.ts";

export type UseNotificationsOptions<T> = NotificationFeedOptions<T>;

export interface NotificationsState<T>
  extends NotificationsSnapshot<T>, NotificationsActions {}

/**
 * The signed-in user's notifications, kept current: loads them, then loads
 * again after each broadcast on `topic` and after the channel rejoins. The
 * same hook runs in React DOM and React Native.
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
  const { auth, ports } = useBlockEnv();
  const latest = useLatest(options);
  const { topic } = options;

  return useController(
    () =>
      createNotificationsController<T>({
        auth,
        ports,
        topic,
        load: () => latest.current.load(),
        sources: [
          async () =>
            (
              await Promise.all(
                (latest.current.sources ?? []).map((source) => source()),
              )
            ).flat(),
        ],
        sort: (a, b) => latest.current.sort?.(a, b) ?? 0,
        count: (items) => (latest.current.count ?? unreadCount)(items),
        onMessage: (event, payload) => {
          latest.current.onMessage?.(event, payload);
        },
      }),
    [auth, ports, topic, latest],
  ).view;
}
