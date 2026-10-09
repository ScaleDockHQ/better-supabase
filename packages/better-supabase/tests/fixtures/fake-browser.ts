import type { Mock } from "vitest";

import { QueryClient } from "@tanstack/query-core";
import { vi } from "vitest";

import type { ClientLike } from "../../src/bindings/client.ts";
import type { PresenceTopic } from "../../src/bindings/client.ts";
import type { AuthSnapshot } from "../../src/client/index.ts";
import type {
  PresenceMember,
  SubscriptionStatus,
} from "../../src/realtime/index.ts";
import type {
  DatabaseOf,
  ModelsOf,
  SchemaMeta,
} from "../../src/schema/types.ts";

import { type BetterSupabase, defineSupabase } from "../../src/core/define.ts";
import { dbError } from "../../src/core/errors.ts";
import { AsyncResult, err, ok } from "../../src/core/result.ts";
import { defineSchema } from "../../src/schema/define.ts";
import { schema } from "./generated-camel.ts";

export const USER = "00000000-0000-4000-8000-0000000000aa";
export const OTHER = "00000000-0000-4000-8000-0000000000bb";
export const LOADING: AuthSnapshot = {
  status: "loading",
  user: null,
  claims: null,
};
export const SIGNED_OUT: AuthSnapshot = {
  status: "signed-out",
  user: null,
  claims: null,
};
export const signedIn = (
  id: string,
  claims: Record<string, unknown> = {},
): AuthSnapshot => ({
  status: "signed-in",
  user: { id },
  claims: { sub: id, ...claims },
});

const meta: SchemaMeta = {
  ...schema.meta,
  realtime: { customers: { tenant: "organizationId" }, notes: {} },
};
const betterSupabase: ReturnType<typeof defineSupabase> = defineSupabase(
  defineSchema(meta),
);
export const typed: BetterSupabase<
  ModelsOf<typeof schema>,
  DatabaseOf<typeof schema>
> = defineSupabase(schema);

type Listener = (message: { event: string; payload: unknown }) => void;
type AuthListener = (event: string, session: unknown) => void;

export interface FakeRealtime {
  readonly client: {
    readonly channel: Mock<(topic: string, options?: unknown) => unknown>;
    readonly removeChannel: Mock<(channel: { topic: string }) => Promise<"ok">>;
    readonly realtime: { readonly setAuth: Mock<() => Promise<undefined>> };
    readonly auth: {
      readonly onAuthStateChange: Mock<(listener: AuthListener) => unknown>;
    };
  };
  readonly channels: Map<string, { broadcast: Set<Listener> }>;
  readonly emit: (topic: string, event: string, payload?: unknown) => void;
  readonly emitAuth: (session: unknown) => void;
  readonly authListeners: Set<AuthListener>;
}

/** A supabase-js client with broadcast channels and an auth state listener. */
export function fakeRealtime(): FakeRealtime {
  const channels = new Map<string, { broadcast: Set<Listener> }>();
  const authListeners = new Set<AuthListener>();
  const client = {
    channel: vi.fn((topic: string, _options?: unknown) => {
      const entry = { broadcast: new Set<Listener>() };
      channels.set(topic, entry);
      const channel = {
        topic,
        on: (_type: string, _filter: unknown, listener: Listener) => {
          entry.broadcast.add(listener);
          return channel;
        },
        subscribe: (callback: (status: string) => void) => {
          queueMicrotask(() => {
            callback("SUBSCRIBED");
          });
          return channel;
        },
      };
      return channel;
    }),
    removeChannel: vi.fn(async (channel: { topic: string }) => {
      channels.delete(channel.topic);
      return "ok" as const;
    }),
    realtime: { setAuth: vi.fn(async () => undefined) },
    auth: {
      onAuthStateChange: vi.fn((listener: AuthListener) => {
        authListeners.add(listener);
        return {
          data: {
            subscription: {
              unsubscribe: () => void authListeners.delete(listener),
            },
          },
        };
      }),
    },
  };
  const emit = (topic: string, event: string, payload: unknown = {}): void => {
    for (const listener of channels.get(topic)?.broadcast ?? [])
      listener({ event, payload });
  };
  const emitAuth = (session: unknown): void => {
    for (const listener of [...authListeners]) listener("SIGNED_IN", session);
  };
  return { client, channels, emit, emitAuth, authListeners };
}

export interface FakeBrowser extends FakeRealtime {
  readonly browser: ClientLike;
  readonly setAuth: (next: AuthSnapshot) => void;
  readonly listeners: Set<() => void>;
}

export function fakeBrowser(
  initial: AuthSnapshot,
  run?: ClientLike["db"],
): FakeBrowser {
  let snapshot = initial;
  const listeners = new Set<() => void>();
  const realtime = fakeRealtime();
  const browser = {
    betterSupabase,
    supabase: realtime.client,
    auth: {
      current: () => snapshot,
      subscribe: (listener: () => void) => {
        listeners.add(listener);
        return () => void listeners.delete(listener);
      },
    },
    db: run ?? { name: "db" },
    queries: { name: "queries" },
  } as unknown as ClientLike;
  const setAuth = (next: AuthSnapshot): void => {
    snapshot = next;
    for (const listener of [...listeners]) listener();
  };
  return { browser, setAuth, listeners, ...realtime };
}

export const flush = (): Promise<void> =>
  new Promise((resolve) => {
    setTimeout(resolve, 0);
  });

export const wait = (ms: number): Promise<void> =>
  new Promise((resolve) => {
    setTimeout(resolve, ms);
  });

export function cachedClient(...keys: (readonly unknown[])[]): {
  readonly queryClient: QueryClient;
  readonly invalidated: (key: readonly unknown[]) => boolean;
} {
  const queryClient = new QueryClient();
  for (const key of keys) queryClient.setQueryData(key, 1);
  const invalidated = (key: readonly unknown[]): boolean =>
    queryClient.getQueryState(key)?.isInvalidated ?? false;
  return { queryClient, invalidated };
}

export interface FakeJoin {
  values: unknown;
  options: {
    onStatus?: (status: SubscriptionStatus) => void;
    onPresence?: (members: readonly PresenceMember<{ name: string }>[]) => void;
  };
  tracked: unknown[];
  untracked: number;
  left: boolean;
}

/** A presence topic that records each join, track and untrack. */
export function fakePresenceTopic(): {
  readonly topic: PresenceTopic<
    "room:{roomId}",
    { name: string },
    { name: string }
  >;
  readonly joins: FakeJoin[];
} {
  const joins: FakeJoin[] = [];
  const topic: PresenceTopic<
    "room:{roomId}",
    { name: string },
    { name: string }
  > = {
    topic: (values) => `room:${values.roomId}`,
    match: (name) =>
      name.startsWith("room:") ? { roomId: name.slice(5) } : null,
    subscribe: (_client, values, _handlers, options = {}) => {
      const join: FakeJoin = {
        values,
        options,
        tracked: [],
        untracked: 0,
        left: false,
      };
      joins.push(join);
      options.onStatus?.("subscribed");
      return {
        topic: "x",
        ready: Promise.resolve(),
        track: (state: unknown) => {
          join.tracked.push(state);
          return AsyncResult.from(async () => ok(undefined));
        },
        untrack: () => {
          join.untracked += 1;
          return AsyncResult.from(async () => err(dbError("network", "down")));
        },
        members: () => [],
        unsubscribe: async () => {
          join.left = true;
        },
      } as never;
    },
  };
  return { topic, joins };
}
