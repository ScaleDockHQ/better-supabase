"use client";

import type {
  ConversationActions,
  ConversationSnapshot,
  Identified,
  InboxListActions,
  InboxListSnapshot,
  InboxWidgetActions,
  InboxWidgetSnapshot,
  InboxSource,
} from "../client.ts";

import { useController, useLatest } from "../../react-controller.ts";
import { useBlockEnv } from "../../react-env.ts";
import {
  createConversationController,
  createInboxController,
  createInboxWidgetController,
} from "../client.ts";

export type { InboxSource } from "../client.ts";

export interface UseInboxOptions<T> {
  /** The organization; the hook joins `inbox:org:<id>`. `null` waits. */
  readonly organizationId: string | null;
  readonly load: InboxSource<T>;
  /**
   * `blockConfig.inbox.options.topic` from `blocks.generated.ts`. Defaults to
   * `inbox`.
   */
  readonly topic?: string;
  /** Runs for each broadcast, e.g. to show a toast for `message`. */
  readonly onMessage?: (event: string, payload: unknown) => void;
}

export interface InboxListState<T>
  extends InboxListSnapshot<T>, InboxListActions {}

/**
 * The staff view of an organization's conversations, kept current: loads, then
 * loads again after each ping on `inbox:org:<id>` and on rejoin.
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

export interface UseConversationOptions<T extends Identified> {
  /** `null` waits, e.g. before the widget opens a conversation. */
  readonly conversationId: string | null;
  /** The messages, oldest first: on mount and after a rejoin. */
  readonly load: InboxSource<T>;
  /** One message after a ping; `null` when the caller cannot read it. */
  readonly get: (messageId: string) => Promise<T | null>;
  /** The messaging topic prefix. Defaults to `messages`. */
  readonly topic?: string;
  /** Runs for the other pings, such as `conversation` and `read`. */
  readonly onEvent?: (event: string, payload: unknown) => void;
  /** How long a typing ping counts. Defaults to 5000 ms. */
  readonly typingMs?: number;
}

export interface ConversationState<T extends Identified>
  extends ConversationSnapshot<T>, ConversationActions {}

/**
 * One conversation's messages, kept current over `messages:<id>`: each ping
 * fetches the one message it names. Typing pings go between staff and the
 * contact.
 */
export function useConversation<T extends Identified>(
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
        get: (messageId) => latest.current.get(messageId),
        onEvent: (event, payload) => {
          latest.current.onEvent?.(event, payload);
        },
        ...(topic === undefined ? {} : { topic }),
        ...(typingMs === undefined ? {} : { typingMs }),
      }),
    [auth, ports, conversationId, topic, typingMs, latest],
  ).view;
}

export interface UseInboxWidgetOptions<T extends Identified> {
  /**
   * Opens the visitor's conversation, e.g. a server action that calls
   * `inbox.conversations.open(inboxId, { message })` with the visitor's
   * transport. Returns its id.
   */
  readonly open: (message: string) => Promise<string>;
  /** Sends into the open conversation. */
  readonly send: (conversationId: string, message: string) => Promise<void>;
  readonly load: (conversationId: string) => Promise<readonly T[]>;
  /** One message after a ping; `null` when the visitor cannot read it. */
  readonly get: (messageId: string) => Promise<T | null>;
  /**
   * Remembers the conversation across reloads in the client's storage port
   * (`localStorage` on the web). Defaults to `better-supabase:inbox-widget`.
   */
  readonly storageKey?: string | null;
  readonly topic?: string;
}

export interface InboxWidgetState<T extends Identified>
  extends InboxWidgetSnapshot<T>, InboxWidgetActions {}

/**
 * The visitor side of an in-app inbox: the first message opens the
 * conversation, later ones go into it, and the messages and typing pings stay
 * current. Visitors without an account sign in anonymously first.
 */
export function useInboxWidget<T extends Identified>(
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
        get: (messageId) => latest.current.get(messageId),
        ...(storageKey === undefined ? {} : { storageKey }),
        ...(topic === undefined ? {} : { topic }),
      }),
    [auth, ports, storageKey, topic, latest],
  ).view;
}
