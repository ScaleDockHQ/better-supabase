import type { SupabaseClient } from "@supabase/supabase-js";

import type { SubscriptionStatus } from "../realtime/index.ts";

import { joinTopic } from "../realtime/channels.ts";

export interface TopicWatch {
  readonly onMessage: (event: string, payload: unknown) => void;
  readonly onRejoin: () => void;
  readonly onStatus: (status: SubscriptionStatus) => void;
}

/**
 * Joins a private topic and returns the function that leaves it. Watches on
 * the same client and topic share one channel, as `defineTopic` subscriptions
 * do, and the channel closes when the last one leaves.
 */
export function watchTopic(
  supabase: SupabaseClient,
  topic: string,
  watch: TopicWatch,
): () => void {
  let joined = false;
  let left = false;
  let leave: () => Promise<void>;
  try {
    ({ leave } = joinTopic(supabase, topic, true, false, false, {
      onStatus: (status) => {
        if (left) return;
        if (status === "subscribed") {
          // Broadcasts sent while disconnected are lost: reload on rejoin.
          if (joined) watch.onRejoin();
          joined = true;
        }
        watch.onStatus(status);
      },
      receive: (message) => {
        if (!left) watch.onMessage(message.event, message.payload);
      },
    }));
  } catch {
    // The topic is already joined with other `self` or `presence` settings.
    watch.onStatus("error");
    return () => undefined;
  }
  return () => {
    if (left) return;
    left = true;
    watch.onStatus("closed");
    // A StrictMode remount joins again in the same commit: leaving a
    // microtask later lets it keep the channel instead of getting the one
    // realtime-js is still tearing down.
    queueMicrotask(() => void leave());
  };
}
