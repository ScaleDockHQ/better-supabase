import type { Author } from "chat";

import type {
  ApprovalRequestRef,
  AuthorizationHooks,
  ChatAction,
  ChatActionHook,
  IdentityRef,
  IdentityTarget,
  PrincipalByIdentity,
} from "../core/contracts/authorization-hooks.ts";

/** Where the chat helpers find `principalByIdentity` and `onAction`. */
export interface ChatIdentityOptions {
  /** Wins over `server.authorization.identities.principalByIdentity`. */
  readonly principalByIdentity?: PrincipalByIdentity;
  /**
   * `createServer(...)`: its `authorization` hooks fill the slots this call
   * leaves out.
   */
  readonly server?: { readonly authorization: AuthorizationHooks | undefined };
}

/**
 * The `IdentityRef` of a Chat SDK author: `kind: "chat"`, the adapter name as
 * the provider and the platform's user id. Pass `workspace` (a Slack team id)
 * when one app serves several workspaces.
 */
export function chatIdentityOf(
  author: Pick<Author, "userId">,
  adapter: { readonly name: string },
  workspace?: string,
): IdentityRef {
  return {
    kind: "chat",
    provider: adapter.name,
    value: author.userId,
    ...(workspace === undefined ? {} : { workspace }),
  };
}

/**
 * The user or contact `identity` is linked to; `null` without a resolver or a
 * link.
 */
export async function resolveChatAuthor(
  identity: IdentityRef,
  options: ChatIdentityOptions,
): Promise<IdentityTarget | null> {
  const resolve =
    options.principalByIdentity ??
    options.server?.authorization?.identities?.principalByIdentity;

  return resolve ? ((await resolve(identity)) ?? null) : null;
}

/**
 * What a bot job is enqueued with: a ticket for a linked user, nothing
 * otherwise.
 */
export interface BotJobEnqueueOptions {
  readonly ticket?: string;
}

export interface BotJobsOptions<P, R> extends ChatIdentityOptions {
  /**
   * Enqueues the job, such as `(payload, options) => jobs.enqueue("bot",
   * payload, options)`. Pass `options` through as is: it never carries a
   * context, so an unlinked author's job runs without a user.
   */
  readonly enqueue: (payload: P, options: BotJobEnqueueOptions) => R;
  /**
   * Issues the opaque ticket the job runs as for a linked user. The provider's
   * `tickets.subject` turns it back into that user's context in `forContext`.
   */
  readonly ticketFor: (userId: string) => string | Promise<string>;
}

export interface EnqueuedBotJob<R> {
  /** What `enqueue` returned. */
  readonly result: Awaited<R>;
  /** The author's link: a ticket was issued only for `kind: "user"`. */
  readonly author: IdentityTarget | null;
}

export interface BotJobs<P, R> {
  /**
   * Resolves the author, then enqueues `payload` with a ticket for a linked
   * user. An unlinked author, or one linked to a contact, gets no ticket and no
   * user context; the job never falls back to the bot's service role. A
   * resolver or ticket error rejects without enqueuing.
   */
  enqueue(author: IdentityRef, payload: P): Promise<EnqueuedBotJob<R>>;
}

/** Enqueues bot jobs that run as the chat author's linked user. */
export function botJobs<P, R>(options: BotJobsOptions<P, R>): BotJobs<P, R> {
  return {
    async enqueue(identity, payload) {
      const author = await resolveChatAuthor(identity, options);

      if (author?.kind !== "user") {
        return { result: await options.enqueue(payload, {}), author };
      }

      const ticket = await options.ticketFor(author.userId);

      if (typeof ticket !== "string" || ticket === "") {
        throw new TypeError("botJobs: ticketFor returned an empty ticket");
      }

      return { result: await options.enqueue(payload, { ticket }), author };
    },
  };
}

/** A Chat SDK `ActionEvent` as the `ChatAction` the provider decides. */
export function chatActionOf(
  event: {
    readonly actionId: string;
    readonly value?: string;
    readonly user: Pick<Author, "userId">;
    readonly adapter: { readonly name: string };
  },
  workspace?: string,
): ChatAction {
  return {
    id: event.actionId,
    ...(event.value === undefined ? {} : { value: event.value }),
    author: chatIdentityOf(event.user, event.adapter, workspace),
  };
}

/** Why a chat action was refused. */
export type ChatActionRefusal =
  /** The author has no link, so no one is acting. */
  | "unlinked"
  /** No `onAction` hook, or it returned `undefined`. */
  | "unhandled"
  /** The hook returned `allowed: false`, or a user other than the author. */
  | "refused"
  /** The resolver or the hook threw. */
  | "error";

export type ChatActionDecision =
  | {
      readonly allowed: true;
      readonly author: IdentityTarget;
      /**
       * The user who acts: the linked author, or the user the hook named for a
       * contact.
       */
      readonly userId?: string;
    }
  | { readonly allowed: false; readonly reason: ChatActionRefusal };

export interface ChatActionsOptions extends ChatIdentityOptions {
  /** Wins over `server.authorization.chat.onAction`. */
  readonly onAction?: ChatActionHook;
}

/**
 * Decides a chat button press through the provider: the author is resolved,
 * then `onAction(action, author)` runs. Everything but `allowed: true` refuses,
 * and an unlinked author is refused before the hook runs. Act on the decision,
 * never on the button alone.
 */
export function chatActions(
  options: ChatActionsOptions,
): (action: ChatAction) => Promise<ChatActionDecision> {
  return async (action) => {
    const hook =
      options.onAction ?? options.server?.authorization?.chat?.onAction;

    let author: IdentityTarget | null;

    try {
      author = await resolveChatAuthor(action.author, options);
    } catch {
      return { allowed: false, reason: "error" };
    }

    if (author === null) {
      return { allowed: false, reason: "unlinked" };
    }

    if (!hook) {
      return { allowed: false, reason: "unhandled" };
    }

    let decision: Awaited<ReturnType<ChatActionHook>>;

    try {
      decision = await hook(action, author);
    } catch {
      return { allowed: false, reason: "error" };
    }

    if (decision === undefined) {
      return { allowed: false, reason: "unhandled" };
    }

    if (!decision.allowed) {
      return { allowed: false, reason: "refused" };
    }

    switch (author.kind) {
      case "user": {
        return decision.userId === undefined ||
          decision.userId === author.userId
          ? { allowed: true, author, userId: author.userId }
          : { allowed: false, reason: "refused" };
      }

      case "contact": {
        return decision.userId === undefined
          ? { allowed: true, author }
          : { allowed: true, author, userId: decision.userId };
      }

      default: {
        const unknown: never = author;
        throw new TypeError(`unknown identity target ${String(unknown)}`);
      }
    }
  };
}

export interface ApprovalPromptOptions {
  /** The app's approval page, such as `https://app.example.com/approvals`. */
  readonly page: string | URL;
  readonly request: ApprovalRequestRef;
  /** The message above the link. */
  readonly text?: string;
  /** The link text. Defaults to `Review the request`. */
  readonly label?: string;
}

/**
 * The approval page URL for `request`, with `kind` and `subject` as query
 * parameters. Opening it approves nothing: the signed-in approver decides on
 * the page, and the page's server action or POST route checks them.
 */
export function approvalLink(
  page: string | URL,
  request: ApprovalRequestRef,
): string {
  const url = new URL(page);
  url.searchParams.set("kind", request.kind);
  url.searchParams.set("subject", request.subject);

  return url.toString();
}

const escapeLabel = (label: string): string =>
  label.replaceAll(/[[\]\\]/g, (char) => `\\${char}`);

/** A chat message that links to the approval page, for `thread.post`. */
export function approvalPrompt(options: ApprovalPromptOptions): {
  readonly markdown: string;
} {
  const link = `[${escapeLabel(options.label ?? "Review the request")}](${approvalLink(options.page, options.request).replaceAll(")", "%29")})`;

  return {
    markdown: options.text === undefined ? link : `${options.text}\n\n${link}`,
  };
}
