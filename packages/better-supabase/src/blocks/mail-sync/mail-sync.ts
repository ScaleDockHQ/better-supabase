import type { BlockHooks } from "../../core/block-hooks.ts";
import type { BlockTransport } from "../../core/block-transport.ts";
import type { ErrorMapper } from "../../core/errors.ts";
import type { Logger } from "../../core/logger.ts";
import type { Result } from "../../core/result.ts";
import type {
  CredentialProvider,
  CredentialRef,
  CredentialToken,
} from "../../credentials/provider.ts";
import type { BlockTemporalOptions } from "../shared.ts";
import type {
  MailAddress,
  MailDraft,
  MailProvider,
  MailProviderMessage,
  MailReplyTarget,
} from "./providers.ts";

import { withBlockHooks } from "../../core/block-hooks.ts";
import { dbError } from "../../core/errors.ts";
import { AsyncResult, err, ok } from "../../core/result.ts";
import { temporal } from "../../core/temporal-required.ts";
import {
  credentialRefInTenant,
  foreignCredentialRef,
} from "../../credentials/provider.ts";
import {
  applyTemporal,
  blockCall,
  instantArg,
  isRecord,
  optionalInstant,
  optionalText,
  recordOf,
  recordsOf,
  requiredInstant,
  textOf,
} from "../shared.ts";
import { mailProviderOf } from "./providers.ts";
import {
  pixelResponse,
  trackHtml,
  trackingHash,
  trackingHitOf,
} from "./tracking.ts";

/** A record a thread is linked to. */
export interface MailSubject {
  readonly type: string;
  readonly id: string;
}

/** A member's connected mailbox. */
export interface MailAccount {
  readonly id: string;
  readonly organizationId: string;
  /** The member whose mailbox it is. */
  readonly userId: string;
  /** `gmail`, `outlook` or a custom provider's name. */
  readonly provider: string;
  readonly address: string;
  /** The member's OAuth grant, resolved by the `credentials` provider. */
  readonly credentialRef: CredentialRef;
  /**
   * `records`: members who can read a linked record see the thread, and it is
   * logged as an engagement. `private`: only the member sees it.
   */
  readonly share: "records" | "private";
  readonly status: "active" | "paused" | "error" | "disconnected";
  readonly cursor?: string;
  readonly lastSyncedAt?: Temporal.Instant;
  readonly lastError?: string;
  /**
   * The grant is gone or needs consent again
   * (`CREDENTIAL_AUTHORIZATION_REQUIRED` or `CREDENTIAL_NOT_FOUND`): show a
   * Reconnect button, not a retry.
   */
  readonly reconnect: boolean;
  readonly createdAt: Temporal.Instant;
}

/** A conversation in one mailbox. */
export interface MailThread {
  readonly id: string;
  readonly organizationId: string;
  readonly accountId: string;
  /** The mailbox's address. */
  readonly address: string;
  readonly externalId: string;
  readonly subject?: string;
  readonly snippet?: string;
  readonly lastMessageAt?: Temporal.Instant;
  readonly messageCount: number;
  /** The engagement the thread is logged as, with `engagements` installed. */
  readonly engagementId?: string;
  readonly subjects: readonly MailSubject[];
}

/** A stored message. */
export interface MailMessage {
  readonly id: string;
  readonly threadId: string;
  readonly accountId: string;
  readonly externalId: string;
  /** The RFC 5322 `Message-ID`. */
  readonly messageId?: string;
  readonly direction: "inbound" | "outbound";
  readonly from?: MailAddress;
  readonly to: readonly string[];
  readonly cc: readonly string[];
  readonly subject?: string;
  readonly snippet?: string;
  readonly text?: string;
  readonly html?: string;
  readonly sentAt: Temporal.Instant;
  /** The template version a sent message was written from. */
  readonly templateVersionId?: string;
  /** Whether opens and clicks of a sent message are tracked. */
  readonly tracked: boolean;
  readonly openCount: number;
  readonly clickCount: number;
  /** The first open; a click counts as one. */
  readonly openedAt?: Temporal.Instant;
  readonly clickedAt?: Temporal.Instant;
}

/** How the messages sent from one template version did. */
export interface MailTemplateStats {
  readonly templateVersionId: string;
  readonly sent: number;
  readonly opened: number;
  readonly clicked: number;
  /** Messages whose thread got an inbound message after them. */
  readonly replied: number;
}

/** A thread with its messages, oldest first. */
export interface MailThreadDetail extends MailThread {
  readonly messages: readonly MailMessage[];
}

/** What one sync run did. */
export interface MailSyncReport {
  readonly accounts: number;
  readonly stored: number;
  /** The mailboxes that failed, marked `error` with the message. */
  readonly failed: readonly {
    readonly accountId: string;
    readonly message: string;
    /** The member has to connect the mailbox again. */
    readonly reconnect: boolean;
  }[];
}

export interface MailSendDraft extends MailDraft {
  /** Replies on this thread, to its latest message. */
  readonly threadId?: string;
  /**
   * The template version the draft was written from, such as a `templates`
   * version, for `templateStats`.
   */
  readonly templateVersionId?: string;
  /**
   * Tracks opens and clicks of the HTML body. Default: on when `createMailSync`
   * has `tracking`; `true` without it is an error.
   */
  readonly track?: boolean;
}

export interface MailSync {
  /**
   * Connects the caller's mailbox. `credentialRef` names the OAuth grant the
   * app stored for them, with the organization as its `tenant`.
   */
  connect(
    organizationId: string,
    input: {
      readonly provider: string;
      readonly address: string;
      readonly credentialRef: CredentialRef;
      readonly share?: "records" | "private";
    },
  ): AsyncResult<MailAccount>;
  /** Changes who sees the mailbox's threads, or pauses its sync. */
  update(
    accountId: string,
    input: {
      readonly share?: "records" | "private";
      readonly paused?: boolean;
    },
  ): AsyncResult<MailAccount>;
  /** Stops syncing; `purge` deletes its threads and messages too. */
  disconnect(
    accountId: string,
    options?: { readonly purge?: boolean },
  ): AsyncResult<boolean>;
  /** The caller's mailboxes; every member's with `mail.manage`. */
  accounts(organizationId: string): AsyncResult<MailAccount[]>;
  /** The threads the caller can see, the latest first (25, at most 100). */
  threads(
    organizationId: string,
    options?: {
      readonly accountId?: string;
      readonly before?: Temporal.Instant;
      readonly limit?: number;
    },
  ): AsyncResult<MailThread[]>;
  /** A record's threads the caller can see, the latest first. */
  threadsOf(
    subject: MailSubject,
    options?: { readonly before?: Temporal.Instant; readonly limit?: number },
  ): AsyncResult<MailThread[]>;
  /** A thread with its messages, or `undefined` when the caller can't see it. */
  thread(id: string): AsyncResult<MailThreadDetail | undefined>;
  /** Links a thread of the caller's mailbox to records by hand. */
  link(
    threadId: string,
    subjects: readonly MailSubject[],
  ): AsyncResult<MailThread>;
  unlink(threadId: string, subject: MailSubject): AsyncResult<boolean>;
  /**
   * Sends from the caller's mailbox through its provider and stores the message
   * on its thread. Needs `credentials` and the provider.
   */
  send(accountId: string, draft: MailSendDraft): AsyncResult<MailMessage>;
  /**
   * Pulls one mailbox's new mail into the database, page by page. Runs as the
   * service role (a job or a cron route).
   */
  sync(
    account: MailAccount,
    options?: { readonly pages?: number; readonly limit?: number },
  ): AsyncResult<number>;
  /**
   * Answers a request to the tracking route: records the open or click and
   * returns the pixel, or a redirect to the link the message had. Service
   * role.
   */
  track(request: Request): AsyncResult<Response>;
  /** Opens, clicks and replies per template version, since a time. */
  templateStats(
    organizationId: string,
    options?: { readonly since?: Temporal.Instant },
  ): AsyncResult<MailTemplateStats[]>;
  /** Syncs the mailboxes not synced within `staleAfter`. Service role. */
  syncDue(options?: {
    /** At most this many mailboxes. Default: 25. */
    readonly accounts?: number;
    /** A Postgres interval. Default: `5 minutes`. */
    readonly staleAfter?: string;
    readonly pages?: number;
    readonly limit?: number;
  }): AsyncResult<MailSyncReport>;
}

export interface MailSyncOptions extends BlockTemporalOptions {
  readonly transport: BlockTransport;
  /**
   * The module schema, or its API schema: `defineBlocks` passes it from
   * `blocks.generated.ts`.
   */
  readonly schema?: string;
  /** Resolves each mailbox's grant to a token, for `send` and `sync`. */
  readonly credentials?: CredentialProvider;
  /** The mail providers, such as `gmailMail()` and `outlookMail()`. */
  readonly providers?: readonly MailProvider[];
  /**
   * Tracks opens and clicks: `url` is the public route that calls `track`, such
   * as `https://app.example.com/api/mail/t`.
   */
  readonly tracking?: { readonly url: string };
  readonly hooks?: NoInfer<BlockHooks<MailSync>>;
  readonly logger?: Logger;
  readonly mappers?: readonly ErrorMapper[];
}

const SHARES = new Set(["records", "private"]);

const RECONNECT_HINTS = [
  "CREDENTIAL_AUTHORIZATION_REQUIRED",
  "CREDENTIAL_NOT_FOUND",
] as const;

/** The stored error starts with the hint, so `reconnect` survives a reload. */
const needsReconnect = (error: string | undefined): boolean =>
  error !== undefined &&
  RECONNECT_HINTS.some((hint) => error.startsWith(`${hint}: `));

const STATUSES = new Set(["active", "paused", "error", "disconnected"]);

function accountOf(value: unknown): MailAccount {
  const row = recordOf(value, "mail account");
  const share = textOf(row["share"]);
  const status = textOf(row["status"]);
  const ref = row["credential_ref"];

  if (!SHARES.has(share) || !STATUSES.has(status) || !isRecord(ref)) {
    throw new TypeError(`mail account returned ${JSON.stringify(row)}`);
  }

  const optional = {
    cursor: optionalText(row["sync_cursor"]),
    lastSyncedAt: optionalInstant(row["last_synced_at"]),
    lastError: optionalText(row["last_error"]),
  };

  return {
    id: textOf(row["id"]),
    organizationId: textOf(row["tenant_id"]),
    userId: textOf(row["user_id"]),
    provider: textOf(row["provider"]),
    address: textOf(row["address"]),
    credentialRef: { ...ref, provider: textOf(ref["provider"]) },
    share: share === "private" ? "private" : "records",
    status:
      status === "paused" || status === "error" || status === "disconnected"
        ? status
        : "active",
    reconnect: needsReconnect(optional.lastError),
    createdAt: requiredInstant(row["created_at"], "createdAt"),
    ...Object.fromEntries(
      Object.entries(optional).filter(([, entry]) => entry !== undefined),
    ),
  };
}

const subjectsOf = (value: unknown): MailSubject[] =>
  recordsOf(value, "mail thread subjects").map((subject) => ({
    type: textOf(subject["type"]),
    id: textOf(subject["id"]),
  }));

function threadOf(value: unknown): MailThread {
  const row = recordOf(value, "mail thread");

  const optional = {
    subject: optionalText(row["subject"]),
    snippet: optionalText(row["snippet"]),
    lastMessageAt: optionalInstant(row["last_message_at"]),
    engagementId: optionalText(row["engagement_id"]),
  };

  return {
    id: textOf(row["id"]),
    organizationId: textOf(row["tenant_id"]),
    accountId: textOf(row["account_id"]),
    address: textOf(row["address"]),
    externalId: textOf(row["external_id"]),
    messageCount: Number(row["message_count"] ?? 0),
    subjects: subjectsOf(row["subjects"]),
    ...Object.fromEntries(
      Object.entries(optional).filter(([, entry]) => entry !== undefined),
    ),
  };
}

const texts = (value: unknown): string[] =>
  Array.isArray(value) ? value.map(textOf) : [];

function messageOf(value: unknown): MailMessage {
  const row = recordOf(value, "mail message");
  const address = optionalText(row["from_address"]);
  const name = optionalText(row["from_name"]);

  const optional = {
    messageId: optionalText(row["rfc_message_id"]),
    from:
      address === undefined
        ? undefined
        : name === undefined
          ? { address }
          : { address, name },
    subject: optionalText(row["subject"]),
    snippet: optionalText(row["snippet"]),
    text: optionalText(row["body_text"]),
    html: optionalText(row["body_html"]),
    templateVersionId: optionalText(row["template_version_id"]),
    openedAt: optionalInstant(row["opened_at"]),
    clickedAt: optionalInstant(row["clicked_at"]),
  };

  return {
    id: textOf(row["id"]),
    threadId: textOf(row["thread_id"]),
    accountId: textOf(row["account_id"]),
    externalId: textOf(row["external_id"]),
    direction: row["direction"] === "outbound" ? "outbound" : "inbound",
    to: texts(row["to_addresses"]),
    cc: texts(row["cc_addresses"]),
    sentAt: requiredInstant(row["sent_at"], "sentAt"),
    tracked: typeof row["tracking_hash"] === "string",
    openCount: Number(row["open_count"] ?? 0),
    clickCount: Number(row["click_count"] ?? 0),
    ...Object.fromEntries(
      Object.entries(optional).filter(([, entry]) => entry !== undefined),
    ),
  };
}

function detailOf(value: unknown): MailThreadDetail | undefined {
  if (value === null || value === undefined) {
    return undefined;
  }

  const row = recordOf(value, "mail thread");

  return {
    ...threadOf(row),
    messages: recordsOf(row["messages"], "mail messages").map(messageOf),
  };
}

/** A provider message as `ingest_mail` and `record_sent_mail` take it. */
export function messageArg(
  message: MailProviderMessage,
): Record<string, unknown> {
  return {
    externalId: message.externalId,
    threadId: message.threadId,
    sentAt: message.sentAt.toString(),
    to: message.to,
    cc: message.cc,
    ...(message.messageId === undefined
      ? {}
      : { messageId: message.messageId }),
    ...(message.direction === undefined
      ? {}
      : { direction: message.direction }),
    ...(message.from === undefined ? {} : { from: message.from }),
    ...(message.subject === undefined ? {} : { subject: message.subject }),
    ...(message.snippet === undefined ? {} : { snippet: message.snippet }),
    ...(message.text === undefined ? {} : { text: message.text }),
    ...(message.html === undefined ? {} : { html: message.html }),
  };
}

const missing = (message: string, hint: string) =>
  dbError("invalid_input", message, { hint });

/**
 * The mail-sync block: members connect Gmail, Outlook or another provider with
 * their own OAuth grant; a job pulls their mail into threads linked to the
 * people and companies on them, logged as email engagements; `send` sends from
 * the member's mailbox and stores the message.
 */
export function createMailSync(options: MailSyncOptions): MailSync {
  applyTemporal(options);
  const call = blockCall(options.transport, options.schema, options.mappers);

  const providers = new Map(
    (options.providers ?? []).map((provider) => [
      provider.name,
      mailProviderOf(provider),
    ]),
  );

  const providerOf = (account: MailAccount): Result<MailProvider> => {
    const provider = providers.get(account.provider);

    return provider === undefined
      ? err(
          missing(
            `createMailSync has no provider "${account.provider}"`,
            "MAIL_PROVIDER_MISSING",
          ),
        )
      : ok(provider);
  };

  const tokenOf = (
    account: MailAccount,
    provider: MailProvider,
  ): AsyncResult<CredentialToken> => {
    const credentials = options.credentials;

    if (credentials === undefined) {
      return AsyncResult.err(
        missing(
          "createMailSync needs credentials to resolve mailbox grants",
          "MAIL_CREDENTIALS_MISSING",
        ),
      );
    }

    if (!credentialRefInTenant(account.credentialRef, account.organizationId)) {
      return AsyncResult.err(foreignCredentialRef(account.organizationId));
    }

    return credentials.getToken(account.credentialRef, {
      subject: { type: "user", id: account.userId },
      ...(provider.scopes === undefined ? {} : { scopes: provider.scopes }),
    });
  };

  const thread = (id: string): AsyncResult<MailThreadDetail | undefined> =>
    call("get_mail_thread", { thread: id }, detailOf);

  const replyTarget = (
    threadId: string | undefined,
  ): AsyncResult<MailReplyTarget | undefined> =>
    threadId === undefined
      ? AsyncResult.ok(undefined)
      : thread(threadId).andThen((found) => {
          const last = found?.messages.at(-1);

          if (found === undefined || last === undefined) {
            return AsyncResult.err(
              dbError("not_found", "no such thread with messages", {
                hint: "MAIL_THREAD_NOT_FOUND",
              }),
            );
          }

          return AsyncResult.ok({
            threadId: found.externalId,
            externalId: last.externalId,
            ...(last.messageId === undefined
              ? {}
              : { messageId: last.messageId }),
          });
        });

  const sync: MailSync["sync"] = (account, run = {}) =>
    AsyncResult.from(async () => {
      const provider = providerOf(account);

      if (!provider.ok) {
        return provider;
      }

      const token = await tokenOf(account, provider.data);

      if (!token.ok) {
        return token;
      }

      let cursor = account.cursor;
      let stored = 0;

      for (let page = 0; page < (run.pages ?? 5); page += 1) {
        const listed = await provider.data.list({
          token: token.data,
          limit: run.limit ?? 50,
          ...(cursor === undefined ? {} : { cursor }),
        });

        if (!listed.ok) {
          return listed;
        }

        const ingested = await call(
          "ingest_mail",
          {
            account: account.id,
            messages: listed.data.messages.map(messageArg),
            next_cursor: listed.data.cursor,
          },
          (value) => Number(recordOf(value, "ingest_mail")["stored"] ?? 0),
        );

        if (!ingested.ok) {
          return ingested;
        }

        stored += ingested.data;
        cursor = listed.data.cursor;

        if (!listed.data.more) {
          break;
        }
      }

      return ok(stored);
    });

  const sendMail = (
    accountId: string,
    draft: MailSendDraft,
  ): AsyncResult<MailMessage> =>
    call("get_mail_account", { account: accountId }, (value) =>
      value === null ? undefined : accountOf(value),
    ).andThen(async (account) => {
      if (account === undefined || account.status === "disconnected") {
        return err(
          dbError("not_found", "no such connected mailbox", {
            hint: "MAIL_ACCOUNT_NOT_FOUND",
          }),
        );
      }

      const provider = providerOf(account);

      if (!provider.ok) {
        return provider;
      }

      const reply = await replyTarget(draft.threadId);

      if (!reply.ok) {
        return reply;
      }

      const token = await tokenOf(account, provider.data);

      if (!token.ok) {
        return token;
      }

      const from = { address: account.address };
      const { threadId: _thread, templateVersionId, track, ...message } = draft;

      const tracked =
        options.tracking === undefined ||
        track === false ||
        draft.html === undefined
          ? undefined
          : await trackHtml(draft.html, options.tracking.url);

      const sent = await provider.data.send({
        token: token.data,
        from,
        draft:
          tracked === undefined ? message : { ...message, html: tracked.html },
        ...(reply.data === undefined ? {} : { reply: reply.data }),
      });

      if (!sent.ok) {
        return sent;
      }

      return call(
        "record_sent_mail",
        {
          account: account.id,
          message: {
            ...(templateVersionId === undefined ? {} : { templateVersionId }),
            ...(tracked === undefined
              ? {}
              : { trackingHash: tracked.hash, trackedLinks: tracked.links }),
            ...messageArg({
              externalId: sent.data.externalId,
              threadId: sent.data.threadId,
              ...(sent.data.messageId === undefined
                ? {}
                : { messageId: sent.data.messageId }),
              direction: "outbound",
              from,
              to: draft.to,
              cc: draft.cc ?? [],
              subject: draft.subject,
              ...(draft.text === undefined
                ? {}
                : { text: draft.text, snippet: draft.text.slice(0, 200) }),
              ...(draft.html === undefined ? {} : { html: draft.html }),
              sentAt: temporal().Now.instant(),
            }),
          },
        },
        messageOf,
      );
    });

  const client: MailSync = {
    connect: (organizationId, input) =>
      call(
        "connect_mail_account",
        {
          tenant: organizationId,
          provider: input.provider,
          address: input.address,
          credential_ref: input.credentialRef,
          share: input.share ?? null,
        },
        accountOf,
      ),
    update: (accountId, input) =>
      call(
        "update_mail_account",
        {
          account: accountId,
          share: input.share ?? null,
          paused: input.paused ?? null,
        },
        accountOf,
      ),
    disconnect: (accountId, disconnect = {}) =>
      call(
        "disconnect_mail_account",
        { account: accountId, purge: disconnect.purge ?? false },
        (value) => value === true,
      ),
    accounts: (organizationId) =>
      call("mail_accounts_of", { tenant: organizationId }, (value) =>
        recordsOf(value, "mail_accounts_of").map(accountOf),
      ),
    threads: (organizationId, list = {}) =>
      call(
        "list_mail_threads",
        {
          tenant: organizationId,
          account: list.accountId ?? null,
          before: instantArg(list.before) ?? null,
          page_size: list.limit ?? null,
        },
        (value) => recordsOf(value, "list_mail_threads").map(threadOf),
      ),
    threadsOf: (subject, list = {}) =>
      call(
        "mail_threads_of",
        {
          subject_type: subject.type,
          subject_id: subject.id,
          before: instantArg(list.before) ?? null,
          page_size: list.limit ?? null,
        },
        (value) => recordsOf(value, "mail_threads_of").map(threadOf),
      ),
    thread,
    link: (threadId, subjects) =>
      call(
        "link_mail_thread",
        {
          thread: threadId,
          subjects: subjects.map((subject) => ({
            type: subject.type,
            id: subject.id,
          })),
        },
        threadOf,
      ),
    unlink: (threadId, subject) =>
      call(
        "unlink_mail_thread",
        {
          thread: threadId,
          subject_type: subject.type,
          subject_id: subject.id,
        },
        (value) => value === true,
      ),
    send: (accountId, draft) =>
      draft.track === true && options.tracking === undefined
        ? AsyncResult.err(
            missing(
              "createMailSync needs tracking to track a message",
              "MAIL_TRACKING_MISSING",
            ),
          )
        : sendMail(accountId, draft),
    sync,
    track: (request) =>
      AsyncResult.from(async () => {
        const hit = trackingHitOf(request.url);

        if (hit === undefined) {
          return ok(new Response(null, { status: 404 }));
        }

        const tracked = await call(
          "track_mail",
          {
            hash: await trackingHash(hit.token),
            kind: hit.kind,
            link: hit.kind === "click" ? hit.position : null,
            user_agent:
              request.headers.get("user-agent")?.slice(0, 300) ?? null,
          },
          (value) =>
            value === null
              ? undefined
              : optionalText(recordOf(value, "track_mail")["url"]),
        );

        if (!tracked.ok) {
          return tracked;
        }

        if (hit.kind === "open") {
          return ok(pixelResponse());
        }

        return ok(
          tracked.data === undefined
            ? new Response(null, { status: 404 })
            : Response.redirect(tracked.data, 302),
        );
      }),
    templateStats: (organizationId, stats = {}) =>
      call(
        "mail_template_stats",
        { tenant: organizationId, since: instantArg(stats.since) ?? null },
        (value) =>
          recordsOf(value, "mail_template_stats").map((row) => ({
            templateVersionId: String(row["templateVersionId"]),
            sent: Number(row["sent"]),
            opened: Number(row["opened"]),
            clicked: Number(row["clicked"]),
            replied: Number(row["replied"]),
          })),
      ),
    syncDue: (run = {}) =>
      call(
        "due_mail_accounts",
        {
          max_count: run.accounts ?? null,
          stale_after: run.staleAfter ?? null,
        },
        (value) => recordsOf(value, "due_mail_accounts").map(accountOf),
      ).andThen(async (accounts) => {
        let stored = 0;

        const failed: {
          accountId: string;
          message: string;
          reconnect: boolean;
        }[] = [];

        for (const account of accounts) {
          const result = await sync(account, {
            ...(run.pages === undefined ? {} : { pages: run.pages }),
            ...(run.limit === undefined ? {} : { limit: run.limit }),
          });

          if (result.ok) {
            stored += result.data;
            continue;
          }

          const hint = "hint" in result.error ? result.error.hint : undefined;

          const message = RECONNECT_HINTS.some((known) => known === hint)
            ? `${String(hint)}: ${result.error.message}`
            : result.error.message;

          failed.push({
            accountId: account.id,
            message,
            reconnect: needsReconnect(message),
          });

          const status =
            result.error.kind === "rate_limited" ? "active" : "error";

          const marked = await call(
            "set_mail_account_status",
            { account: account.id, status, error: message },
            (value) => value === true,
          );

          if (!marked.ok) {
            return marked;
          }
        }

        return ok({ accounts: accounts.length, stored, failed });
      }),
  };

  return withBlockHooks(client, options.hooks, {
    block: "mail-sync",
    ...(options.logger ? { logger: options.logger } : {}),
  });
}
