import type { Result } from "../../core/result.ts";
import type { CredentialToken } from "../../credentials/provider.ts";

import { dbError } from "../../core/errors.ts";
import { isRecord } from "../../core/guards.ts";
import { AsyncResult, err, ok } from "../../core/result.ts";
import { temporal } from "../../core/temporal-required.ts";

/** An address on a message, with the display name when the provider has one. */
export interface MailAddress {
  readonly address: string;
  readonly name?: string;
}

/** A message as a provider returns it, before it is stored. */
export interface MailProviderMessage {
  /** The provider's id for the message. */
  readonly externalId: string;
  /** The provider's id for the thread or conversation. */
  readonly threadId: string;
  /** The RFC 5322 `Message-ID`, which matches a sent message to its copy. */
  readonly messageId?: string;
  /** Left out, it is `outbound` when `from` is the mailbox's own address. */
  readonly direction?: "inbound" | "outbound";
  readonly from?: MailAddress;
  readonly to: readonly MailAddress[];
  readonly cc: readonly MailAddress[];
  readonly subject?: string;
  readonly snippet?: string;
  readonly text?: string;
  readonly html?: string;
  readonly sentAt: Temporal.Instant;
}

/** One page of a mailbox's changes since `cursor`. */
export interface MailPage {
  readonly messages: readonly MailProviderMessage[];
  /** Where the next page starts; the sync stores it on the mailbox. */
  readonly cursor: string;
  /** More changes wait behind `cursor` right now. */
  readonly more: boolean;
}

/** What the block sends: the provider builds the message from it. */
export interface MailDraft {
  readonly to: readonly MailAddress[];
  readonly cc?: readonly MailAddress[];
  readonly bcc?: readonly MailAddress[];
  readonly subject: string;
  readonly text?: string;
  readonly html?: string;
}

/** The message a reply answers, in the provider's ids. */
export interface MailReplyTarget {
  readonly threadId: string;
  readonly externalId: string;
  readonly messageId?: string;
}

/** What a provider returns for a sent message. */
export interface MailSent {
  readonly externalId: string;
  readonly threadId: string;
  readonly messageId?: string;
}

export interface MailListInput {
  readonly token: CredentialToken;
  /** Unset on a mailbox's first sync. */
  readonly cursor?: string;
  /** At most this many messages per page. */
  readonly limit: number;
  readonly signal?: AbortSignal;
}

export interface MailSendInput {
  readonly token: CredentialToken;
  readonly from: MailAddress;
  readonly draft: MailDraft;
  readonly reply?: MailReplyTarget;
  readonly signal?: AbortSignal;
}

/**
 * Reads and sends a member's mail with a token from their OAuth grant.
 * Versioned: a breaking change to this contract ships a new `apiVersion`.
 * Errors are `DbError`s: `unauthorized` for a token the provider refuses,
 * `rate_limited` with `retryAfter`, `network` for a provider outage.
 */
export interface MailProvider {
  readonly apiVersion: 1;
  /** The name a mailbox's `provider` column holds, such as `gmail`. */
  readonly name: string;
  /** The OAuth scopes the token needs, passed to `getToken`. */
  readonly scopes?: readonly string[];
  list(input: MailListInput): AsyncResult<MailPage>;
  send(input: MailSendInput): AsyncResult<MailSent>;
}

/** Checks the provider's `apiVersion` before the block uses it. */
export function mailProviderOf(provider: MailProvider): MailProvider {
  const version: unknown = provider.apiVersion;

  if (version !== 1) {
    throw new TypeError(
      `mail "${provider.name}" targets mail provider API ${String(version)}; this better-supabase supports 1. Upgrade better-supabase or use a release of the provider for API 1.`,
    );
  }

  return provider;
}

export interface HttpMailOptions {
  /** Defaults to the global `fetch`. */
  readonly fetch?: typeof fetch;
  /** The API origin, for a proxy or a test server. */
  readonly baseUrl?: string;
  /** How many days of mail the first sync of a mailbox reads. Default: 30. */
  readonly initialDays?: number;
}

type Json = Readonly<Record<string, unknown>>;

const record = (value: unknown): Json => (isRecord(value) ? value : {});

const list = (value: unknown): readonly unknown[] =>
  Array.isArray(value) ? value : [];

const text = (value: unknown): string | undefined =>
  typeof value === "string" && value.length > 0 ? value : undefined;

/** The `DbError` for a provider response that isn't a success. */
async function httpError(
  provider: string,
  response: Response,
): Promise<Result<never>> {
  const body = await response.text().catch(() => "");
  const message = `${provider} answered ${String(response.status)}${body.length > 0 ? `: ${body.slice(0, 300)}` : ""}`;
  const retry = Number(response.headers.get("retry-after"));
  const retryAfter = Number.isFinite(retry) && retry > 0 ? retry : undefined;

  if (response.status === 401 || response.status === 403) {
    return err(
      dbError("unauthorized", message, { hint: "MAIL_TOKEN_REFUSED" }),
    );
  }

  if (response.status === 404) {
    return err(dbError("not_found", message));
  }

  if (response.status === 429) {
    return err(
      dbError("rate_limited", message, {
        ...(retryAfter === undefined ? {} : { retryAfter }),
      }),
    );
  }

  return err(
    dbError("network", message, {
      ...(retryAfter === undefined ? {} : { retryAfter }),
    }),
  );
}

interface Http {
  readonly get: (path: string, signal?: AbortSignal) => AsyncResult<Json>;
  readonly post: (
    path: string,
    body: unknown,
    signal?: AbortSignal,
  ) => AsyncResult<Json>;
}

function http(
  provider: string,
  base: string,
  token: CredentialToken,
  options: HttpMailOptions,
  headers: Readonly<Record<string, string>> = {},
): Http {
  const run = options.fetch ?? fetch;

  const call = (
    path: string,
    init: RequestInit,
    signal: AbortSignal | undefined,
  ): AsyncResult<Json> =>
    AsyncResult.from(async () => {
      const response = await run(
        path.startsWith("https://") ? path : `${base}${path}`,
        {
          ...init,
          headers: {
            accept: "application/json",
            ...headers,
            ...token.headers,
            ...(init.body === undefined
              ? {}
              : { "content-type": "application/json" }),
          },
          ...(signal === undefined ? {} : { signal }),
        },
      );

      if (!response.ok) {
        return httpError(provider, response);
      }

      const body = await response.text();

      return ok(body.length === 0 ? {} : record(JSON.parse(body)));
    });

  return {
    get: (path, signal) => call(path, { method: "GET" }, signal),
    post: (path, body, signal) =>
      call(path, { method: "POST", body: JSON.stringify(body) }, signal),
  };
}

/** Splits `Name <a@b>, "Last, First" <c@d>` into addresses. */
export function parseAddresses(header: string | undefined): MailAddress[] {
  if (header === undefined) {
    return [];
  }

  const parts: string[] = [];
  let current = "";
  let quoted = false;
  let angled = false;

  for (const char of header) {
    if (char === '"') {
      quoted = !quoted;
    } else if (char === "<") {
      angled = true;
    } else if (char === ">") {
      angled = false;
    }

    if (char === "," && !quoted && !angled) {
      parts.push(current);
      current = "";
    } else {
      current += char;
    }
  }

  parts.push(current);

  return parts.flatMap((part) => {
    const trimmed = part.trim();
    const match = /^(.*)<([^<>]+)>$/.exec(trimmed);
    const address = (match?.[2] ?? trimmed).trim().toLowerCase();
    const name = match?.[1]?.trim().replaceAll(/^"|"$/g, "").trim();

    if (!address.includes("@")) {
      return [];
    }

    return [
      name === undefined || name.length === 0 ? { address } : { address, name },
    ];
  });
}

const encoder = new TextEncoder();
const decoder = new TextDecoder();

function base64(bytes: Uint8Array): string {
  let binary = "";

  for (const byte of bytes) {
    binary += String.fromCodePoint(byte);
  }

  return btoa(binary);
}

const base64Url = (value: string): string =>
  base64(encoder.encode(value))
    .replaceAll("+", "-")
    .replaceAll("/", "_")
    .replace(/[=]+$/, "");

function fromBase64Url(value: string): string {
  const binary = atob(value.replaceAll("-", "+").replaceAll("_", "/"));

  return decoder.decode(
    Uint8Array.from(binary, (char) => char.codePointAt(0) ?? 0),
  );
}

/** A header value without line breaks, so it can't add a header. */
const headerValue = (value: string): string =>
  value.replaceAll(/[\r\n]+/g, " ");

/** RFC 2047 for a header with non-ASCII text. */
function encodedWord(value: string): string {
  const clean = headerValue(value);

  return /^[\u0020-\u007E]*$/.test(clean)
    ? clean
    : `=?UTF-8?B?${base64(encoder.encode(clean))}?=`;
}

const formatAddress = (address: MailAddress): string =>
  address.name === undefined
    ? headerValue(address.address)
    : `${encodedWord(address.name)} <${headerValue(address.address)}>`;

const wrap = (value: string): string =>
  (value.match(/.{1,76}/g) ?? []).join("\r\n");

/**
 * The RFC 5322 message for a draft: a `multipart/alternative` with the text and
 * HTML parts, base64 encoded, and the reply headers when it answers one.
 */
export function buildMime(input: {
  readonly from: MailAddress;
  readonly draft: MailDraft;
  readonly messageId: string;
  readonly reply?: MailReplyTarget;
}): string {
  const { draft, from, reply } = input;
  const boundary = `bs-${input.messageId.replaceAll(/[^A-Za-z0-9]/g, "")}`;

  const join = (addresses: readonly MailAddress[] | undefined): string =>
    (addresses ?? []).map(formatAddress).join(", ");

  const headers = [
    `From: ${formatAddress(from)}`,
    `To: ${join(draft.to)}`,
    ...((draft.cc ?? []).length > 0 ? [`Cc: ${join(draft.cc)}`] : []),
    ...((draft.bcc ?? []).length > 0 ? [`Bcc: ${join(draft.bcc)}`] : []),
    `Subject: ${encodedWord(draft.subject)}`,
    `Message-ID: ${headerValue(input.messageId)}`,
    ...(reply?.messageId === undefined
      ? []
      : [
          `In-Reply-To: ${headerValue(reply.messageId)}`,
          `References: ${headerValue(reply.messageId)}`,
        ]),
    "MIME-Version: 1.0",
    `Content-Type: multipart/alternative; boundary="${boundary}"`,
  ];

  const part = (type: string, body: string): string =>
    [
      `--${boundary}`,
      `Content-Type: ${type}; charset="UTF-8"`,
      "Content-Transfer-Encoding: base64",
      "",
      wrap(base64(encoder.encode(body))),
    ].join("\r\n");

  return [
    ...headers,
    "",
    part("text/plain", draft.text ?? ""),
    ...(draft.html === undefined ? [] : [part("text/html", draft.html)]),
    `--${boundary}--`,
    "",
  ].join("\r\n");
}

/** A `Message-ID` on the sender's domain. */
export function newMessageId(from: MailAddress): string {
  const domain = from.address.split("@")[1] ?? "localhost";

  return `<${crypto.randomUUID()}@${domain}>`;
}

const GMAIL_SCOPES = [
  "https://www.googleapis.com/auth/gmail.readonly",
  "https://www.googleapis.com/auth/gmail.send",
] as const;

/** The first part of `type` in a Gmail message part tree, decoded. */
function gmailBody(value: unknown, type: string): string | undefined {
  const part = record(value);
  const data = text(record(part["body"])["data"]);

  if (part["mimeType"] === type && data !== undefined) {
    return fromBase64Url(data);
  }

  for (const child of list(part["parts"])) {
    const found = gmailBody(child, type);

    if (found !== undefined) {
      return found;
    }
  }

  return undefined;
}

/** A Gmail API message (`format=full`) as a provider message. */
export function gmailMessage(value: unknown): MailProviderMessage | undefined {
  const row = record(value);
  const id = text(row["id"]);
  const labels = list(row["labelIds"]);

  if (id === undefined || labels.includes("DRAFT")) {
    return undefined;
  }

  const payload = record(row["payload"]);

  const headers = new Map(
    list(payload["headers"]).map((header) => {
      const entry = record(header);

      return [
        String(entry["name"] ?? "").toLowerCase(),
        String(entry["value"] ?? ""),
      ] as const;
    }),
  );

  const internal = Number(row["internalDate"]);

  const sentAt = Number.isFinite(internal)
    ? temporal().Instant.fromEpochMilliseconds(internal)
    : temporal().Now.instant();

  const from = parseAddresses(headers.get("from"))[0];
  const subject = text(headers.get("subject"));
  const messageId = text(headers.get("message-id"));
  const snippet = text(row["snippet"]);
  const plain = gmailBody(payload, "text/plain");
  const html = gmailBody(payload, "text/html");

  return {
    externalId: id,
    threadId: text(row["threadId"]) ?? id,
    ...(messageId === undefined ? {} : { messageId }),
    ...(labels.includes("SENT") ? { direction: "outbound" as const } : {}),
    ...(from === undefined ? {} : { from }),
    to: parseAddresses(headers.get("to")),
    cc: parseAddresses(headers.get("cc")),
    ...(subject === undefined ? {} : { subject }),
    ...(snippet === undefined ? {} : { snippet }),
    ...(plain === undefined ? {} : { text: plain }),
    ...(html === undefined ? {} : { html }),
    sentAt,
  };
}

/**
 * Gmail through its REST API with the member's OAuth token: the first sync
 * reads the last `initialDays` of mail, later ones the history since the stored
 * `historyId`. No Google SDK is needed.
 */
export function gmailMail(options: HttpMailOptions = {}): MailProvider {
  const base =
    options.baseUrl ?? "https://gmail.googleapis.com/gmail/v1/users/me";

  const days = options.initialDays ?? 30;

  const fetchAll = (
    api: Http,
    ids: readonly string[],
    signal: AbortSignal | undefined,
  ): AsyncResult<MailProviderMessage[]> =>
    AsyncResult.from(async () => {
      const messages: MailProviderMessage[] = [];

      for (const id of ids) {
        const read = await api.get(
          `/messages/${encodeURIComponent(id)}?format=full`,
          signal,
        );

        if (!read.ok) {
          if (read.error.kind === "not_found") {
            continue;
          }

          return read;
        }

        const message = gmailMessage(read.data);

        if (message !== undefined) {
          messages.push(message);
        }
      }

      return ok(messages);
    });

  const initial = (api: Http, input: MailListInput): AsyncResult<MailPage> =>
    api.get("/profile", input.signal).andThen((profile) =>
      api
        .get(
          `/messages?maxResults=${String(input.limit)}&q=${encodeURIComponent(`newer_than:${String(days)}d`)}`,
          input.signal,
        )
        .andThen((page) =>
          fetchAll(
            api,
            list(page["messages"]).flatMap((entry) => {
              const id = text(record(entry)["id"]);

              return id === undefined ? [] : [id];
            }),
            input.signal,
          ),
        )
        .map((messages) => ({
          messages,
          cursor: String(profile["historyId"] ?? ""),
          more: false,
        })),
    );

  return {
    apiVersion: 1,
    name: "gmail",
    scopes: GMAIL_SCOPES,
    list: (input) => {
      const api = http("gmail", base, input.token, options);

      if (input.cursor === undefined || input.cursor.length === 0) {
        return initial(api, input);
      }

      return AsyncResult.from(async () => {
        const history = await api.get(
          `/history?historyTypes=messageAdded&maxResults=${String(input.limit)}&startHistoryId=${encodeURIComponent(input.cursor ?? "")}`,
          input.signal,
        );

        if (!history.ok) {
          // An expired historyId: start over from the recent mail.
          return history.error.kind === "not_found"
            ? initial(api, {
                token: input.token,
                limit: input.limit,
                ...(input.signal === undefined ? {} : { signal: input.signal }),
              })
            : history;
        }

        const records = list(history.data["history"]).map(record);

        const ids = [
          ...new Set(
            records.flatMap((entry) =>
              list(entry["messagesAdded"]).flatMap((added) => {
                const id = text(record(record(added)["message"])["id"]);

                return id === undefined ? [] : [id];
              }),
            ),
          ),
        ];

        const more = text(history.data["nextPageToken"]) !== undefined;
        const last = records.at(-1)?.["id"];

        const cursor = String(
          (more ? last : history.data["historyId"]) ?? input.cursor,
        );

        return fetchAll(api, ids, input.signal).map((messages) => ({
          messages,
          cursor,
          more,
        }));
      });
    },
    send: (input) => {
      const api = http("gmail", base, input.token, options);
      const messageId = newMessageId(input.from);

      const raw = base64Url(
        buildMime({
          from: input.from,
          draft: input.draft,
          messageId,
          ...(input.reply === undefined ? {} : { reply: input.reply }),
        }),
      );

      return api
        .post(
          "/messages/send",
          {
            raw,
            ...(input.reply === undefined
              ? {}
              : { threadId: input.reply.threadId }),
          },
          input.signal,
        )
        .map((sent) => {
          const id = String(sent["id"] ?? "");

          return {
            externalId: id,
            threadId: String(sent["threadId"] ?? id),
            messageId,
          };
        });
    },
  };
}

const OUTLOOK_SCOPES = [
  "https://graph.microsoft.com/Mail.Read",
  "https://graph.microsoft.com/Mail.Send",
] as const;

const OUTLOOK_FIELDS =
  "id,conversationId,internetMessageId,subject,bodyPreview,body,from,toRecipients,ccRecipients,sentDateTime,receivedDateTime,isDraft";

const FOLDERS = ["inbox", "sentitems"] as const;

const outlookAddress = (value: unknown): MailAddress | undefined => {
  const email = record(record(value)["emailAddress"]);
  const address = text(email["address"])?.toLowerCase();
  const name = text(email["name"]);

  if (address === undefined) {
    return undefined;
  }

  return name === undefined ? { address } : { address, name };
};

const outlookAddresses = (value: unknown): MailAddress[] =>
  list(value).flatMap((entry) => {
    const address = outlookAddress(entry);

    return address === undefined ? [] : [address];
  });

/** A Microsoft Graph message as a provider message. */
export function outlookMessage(
  value: unknown,
  folder: string,
): MailProviderMessage | undefined {
  const row = record(value);
  const id = text(row["id"]);

  if (id === undefined || row["isDraft"] === true || "@removed" in row) {
    return undefined;
  }

  const body = record(row["body"]);
  const content = text(body["content"]);
  const html = body["contentType"] === "html" ? content : undefined;
  const plain = body["contentType"] === "html" ? undefined : content;
  const at = text(row["sentDateTime"]) ?? text(row["receivedDateTime"]);
  const from = outlookAddress(row["from"]);
  const messageId = text(row["internetMessageId"]);
  const subject = text(row["subject"]);
  const snippet = text(row["bodyPreview"]);

  return {
    externalId: id,
    threadId: text(row["conversationId"]) ?? id,
    ...(messageId === undefined ? {} : { messageId }),
    direction: folder === "sentitems" ? "outbound" : "inbound",
    ...(from === undefined ? {} : { from }),
    to: outlookAddresses(row["toRecipients"]),
    cc: outlookAddresses(row["ccRecipients"]),
    ...(subject === undefined ? {} : { subject }),
    ...(snippet === undefined ? {} : { snippet }),
    ...(plain === undefined ? {} : { text: plain }),
    ...(html === undefined ? {} : { html }),
    sentAt:
      at === undefined ? temporal().Now.instant() : temporal().Instant.from(at),
  };
}

type OutlookCursor = Partial<Record<(typeof FOLDERS)[number], string>>;

function outlookCursor(value: string | undefined): OutlookCursor {
  if (value === undefined || value.length === 0) {
    return {};
  }

  try {
    const parsed = record(JSON.parse(value));

    return Object.fromEntries(
      FOLDERS.flatMap((folder) => {
        const link = text(parsed[folder]);

        return link?.startsWith("https://") === true ? [[folder, link]] : [];
      }),
    );
  } catch {
    return {};
  }
}

/**
 * Outlook and Microsoft 365 through Microsoft Graph with the member's OAuth
 * token: the inbox and sent items through delta queries, whose links are the
 * cursor. No Microsoft SDK is needed.
 */
export function outlookMail(options: HttpMailOptions = {}): MailProvider {
  const base = options.baseUrl ?? "https://graph.microsoft.com/v1.0";

  const recipients = (addresses: readonly MailAddress[] | undefined) =>
    (addresses ?? []).map((address) => ({
      emailAddress: {
        address: address.address,
        ...(address.name === undefined ? {} : { name: address.name }),
      },
    }));

  return {
    apiVersion: 1,
    name: "outlook",
    scopes: OUTLOOK_SCOPES,
    list: (input) =>
      AsyncResult.from(async () => {
        const api = http("outlook", base, input.token, options, {
          prefer: `odata.maxpagesize=${String(input.limit)}`,
        });

        const cursor = outlookCursor(input.cursor);
        const next: OutlookCursor = {};
        const messages: MailProviderMessage[] = [];
        let more = false;

        for (const folder of FOLDERS) {
          const page = await api.get(
            cursor[folder] ??
              `/me/mailFolders/${folder}/messages/delta?$select=${OUTLOOK_FIELDS}`,
            input.signal,
          );

          if (!page.ok) {
            return page;
          }

          for (const entry of list(page.data["value"])) {
            const message = outlookMessage(entry, folder);

            if (message !== undefined) {
              messages.push(message);
            }
          }

          const following = text(page.data["@odata.nextLink"]);
          const delta = text(page.data["@odata.deltaLink"]);
          more ||= following !== undefined;
          const link = following ?? delta ?? cursor[folder];

          if (link !== undefined) {
            next[folder] = link;
          }
        }

        return ok({ messages, cursor: JSON.stringify(next), more });
      }),
    send: (input) => {
      const api = http("outlook", base, input.token, options);

      const message = {
        subject: input.draft.subject,
        body:
          input.draft.html === undefined
            ? { contentType: "text", content: input.draft.text ?? "" }
            : { contentType: "html", content: input.draft.html },
        toRecipients: recipients(input.draft.to),
        ccRecipients: recipients(input.draft.cc),
        bccRecipients: recipients(input.draft.bcc),
      };

      const draft =
        input.reply === undefined
          ? api.post("/me/messages", message, input.signal)
          : api.post(
              `/me/messages/${encodeURIComponent(input.reply.externalId)}/createReply`,
              { message },
              input.signal,
            );

      return draft.andThen((created) => {
        const id = String(created["id"] ?? "");
        const messageId = text(created["internetMessageId"]);

        return api
          .post(`/me/messages/${encodeURIComponent(id)}/send`, {}, input.signal)
          .map(() => ({
            externalId: id,
            threadId: String(created["conversationId"] ?? id),
            ...(messageId === undefined ? {} : { messageId }),
          }));
      });
    },
  };
}
