import type { SupabaseClient } from "@supabase/supabase-js";

import { REALTIME_SUBSCRIBE_STATES } from "@supabase/supabase-js";

import type { SubscriptionStatus } from "../realtime/index.ts";

export interface TopicWatch {
  readonly onMessage: (event: string, payload: unknown) => void;
  readonly onRejoin: () => void;
  readonly onStatus: (status: SubscriptionStatus) => void;
}

/** Joins a private topic and returns the function that leaves it. */
export function watchTopic(
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
