import type { RealtimeClient, SubscriptionStatus } from "./topic.ts";

import { joinTopic } from "./channels.ts";

export interface TopicWatch {
  readonly onMessage: (event: string, payload: unknown) => void;
  readonly onRejoin: () => void;
  readonly onStatus: (status: SubscriptionStatus) => void;
}

/**
 * A joined topic: `leave` is safe to call twice, `send` broadcasts to the other
 * members.
 */
export interface TopicHandle {
  readonly leave: () => void;
  readonly send: (
    event: string,
    payload: Readonly<Record<string, unknown>>,
  ) => void;
}

/**
 * Joins a private topic and reports its messages, rejoins and status: the
 * realtime port of the block controllers. `topicPort(supabase)` is the default;
 * a test passes a fake.
 */
export type TopicPort = (topic: string, watch: TopicWatch) => TopicHandle;

const CLOSED: TopicHandle = { leave: () => undefined, send: () => undefined };

/**
 * Joins a private topic and returns its handle. Watches on the same client and
 * topic share one channel, as `defineTopic` subscriptions do, and the channel
 * closes when the last one leaves.
 */
export function watchTopic(
  supabase: RealtimeClient,
  topic: string,
  watch: TopicWatch,
): TopicHandle {
  let joined = false;
  let left = false;
  let joinedTopic: ReturnType<typeof joinTopic>;

  try {
    joinedTopic = joinTopic(supabase, topic, true, false, false, {
      onStatus: (status) => {
        if (left) {
          return;
        }

        if (status === "subscribed") {
          // Broadcasts sent while disconnected are lost: reload on rejoin.
          if (joined) {
            watch.onRejoin();
          }

          joined = true;
        }

        watch.onStatus(status);
      },
      receive: (message) => {
        if (!left) {
          watch.onMessage(message.event, message.payload);
        }
      },
    });
  } catch {
    // The topic is already joined with other `self` or `presence` settings.
    watch.onStatus("error");

    return CLOSED;
  }

  const { shared, leave } = joinedTopic;

  return {
    leave: () => {
      if (left) {
        return;
      }

      left = true;
      watch.onStatus("closed");
      // A StrictMode remount joins again in the same commit: leaving a
      // microtask later lets it keep the channel instead of getting the one
      // realtime-js is still tearing down.
      queueMicrotask(() => void leave());
    },
    send: (event, payload) => {
      if (left) {
        return;
      }

      void shared.channel.send({ type: "broadcast", event, payload });
    },
  };
}

/** The realtime port over a supabase-js client. */
export function topicPort(supabase: RealtimeClient): TopicPort {
  return (topic, watch) => watchTopic(supabase, topic, watch);
}
