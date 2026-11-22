import type { HistoryApi, HistoryConfig, IdentityContext } from "chat";

import type { ChatIdentityOptions } from "./identity.ts";

import { chatIdentityOf, resolveChatAuthor } from "./identity.ts";

/** The user key history is stored under for a linked app user. */
export function chatHistoryUserKey(userId: string): string {
  return `user:${userId}`;
}

/** The user key history is stored under for a linked contact. */
export function chatHistoryContactKey(contactId: string): string {
  return `contact:${contactId}`;
}

export interface ChatHistoryOptions extends ChatIdentityOptions {
  /**
   * The platform workspace of a message, such as a Slack team id, when one app
   * serves several workspaces. Pass the same value `chatIdentityOf` gets
   * elsewhere, or the link lookup misses.
   */
  readonly workspaceOf?: (context: IdentityContext) => string | undefined;
  /**
   * Also keep the history of an author linked to a contact. Default false: only
   * linked app users get history.
   */
  readonly contacts?: boolean;
  /** List lifetime, refreshed on every append. Omit for no expiry. */
  readonly retention?: NonNullable<HistoryConfig["user"]>["retention"];
  /** Entries kept per user. Default is the SDK's 200; `false` keeps all. */
  readonly maxPerUser?: NonNullable<HistoryConfig["user"]>["maxPerUser"];
  /** Keep the formatted AST next to the text. Default false. */
  readonly storeFormatted?: boolean;
  /** Passed to `history.thread` as it is. */
  readonly thread?: HistoryConfig["thread"];
}

/**
 * The `history` option of `new Chat(...)`, with the user scope keyed by the
 * app's own identity link instead of an email or a platform id. An author the
 * resolver can't link gets no key, so nothing is stored for them and their
 * history never splits across platforms. Because the key is the linked user,
 * `eraseChatHistory` removes everything stored about that user in one call.
 *
 * ```ts
 * const bot = new Chat({ ..., history: chatHistory({ server, retention: "30d" }) });
 * ```
 */
export function chatHistory(options: ChatHistoryOptions): HistoryConfig {
  const { workspaceOf, contacts = false } = options;

  return {
    user: {
      identity: async (context) => {
        const target = await resolveChatAuthor(
          chatIdentityOf(
            context.author,
            { name: context.adapter },
            workspaceOf?.(context),
          ),
          options,
        );

        if (target === null) {
          return null;
        }

        switch (target.kind) {
          case "user": {
            return chatHistoryUserKey(target.userId);
          }

          case "contact": {
            return contacts ? chatHistoryContactKey(target.contactId) : null;
          }

          default: {
            const unknown: never = target;
            throw new TypeError(`unknown identity target ${String(unknown)}`);
          }
        }
      },
      ...(options.retention === undefined
        ? {}
        : { retention: options.retention }),
      ...(options.maxPerUser === undefined
        ? {}
        : { maxPerUser: options.maxPerUser }),
      ...(options.storeFormatted === undefined
        ? {}
        : { storeFormatted: options.storeFormatted }),
    },
    ...(options.thread === undefined ? {} : { thread: options.thread }),
  };
}

/** Who to erase: an app user, or a contact. */
export type ChatHistoryTarget =
  | { readonly userId: string }
  | { readonly contactId: string };

/**
 * Deletes every entry stored for a user or contact, across platforms and
 * threads, and returns how many. Call it from the account-deletion and data
 * subject request flows. It covers the user scope only: the SDK keeps no index
 * from a user to the thread caches that `persistThreadHistory` adapters write,
 * which expire with `history.thread.ttlMs`.
 */
export async function eraseChatHistory(
  history: Pick<HistoryApi, "user">,
  target: ChatHistoryTarget,
): Promise<{ readonly deleted: number }> {
  const userKey =
    "userId" in target
      ? chatHistoryUserKey(target.userId)
      : chatHistoryContactKey(target.contactId);

  return history.user.delete({ userKey });
}
