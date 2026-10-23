import type { AuthzVersionCache } from "../core/authorizer.ts";

/** The broadcast message shape Realtime delivers for `realtime.send()`. */
interface BroadcastMessage {
  readonly payload?: unknown;
}

/** The part of a supabase-js `RealtimeChannel` the subscriber uses. */
export interface AuthzVersionChannel {
  on(
    type: "broadcast",
    filter: { readonly event: string },
    callback: (message: BroadcastMessage) => void,
  ): AuthzVersionChannel;
  subscribe(
    callback?: (status: string, error?: Error) => void,
  ): AuthzVersionChannel;
  unsubscribe(): Promise<unknown>;
}

/** The part of a supabase-js client the subscriber uses. */
export interface AuthzVersionClient {
  channel(
    topic: string,
    options: { readonly config: { readonly private: boolean } },
  ): AuthzVersionChannel;
}

export interface SubscribeAuthzVersionsOptions {
  /**
   * A service-role client. It reads the private channel without a
   * `realtime.messages` policy, so no user can listen.
   */
  readonly client: AuthzVersionClient;
  /** The private channel the database trigger sends on. */
  readonly topic: string;
  /** The broadcast event name the trigger uses. */
  readonly event: string;
  /** The payload key holding the user id whose authorization changed. */
  readonly userIdKey: string;
  /** The app's module-scope cache; each message evicts one user. */
  readonly versions: AuthzVersionCache;
  /** Called for a malformed message, a failed eviction or a channel error. */
  readonly onError?: (error: Error) => void;
}

export interface AuthzVersionSubscription {
  /** Settles once the channel is subscribed; rejects when it can't join. */
  readonly ready: Promise<void>;
  /** Leaves the channel. A later `subscribeAuthzVersions` joins again. */
  close(): Promise<void>;
}

const subscriptions = new WeakMap<
  AuthzVersionCache,
  AuthzVersionSubscription
>();

function userIdOf(payload: unknown, key: string): string | undefined {
  if (typeof payload !== "object" || payload === null || !(key in payload)) {
    return undefined;
  }

  const value: unknown = Object.entries(payload).find(
    ([name]) => name === key,
  )?.[1];

  return typeof value === "string" && value.length > 0 ? value : undefined;
}

/**
 * Evicts a user from `versions` whenever the database broadcasts that their
 * authorization changed, so the next check reads the new version. Call it once
 * from the module that creates `versions`; a second call with the same cache
 * returns the first subscription.
 *
 * ```ts
 * export const versions = createVersionCache();
 * subscribeAuthzVersions({
 *   client: serviceClient,
 *   topic: "authz-versions",
 *   event: "changed",
 *   userIdKey: "user_id",
 *   versions,
 * });
 * ```
 */
export function subscribeAuthzVersions(
  options: SubscribeAuthzVersionsOptions,
): AuthzVersionSubscription {
  const existing = subscriptions.get(options.versions);

  if (existing) {
    return existing;
  }

  const report = (error: Error): void => {
    options.onError?.(error);
  };

  const channel = options.client.channel(options.topic, {
    config: { private: true },
  });

  channel.on("broadcast", { event: options.event }, (message) => {
    const userId = userIdOf(message.payload, options.userIdKey);

    if (userId === undefined) {
      report(
        new Error(
          `better-supabase: an ${options.event} message on ${options.topic} has no ${options.userIdKey}`,
        ),
      );

      return;
    }

    Promise.resolve(options.versions.evict(userId)).catch((cause: unknown) => {
      report(cause instanceof Error ? cause : new Error(String(cause)));
    });
  });

  const ready = new Promise<void>((resolve, reject) => {
    channel.subscribe((status, error) => {
      switch (status) {
        case "SUBSCRIBED": {
          resolve();
          break;
        }

        case "CHANNEL_ERROR":
        case "TIMED_OUT": {
          const failure =
            error ??
            new Error(
              `better-supabase: ${options.topic} ${status.toLowerCase()}`,
            );

          report(failure);
          reject(failure);
          break;
        }

        default: {
          break;
        }
      }
    });
  });

  ready.catch(() => {
    subscriptions.delete(options.versions);
  });

  const subscription: AuthzVersionSubscription = {
    ready,
    async close() {
      subscriptions.delete(options.versions);
      await channel.unsubscribe();
    },
  };

  subscriptions.set(options.versions, subscription);

  return subscription;
}
