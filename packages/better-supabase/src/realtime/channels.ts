import {
  type RealtimeChannel,
  type RealtimePresenceState,
  REALTIME_SUBSCRIBE_STATES,
} from "@supabase/supabase-js";

import type {
  RealtimeClient,
  SubscribeOptions,
  SubscriptionStatus,
  TopicMessage,
} from "./topic.ts";

import { refreshRealtimeAuth } from "./auth.ts";

export interface Subscriber {
  readonly onStatus: SubscribeOptions["onStatus"];
  readonly receive: (message: TopicMessage) => void;
  readonly sync?: (state: RealtimePresenceState) => void;
}

export interface SharedTopic {
  readonly channel: RealtimeChannel;
  readonly self: boolean;
  readonly presence: boolean;
  readonly subscribers: Set<Subscriber>;
  readonly ready: Promise<void>;
  subscribed: boolean;
  synced: boolean;
  /** The subscriber whose `track` set this client's presence state. */
  tracker: Subscriber | undefined;
}

const topicChannels = new WeakMap<RealtimeClient, Map<string, SharedTopic>>();

/**
 * One channel per topic and client, shared by every `subscribe()` on it:
 * supabase-js hands back the open channel for a topic, so a second join or
 * an early `removeChannel` would break the first subscription.
 */
export function joinTopic(
  client: RealtimeClient,
  topic: string,
  isPrivate: boolean,
  self: boolean,
  presence: boolean,
  subscriber: Subscriber,
): {
  shared: SharedTopic;
  leave: () => Promise<void>;
} {
  let byTopic = topicChannels.get(client);
  if (!byTopic) {
    byTopic = new Map();
    topicChannels.set(client, byTopic);
  }
  const topics = byTopic;
  let shared = topics.get(topic);
  if (shared && shared.self !== self) {
    throw new TypeError(
      `better-supabase: "${topic}" is already subscribed with self: ${String(shared.self)}; every subscription on a topic needs the same \`self\``,
    );
  }
  if (shared && shared.presence !== presence) {
    throw new TypeError(
      `better-supabase: "${topic}" is already subscribed ${shared.presence ? "with" : "without"} presence; every topic definition for it needs the same \`presence\``,
    );
  }
  if (!shared) {
    const channel = client.channel(topic, {
      config: { private: isPrivate, broadcast: { self } },
    });
    const subscribers = new Set<Subscriber>();
    const status = (next: SubscriptionStatus, error?: Error): void => {
      for (const each of subscribers) each.onStatus?.(next, error);
    };
    channel.on("broadcast", { event: "*" }, (raw) => {
      const message: TopicMessage = {
        event: raw.event,
        payload: raw["payload"],
        topic,
      };
      for (const each of subscribers) each.receive(message);
    });
    // realtime-js refuses presence listeners after `subscribe()`, so the
    // shared channel registers one for every subscriber up front.
    if (presence) {
      channel.on("presence", { event: "sync" }, () => {
        entry.synced = true;
        const state = channel.presenceState();
        for (const each of subscribers) each.sync?.(state);
      });
    }
    const evict = (): void => {
      if (topics.get(topic) !== entry) return;
      topics.delete(topic);
      void client.removeChannel(channel);
    };
    const ready = (async () => {
      // Yields for public topics too: the first subscriber is added after
      // this starts, and one that leaves before the join skips it.
      await (isPrivate ? refreshRealtimeAuth(client) : undefined);
      if (subscribers.size === 0) return;
      await new Promise<void>((resolve, reject) => {
        channel.subscribe((state, error) => {
          // Dropped channels still report CLOSED on removal.
          if (topics.get(topic) !== entry) return;
          switch (state) {
            case REALTIME_SUBSCRIBE_STATES.SUBSCRIBED:
              entry.subscribed = true;
              status("subscribed");
              resolve();
              return;
            case REALTIME_SUBSCRIBE_STATES.CLOSED:
              entry.subscribed = false;
              status("closed");
              resolve();
              return;
            case REALTIME_SUBSCRIBE_STATES.CHANNEL_ERROR:
            case REALTIME_SUBSCRIBE_STATES.TIMED_OUT: {
              const failure =
                error ??
                new Error(`Realtime ${state.toLowerCase()} on ${topic}`);
              status("error", failure);
              reject(failure);
              // A joined channel rejoins on its own; one that never joined is
              // dropped so the next subscribe opens a fresh channel.
              if (!entry.subscribed) evict();
              return;
            }
            default: {
              const unknown: never = state;
              reject(new Error(`Unknown realtime status ${String(unknown)}`));
            }
          }
        });
      });
    })();
    ready.catch(() => undefined);
    const entry: SharedTopic = {
      channel,
      self,
      presence,
      subscribers,
      ready,
      subscribed: false,
      synced: false,
      tracker: undefined,
    };
    shared = entry;
    topics.set(topic, entry);
  }
  const current = shared;
  current.subscribers.add(subscriber);
  subscriber.onStatus?.("joining");
  if (current.subscribed) subscriber.onStatus?.("subscribed");
  if (current.synced) subscriber.sync?.(current.channel.presenceState());
  return {
    shared: current,
    leave: async () => {
      current.subscribers.delete(subscriber);
      if (current.subscribers.size > 0) {
        if (current.tracker === subscriber) {
          current.tracker = undefined;
          await current.channel.untrack();
        }
        return;
      }
      // Removed right away rather than on the next tick like live queries: a
      // resubscribe for another user must join with that user's token.
      if (topics.get(topic) !== current) return;
      topics.delete(topic);
      await client.removeChannel(current.channel);
    },
  };
}
