"use client";

import type { RealtimeChannel } from "@supabase/supabase-js";

import { REALTIME_SUBSCRIBE_STATES } from "@supabase/supabase-js";
import { useCallback, useEffect, useRef, useState } from "react";

import type { SubscriptionStatus } from "../../../realtime/index.ts";

import { useAuth, useSupabase } from "../../../react/hooks.ts";
import { refreshRealtimeAuth } from "../../../realtime/auth.ts";
import { watchTopic } from "../../react-topic.ts";

/** Loads one list, e.g. a server action that calls `inbox.conversations.list()`. */
export type InboxSource<T> = () => Promise<readonly T[]>;

export interface UseInboxOptions<T> {
  /** The organization; the hook joins `inbox:org:<id>`. `null` waits. */
  readonly organizationId: string | null;
  readonly load: InboxSource<T>;
  /** `sql.modules.inbox.options.topic`. Defaults to `inbox`. */
  readonly topic?: string;
  /** Runs for each broadcast, e.g. to show a toast for `message`. */
  readonly onMessage?: (event: string, payload: unknown) => void;
}

export interface InboxListState<T> {
  /** `undefined` until the first load. */
  readonly items: readonly T[] | undefined;
  readonly status: SubscriptionStatus;
  readonly error: unknown;
  readonly refresh: () => Promise<void>;
}

function useLoader<T>(load: InboxSource<T>) {
  const [items, setItems] = useState<readonly T[] | undefined>(undefined);
  const [error, setError] = useState<unknown>(undefined);
  const latest = useRef(load);
  // oxlint-disable-next-line react/refs -- latest-ref pattern; the react peer range predates useEffectEvent.
  latest.current = load;
  const refresh = useCallback(async () => {
    try {
      setItems(await latest.current());
      setError(undefined);
    } catch (cause) {
      setError(cause);
    }
  }, []);
  return { items, setItems, error, refresh };
}

/**
 * The staff view of an organization's conversations, kept current: loads,
 * then loads again after each ping on `inbox:org:<id>` and on rejoin.
 */
export function useInbox<T>(options: UseInboxOptions<T>): InboxListState<T> {
  const supabase = useSupabase();
  const auth = useAuth();
  const { items, error, refresh } = useLoader(options.load);
  const [status, setStatus] = useState<SubscriptionStatus>("closed");
  const onMessage = useRef(options.onMessage);
  // oxlint-disable-next-line react/refs -- latest-ref pattern; the react peer range predates useEffectEvent.
  onMessage.current = options.onMessage;
  const topic =
    options.organizationId === null
      ? null
      : `${options.topic ?? "inbox"}:org:${options.organizationId}`;

  useEffect(() => {
    if (auth.status !== "signed-in" || topic === null) return;
    void refresh();
    return watchTopic(supabase, topic, {
      onMessage: (event, payload) => {
        onMessage.current?.(event, payload);
        void refresh();
      },
      onRejoin: () => void refresh(),
      onStatus: setStatus,
    });
  }, [supabase, topic, auth.status, refresh]);

  return { items, status, error, refresh };
}

export interface UseConversationOptions<T> {
  /** `null` waits, e.g. before the widget opens a conversation. */
  readonly conversationId: string | null;
  /** The messages, oldest first. */
  readonly load: InboxSource<T>;
  readonly topic?: string;
  /** How long a typing ping counts. Defaults to 5000 ms. */
  readonly typingMs?: number;
}

export interface ConversationState<T> extends InboxListState<T> {
  /** User ids typing now, the caller left out. */
  readonly typing: readonly string[];
  /** Tells the others the caller is typing; call it on input, throttled. */
  readonly setTyping: (typing: boolean) => void;
}

interface ConversationHandlers {
  readonly userId: string | null;
  readonly typingMs: number;
  readonly refresh: () => Promise<void>;
  readonly setStatus: (status: SubscriptionStatus) => void;
  readonly setTypers: (typers: readonly string[]) => void;
  readonly channel: { current: RealtimeChannel | null };
}

/** Joins `topic` for messages and typing pings; returns the function that leaves it. */
function joinConversation(
  supabase: ReturnType<typeof useSupabase>,
  topic: string,
  handlers: ConversationHandlers,
): () => void {
  const { userId, typingMs, refresh, setStatus, setTypers } = handlers;
  let closed = false;
  let joined = false;
  const seen = new Map<string, ReturnType<typeof setTimeout>>();
  const typer = (who: string, on: boolean): void => {
    const timer = seen.get(who);
    if (timer !== undefined) clearTimeout(timer);
    if (on)
      seen.set(
        who,
        setTimeout(() => {
          typer(who, false);
        }, typingMs),
      );
    else seen.delete(who);
    setTypers([...seen.keys()]);
  };
  const joinedChannel = supabase.channel(topic, {
    config: { private: true, broadcast: { self: false } },
  });
  handlers.channel.current = joinedChannel;
  joinedChannel.on("broadcast", { event: "*" }, (message) => {
    const payload: unknown = message["payload"];
    if (message.event === "typing") {
      if (typeof payload !== "object" || payload === null) return;
      const who = "user_id" in payload ? String(payload.user_id) : "";
      if (who !== "" && who !== userId)
        typer(who, !("typing" in payload) || payload.typing !== false);
      return;
    }
    void refresh();
  });
  void (async () => {
    setStatus("joining");
    await refreshRealtimeAuth(supabase);
    // oxlint-disable-next-line typescript/no-unnecessary-condition -- the cleanup can run while the auth refresh is awaited.
    if (closed) return;
    joinedChannel.subscribe((state) => {
      switch (state) {
        case REALTIME_SUBSCRIBE_STATES.SUBSCRIBED:
          if (joined) void refresh();
          joined = true;
          setStatus("subscribed");
          return;
        case REALTIME_SUBSCRIBE_STATES.CLOSED:
          setStatus("closed");
          return;
        case REALTIME_SUBSCRIBE_STATES.CHANNEL_ERROR:
        case REALTIME_SUBSCRIBE_STATES.TIMED_OUT:
          setStatus("error");
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
    for (const timer of seen.values()) clearTimeout(timer);
    handlers.channel.current = null;
    setTypers([]);
    void supabase.removeChannel(joinedChannel);
    setStatus("closed");
  };
}

/**
 * One conversation's messages, kept current over `inbox:<id>`, with typing
 * pings between staff and the contact. Notes never reach this topic.
 */
export function useConversation<T>(
  options: UseConversationOptions<T>,
): ConversationState<T> {
  const supabase = useSupabase();
  const auth = useAuth();
  const { items, error, refresh } = useLoader(options.load);
  const [status, setStatus] = useState<SubscriptionStatus>("closed");
  const [typing, setTypers] = useState<readonly string[]>([]);
  const channel = useRef<RealtimeChannel | null>(null);
  const userId = auth.user?.id ?? null;
  const typingMs = options.typingMs ?? 5000;
  const topic =
    options.conversationId === null
      ? null
      : `${options.topic ?? "inbox"}:${options.conversationId}`;

  useEffect(() => {
    if (auth.status !== "signed-in" || topic === null) return;
    void refresh();
    return joinConversation(supabase, topic, {
      userId,
      typingMs,
      refresh,
      setStatus,
      setTypers,
      channel,
    });
  }, [supabase, topic, auth.status, userId, typingMs, refresh]);

  const setTyping = useCallback(
    (on: boolean) => {
      if (userId === null) return;
      void channel.current?.send({
        type: "broadcast",
        event: "typing",
        payload: { user_id: userId, typing: on },
      });
    },
    [userId],
  );

  return { items, status, error, refresh, typing, setTyping };
}

export interface UseInboxWidgetOptions<T> {
  /**
   * Opens the visitor's conversation, e.g. a server action that calls
   * `inbox.conversations.open(inboxId, { message })` with the visitor's
   * transport. Returns its id.
   */
  readonly open: (message: string) => Promise<string>;
  /** Sends into the open conversation. */
  readonly send: (conversationId: string, message: string) => Promise<void>;
  readonly load: (conversationId: string) => Promise<readonly T[]>;
  /** Remembers the conversation across reloads. Defaults to `better-supabase:inbox-widget`. */
  readonly storageKey?: string | null;
  readonly topic?: string;
}

export interface InboxWidgetState<T> extends ConversationState<T> {
  readonly conversationId: string | null;
  /** Opens the conversation with the first message, or sends into it. */
  readonly submit: (message: string) => Promise<void>;
  /** Forgets the conversation, so the next message opens a new one. */
  readonly reset: () => void;
}

function storage(): Storage | undefined {
  try {
    return typeof localStorage === "undefined" ? undefined : localStorage;
  } catch {
    return undefined;
  }
}

/**
 * The visitor side of an in-app inbox: the first message opens the
 * conversation, later ones go into it, and the messages and typing pings
 * stay current. Visitors without an account sign in anonymously first.
 */
export function useInboxWidget<T>(
  options: UseInboxWidgetOptions<T>,
): InboxWidgetState<T> {
  const key =
    options.storageKey === undefined
      ? "better-supabase:inbox-widget"
      : options.storageKey;
  const [conversationId, setConversationId] = useState<string | null>(() =>
    key === null ? null : (storage()?.getItem(key) ?? null),
  );
  const latest = useRef(options);
  // oxlint-disable-next-line react/refs -- latest-ref pattern; the react peer range predates useEffectEvent.
  latest.current = options;
  const conversation = useConversation<T>({
    conversationId,
    load: () =>
      conversationId === null
        ? Promise.resolve([])
        : latest.current.load(conversationId),
    ...(options.topic === undefined ? {} : { topic: options.topic }),
  });
  const { refresh } = conversation;

  const submit = useCallback(
    async (message: string) => {
      if (conversationId === null) {
        const id = await latest.current.open(message);
        if (key !== null) storage()?.setItem(key, id);
        setConversationId(id);
        return;
      }
      await latest.current.send(conversationId, message);
      await refresh();
    },
    [conversationId, key, refresh],
  );
  const reset = useCallback(() => {
    if (key !== null) storage()?.removeItem(key);
    setConversationId(null);
  }, [key]);

  return { ...conversation, conversationId, submit, reset };
}
