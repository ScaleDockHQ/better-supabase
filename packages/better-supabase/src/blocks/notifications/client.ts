import type { SubscriptionStatus } from "../../realtime/index.ts";
import type { TopicPort } from "../../realtime/watch-topic.ts";
import type { AuthPort, Controller } from "../controller.ts";

import { defineController, whileSignedIn } from "../controller.ts";

/** Loads one list of items, e.g. a server action that calls `notifications.list()`. */
export type NotificationSource<T> = () => Promise<readonly T[]>;

export interface NotificationFeedOptions<T> {
  /**
   * The private topic the `notifications` module broadcasts to:
   * `fillTopic(blockConfig.notifications.options.topic, { userId })` with
   * the template from `blocks.generated.ts`. `null` loads once without
   * realtime.
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

export interface NotificationsControllerOptions<
  T,
> extends NotificationFeedOptions<T> {
  readonly auth: AuthPort;
  readonly ports: { readonly topic: TopicPort };
}

export interface NotificationsSnapshot<T> {
  /** `undefined` until the first load. */
  readonly items: readonly T[] | undefined;
  readonly count: number;
  readonly status: SubscriptionStatus;
  readonly error: unknown;
}

export interface NotificationsActions {
  /** Loads again, e.g. after marking items read. */
  readonly refresh: () => Promise<void>;
}

export type NotificationsController<T> = Controller<
  NotificationsSnapshot<T>,
  NotificationsActions
>;

/** The default badge number: the items whose `readAt` is `null`. */
export const unreadCount = (items: readonly unknown[]): number =>
  items.filter(
    (item) =>
      typeof item === "object" &&
      item !== null &&
      "readAt" in item &&
      item.readAt === null,
  ).length;

/**
 * The signed-in user's notifications, kept current: loads them, then loads
 * again after each broadcast on `topic` and after the channel rejoins.
 */
export function createNotificationsController<T>(
  options: NotificationsControllerOptions<T>,
): NotificationsController<T> {
  const countOf = options.count ?? unreadCount;

  return defineController<NotificationsSnapshot<T>, NotificationsActions>(
    { items: undefined, count: 0, status: "closed", error: undefined },
    (state) => {
      const refresh = async (): Promise<void> => {
        try {
          const lists = await Promise.all(
            [options.load, ...(options.sources ?? [])].map((source) =>
              source(),
            ),
          );

          const merged = lists.flat();
          const items = options.sort ? [...merged].sort(options.sort) : merged;
          state.set({ items, count: countOf(items), error: undefined });
        } catch (cause) {
          state.set({ error: cause });
        }
      };

      return {
        actions: { refresh },
        start: () =>
          whileSignedIn(options.auth, () => {
            void refresh();

            if (!options.topic) {
              return;
            }

            const { leave } = options.ports.topic(options.topic, {
              onMessage: (event, payload) => {
                options.onMessage?.(event, payload);
                void refresh();
              },
              onRejoin: () => void refresh(),
              onStatus: (status) => {
                state.set({ status });
              },
            });

            return leave;
          }),
      };
    },
  );
}
