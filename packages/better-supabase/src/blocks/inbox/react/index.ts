"use client";

import { useController, useLatest } from "../../react-controller.ts";
import { useBlockEnv } from "../../react-env.ts";
import {
  type ConversationActions,
  type ConversationSnapshot,
  type InboxListActions,
  type InboxListSnapshot,
  type InboxWidgetActions,
  type InboxWidgetSnapshot,
  createConversationController,
  createInboxController,
  createInboxWidgetController,
  type InboxSource,
} from "../client.ts";

export type { InboxSource } from "../client.ts";

export interface UseInboxOptions<T> {
  /** The organization; the hook joins `inbox:org:<id>`. `null` waits. */
  readonly organizationId: string | null;
  readonly load: InboxSource<T>;
  /** `blockConfig.inbox.options.topic` from `blocks.generated.ts`. Defaults to `inbox`. */
  readonly topic?: string;
  /** Runs for each broadcast, e.g. to show a toast for `message`. */
  readonly onMessage?: (event: string, payload: unknown) => void;
}

export interface InboxListState<T>
  extends InboxListSnapshot<T>, InboxListActions {}

/**
 * The staff view of an organization's conversations, kept current: loads,
 * then loads again after each ping on `inbox:org:<id>` and on rejoin.
 */
export function useInbox<T>(options: UseInboxOptions<T>): InboxListState<T> {
  const { auth, ports } = useBlockEnv();
  const latest = useLatest(options);
  const { organizationId, topic } = options;
  return useController(
    () =>
      createInboxController<T>({
        auth,
        ports,
        organizationId,
        load: () => latest.current.load(),
        onMessage: (event, payload) => {
          latest.current.onMessage?.(event, payload);
        },
        ...(topic === undefined ? {} : { topic }),
      }),
    [auth, ports, organizationId, topic, latest],
  ).view;
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

export interface ConversationState<T>
  extends ConversationSnapshot<T>, ConversationActions {}

/**
 * One conversation's messages, kept current over `inbox:<id>`, with typing
 * pings between staff and the contact. Notes never reach this topic.
 */
export function useConversation<T>(
  options: UseConversationOptions<T>,
): ConversationState<T> {
  const { auth, ports } = useBlockEnv();
  const latest = useLatest(options);
  const { conversationId, topic, typingMs } = options;
  return useController(
    () =>
      createConversationController<T>({
        auth,
        ports,
        conversationId,
        load: () => latest.current.load(),
        ...(topic === undefined ? {} : { topic }),
        ...(typingMs === undefined ? {} : { typingMs }),
      }),
    [auth, ports, conversationId, topic, typingMs, latest],
  ).view;
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
  /**
   * Remembers the conversation across reloads in the client's storage port
   * (`localStorage` on the web). Defaults to `better-supabase:inbox-widget`.
   */
  readonly storageKey?: string | null;
  readonly topic?: string;
}

export interface InboxWidgetState<T>
  extends InboxWidgetSnapshot<T>, InboxWidgetActions {}

/**
 * The visitor side of an in-app inbox: the first message opens the
 * conversation, later ones go into it, and the messages and typing pings
 * stay current. Visitors without an account sign in anonymously first.
 */
export function useInboxWidget<T>(
  options: UseInboxWidgetOptions<T>,
): InboxWidgetState<T> {
  const { auth, ports } = useBlockEnv();
  const latest = useLatest(options);
  const { storageKey, topic } = options;
  return useController(
    () =>
      createInboxWidgetController<T>({
        auth,
        ports,
        open: (message) => latest.current.open(message),
        send: (conversationId, message) =>
          latest.current.send(conversationId, message),
        load: (conversationId) => latest.current.load(conversationId),
        ...(storageKey === undefined ? {} : { storageKey }),
        ...(topic === undefined ? {} : { topic }),
      }),
    [auth, ports, storageKey, topic, latest],
  ).view;
}
