import type { ExpoNotificationsLike } from "../../client/native/push-token.ts";
import type {
  BlockFields,
  FieldsOf,
  RowFields,
} from "../../core/block-fields.ts";
import type { BlockHooks } from "../../core/block-hooks.ts";
import type { BlockTransport } from "../../core/block-transport.ts";
import type { ErrorMapper } from "../../core/errors.ts";
import type { EventHub } from "../../core/events.ts";
import type { Logger } from "../../core/logger.ts";
import type { RequestContext } from "../../core/plugin.ts";
import type { AsyncResult } from "../../core/result.ts";
import type { StandardSchemaV1 } from "../../core/standard.ts";
import type { RecordedDeliveryEvent } from "../notifications/api-types.ts";
import type {
  NotificationChannel,
  NotificationMessage,
  NotificationSendResult,
} from "../notifications/channel.ts";
import type { NotificationsEvents } from "../notifications/events.ts";
import type { BlockTemporalOptions } from "../shared.ts";

import { expoPushToken } from "../../client/native/push-token.ts";
import { blockEmitter } from "../../core/block-events.ts";
import {
  blockFields,
  readAllFields,
  rowFields,
  writeFields,
} from "../../core/block-fields.ts";
import { withBlockHooks } from "../../core/block-hooks.ts";
import { temporal } from "../../core/temporal-required.ts";
import {
  emitDeliveryEvent,
  recordedDeliveryEventOf,
} from "../notifications/delivery-events.ts";
import {
  applyTemporal,
  blockCall,
  nullableText,
  recordOrEmpty,
  recordsOf,
  run,
  textOf,
} from "../shared.ts";

export type { ExpoNotificationsLike } from "../../client/native/push-token.ts";

export type PushPlatform = "ios" | "android" | "web";

export type PushProvider = "expo" | "fcm" | "apns" | "webpush";

const PLATFORMS: ReadonlySet<string> = new Set(["ios", "android", "web"]);

function isPlatform(value: string): value is PushPlatform {
  return PLATFORMS.has(value);
}

/**
 * A device to register. `F` types the extra columns the `fields` schema
 * describes.
 */
export interface PushDeviceInput<F extends object = Record<never, never>> {
  readonly token: string;
  readonly platform: PushPlatform;
  /** Defaults to `expo`. */
  readonly provider?: PushProvider;
  readonly deviceName?: string;
  readonly appVersion?: string;
  /**
   * Values for the app's extra columns (`options.extraColumns`); left out keeps
   * the stored ones.
   */
  readonly fields?: Partial<F> & Readonly<Record<string, unknown>>;
}

/** One device a user gets pushes on. */
export interface PushTarget<F extends object = Record<never, never>> {
  readonly userId: string;
  readonly token: string;
  readonly platform: PushPlatform;
  readonly provider: PushProvider;
  /** The app's extra columns (`options.extraColumns`), by column name. */
  readonly fields: RowFields<F>;
}

export interface PushDevicesOptions<
  S extends StandardSchemaV1 | undefined = undefined,
> extends BlockTemporalOptions {
  /**
   * `sqlTransport(postgres.asUser(claims))`, `rpcTransport(supabase)`, or over
   * `postgres.admin` for the sender.
   */
  readonly transport: BlockTransport;
  /**
   * The module schema, or its API schema: `defineBlocks` passes it from
   * `blocks.generated.ts`. Default `better_supabase`.
   */
  readonly schema?: string;
  readonly mappers?: readonly ErrorMapper[];
  /**
   * A Standard Schema for the extra columns of the devices table
   * (`blocks.push.options.extraColumns`): writes are validated, reads parsed.
   */
  readonly fields?: S;
  /** `withBlockHooks` hooks around the client's methods. */
  readonly hooks?: NoInfer<BlockHooks<PushDevices<FieldsOf<S>>>>;
  /** Receives the errors `after` hooks throw. Default: `console`. */
  readonly logger?: Logger;
  /**
   * `betterSupabase.events`, for the `notification.delivered` and
   * `notification.bounced` events `checkReceipts` records.
   */
  readonly events?: EventHub;
  readonly actorId?: string;
  readonly context?: RequestContext;
}

/** The `push` SQL module as typed calls. */
export interface PushDevices<F extends object = Record<never, never>> {
  /**
   * Registers the caller's device, or refreshes it; resolves with the device
   * id.
   */
  readonly register: (device: PushDeviceInput<F>) => AsyncResult<string>;
  /** Removes the caller's device; `false` when the caller had none with `token`. */
  readonly unregister: (token: string) => AsyncResult<boolean>;
  /** Service role: every device of `userIds`, newest first per user. */
  readonly tokensFor: (
    userIds: readonly string[],
  ) => AsyncResult<readonly PushTarget<F>[]>;
  /** Service role: deletes the devices with `tokens`; resolves with how many. */
  readonly prune: (tokens: readonly string[]) => AsyncResult<number>;
  /**
   * Service role: stores Expo's tickets for one notification delivery. Needs
   * push module version 2 with the notifications block.
   */
  readonly recordTickets: (input: {
    deliveryId: string;
    tickets: readonly ExpoPushTicket[];
  }) => AsyncResult<number>;
  /** Service role: the tickets already stored for a delivery. */
  readonly ticketsFor: (
    deliveryId: string,
  ) => AsyncResult<readonly ExpoPushTicket[]>;
  /**
   * Service role: reads the receipts of tickets older than `olderThan` (default
   * 15 minutes), stores them, records `notification.delivered` or
   * `notification.bounced` on their deliveries and prunes the devices Expo no
   * longer reaches. Run it from a cron.
   */
  readonly checkReceipts: (
    options?: CheckReceiptsOptions,
  ) => AsyncResult<ExpoReceiptResult>;
}

export interface CheckReceiptsOptions {
  /** Defaults to `expoPush({ devices })` over this client. */
  readonly push?: ExpoPush;
  /** Tickets per call, at most 1000. Default 1000. */
  readonly limit?: number;
  /** How long Expo needs before a receipt is ready. Default 15 minutes. */
  readonly olderThan?: Temporal.Duration;
}

const PROVIDERS: ReadonlySet<string> = new Set([
  "expo",
  "fcm",
  "apns",
  "webpush",
]);

function isProvider(value: string): value is PushProvider {
  return PROVIDERS.has(value);
}

function targetsOf(value: unknown): readonly PushTarget[] {
  return recordsOf(value, "push_tokens_for").flatMap((row) => {
    const platform = textOf(row["platform"]);
    const provider = textOf(row["provider"]);

    return isPlatform(platform) && isProvider(provider)
      ? [
          {
            userId: textOf(row["userId"]),
            token: textOf(row["token"]),
            platform,
            provider,
            fields: rowFields(row["fields"]),
          },
        ]
      : [];
  });
}

function ticketsOf(value: unknown): readonly ExpoPushTicket[] {
  return recordsOf(value, "push_tickets_for").map((row) => {
    const id = row["id"];
    const error = row["error"];

    return {
      token: textOf(row["token"]),
      ...(typeof id === "string" ? { id } : {}),
      ...(typeof error === "string" ? { error } : {}),
    };
  });
}

interface UncheckedTicket {
  readonly id: string;
  readonly token: string;
}

function uncheckedOf(value: unknown): readonly UncheckedTicket[] {
  return recordsOf(value, "unchecked_push_tickets").map((row) => ({
    id: textOf(row["id"]),
    token: textOf(row["token"]),
  }));
}

const countOf = (value: unknown): number =>
  typeof value === "number" ? value : Number(value ?? 0);

interface CompletedReceipts {
  readonly events: readonly {
    readonly recorded: RecordedDeliveryEvent;
    readonly providerEventId: string | null;
  }[];
}

function completedOf(value: unknown): CompletedReceipts {
  const events = recordOrEmpty(value)["events"];

  return {
    events: (Array.isArray(events) ? events : []).flatMap((event) => {
      const recorded = recordedDeliveryEventOf(event);

      return recorded === null
        ? []
        : [
            {
              recorded,
              providerEventId: nullableText(
                recordOrEmpty(event)["provider_event_id"],
              ),
            },
          ];
    }),
  };
}

export function createPush<S extends StandardSchemaV1 | undefined = undefined>(
  options: PushDevicesOptions<S>,
): PushDevices<FieldsOf<S>> {
  type F = FieldsOf<S>;

  applyTemporal(options);
  const call = blockCall(options.transport, options.schema, options.mappers);
  const emit = blockEmitter<NotificationsEvents>(options);

  const fields: BlockFields<F> = blockFields(
    options.fields,
    "push device fields",
  );

  const client: PushDevices<F> = {
    register: (device) =>
      writeFields(fields, device.fields, (checked) =>
        call(
          "register_push_device",
          {
            token: device.token,
            platform: device.platform,
            provider: device.provider ?? "expo",
            device_name: device.deviceName,
            app_version: device.appVersion,
            fields: checked,
          },
          textOf,
        ),
      ),
    unregister: (token) =>
      call("unregister_push_device", { token }, (value) => value === true),
    tokensFor: (userIds) =>
      call("push_tokens_for", { users: [...userIds] }, targetsOf).andThen(
        (targets) => readAllFields(fields, targets),
      ),
    prune: (tokens) =>
      call("prune_push_tokens", { tokens: [...tokens] }, countOf),
    recordTickets: ({ deliveryId, tickets }) =>
      call(
        "record_push_tickets",
        {
          delivery: deliveryId,
          tickets: tickets.map((ticket) => ({
            token: ticket.token,
            id: ticket.id ?? null,
            error: ticket.error ?? null,
          })),
        },
        countOf,
      ),
    ticketsFor: (deliveryId) =>
      call("push_tickets_for", { delivery: deliveryId }, ticketsOf),
    checkReceipts: (checks = {}) =>
      run(async (): Promise<ExpoReceiptResult> => {
        const push = checks.push ?? expoPush({ devices: client });

        const tickets = await call(
          "unchecked_push_tickets",
          {
            max_items: checks.limit ?? 1000,
            older_than: (
              checks.olderThan ?? temporal().Duration.from({ minutes: 15 })
            ).toString(),
          },
          uncheckedOf,
        ).orThrow();

        const result = await push.checkReceipts(tickets);

        if (result.receipts.length > 0) {
          const completed = await call(
            "complete_push_receipts",
            {
              receipts: result.receipts.map((receipt) => ({
                id: receipt.id,
                status: receipt.status,
                error: receipt.error ?? null,
                message: receipt.message ?? null,
              })),
            },
            completedOf,
          ).orThrow();

          for (const { recorded, providerEventId } of completed.events) {
            emitDeliveryEvent(emit, recorded, "expo", providerEventId);
          }
        }

        return result;
      }),
  };

  return withBlockHooks(client, options.hooks, {
    block: "push",
    ...(options.logger ? { logger: options.logger } : {}),
  });
}

export interface RegisterDeviceOptions {
  readonly notifications: ExpoNotificationsLike;
  readonly devices: PushDevices;
  /** `Platform.OS` from `react-native`. */
  readonly platform: string;
  /** `Constants.easConfig?.projectId`; Expo needs it outside Expo Go. */
  readonly projectId?: string | undefined;
  readonly deviceName?: string | undefined;
  readonly appVersion?: string | undefined;
  /** Asks for permission when it isn't granted yet. Defaults to true. */
  readonly request?: boolean;
}

export interface RegisteredDevice {
  readonly deviceId: string;
  readonly token: string;
}

/**
 * Gets the Expo push token, asking for permission first, and registers the
 * device for the signed-in user. Resolves with `null` when the user denies
 * permission or the platform has no push.
 *
 * ```ts
 * const device = await registerDevice({
 *   notifications: Notifications,
 *   devices: createPush({ transport: rpcTransport(supabase) }),
 *   platform: Platform.OS,
 *   projectId: Constants.easConfig?.projectId,
 * }).orThrow();
 * ```
 */
export function registerDevice(
  options: RegisterDeviceOptions,
): AsyncResult<RegisteredDevice | null> {
  return run(async (): Promise<RegisteredDevice | null> => {
    const { notifications, platform } = options;

    if (!isPlatform(platform)) {
      return null;
    }

    const token = await expoPushToken(notifications, {
      projectId: options.projectId,
    }).token({ request: options.request ?? true });

    if (token === null) {
      return null;
    }

    const deviceId = await options.devices
      .register({
        token,
        platform,
        provider: "expo",
        ...(options.deviceName === undefined
          ? {}
          : { deviceName: options.deviceName }),
        ...(options.appVersion === undefined
          ? {}
          : { appVersion: options.appVersion }),
      })
      .orThrow();

    return { deviceId, token };
  });
}

/**
 * Wraps `signOut` so it first removes this device's token, while the session
 * can still call `unregister_push_device`. A failed unregister doesn't stop the
 * sign-out.
 *
 * ```ts
 * const signOut = unregisterOnSignOut({
 *   signOut: () => supabase.auth.signOut(),
 *   devices,
 *   token: () => device?.token,
 * });
 * ```
 */
export function unregisterOnSignOut<R>(options: {
  readonly signOut: () => Promise<R>;
  readonly devices: PushDevices;
  readonly token: () => string | null | undefined;
}): () => Promise<R> {
  return async () => {
    const token = options.token();

    if (token) {
      await options.devices.unregister(token);
    }

    return options.signOut();
  };
}

/** One message for the Expo Push API; `to` is set per device. */
export interface ExpoPushMessage {
  readonly title?: string;
  readonly subtitle?: string;
  readonly body?: string;
  readonly data?: Readonly<Record<string, unknown>>;
  readonly sound?: "default" | null;
  readonly badge?: number;
  readonly channelId?: string;
  readonly categoryId?: string;
  readonly priority?: "default" | "normal" | "high";
  /** Seconds the push service keeps trying to deliver. */
  readonly ttl?: number;
  readonly mutableContent?: boolean;
}

/** What Expo answered for one message: an id for the receipt, or an error. */
export interface ExpoPushTicket {
  readonly token: string;
  readonly id?: string;
  /** Expo's error code, e.g. `DeviceNotRegistered` or `MessageRateExceeded`. */
  readonly error?: string;
  readonly message?: string;
}

/** What Expo's receipt said about one ticket. */
export interface ExpoPushReceipt {
  readonly id: string;
  readonly token: string;
  readonly status: "ok" | "error";
  readonly error?: string;
  readonly message?: string;
}

export interface ExpoReceiptResult {
  readonly delivered: number;
  readonly failed: readonly ExpoPushTicket[];
  /** Tokens deleted because Expo reported `DeviceNotRegistered`. */
  readonly pruned: number;
  /** Every receipt Expo had ready; tickets without one stay unchecked. */
  readonly receipts: readonly ExpoPushReceipt[];
}

export interface ExpoPushOptions {
  /** The Expo access token, when the project turns on push security. */
  readonly accessToken?: string;
  /** Prunes tokens Expo reports as `DeviceNotRegistered`. */
  readonly devices?: PushDevices;
  readonly fetch?: typeof fetch;
  /** Defaults to `https://exp.host/--/api/v2/push`. */
  readonly endpoint?: string;
  /**
   * Retries of one request after a 429, a 5xx or a network error, waiting for
   * `Retry-After` (at most 30 seconds) or 1, 2, 4 seconds. Default 3.
   */
  readonly maxRetries?: number;
  /** Waits between retries. Defaults to `setTimeout`. */
  readonly sleep?: (milliseconds: number) => Promise<void>;
}

export interface ExpoSendOptions {
  /**
   * Sent as the `idempotency-key` header per request, suffixed with the chunk
   * number, e.g. the notification delivery id.
   */
  readonly idempotencyKey?: string;
  /**
   * Tickets an earlier attempt stored: tokens with a ticket id or
   * `DeviceNotRegistered` are not sent again, and a chunk whose tokens all have
   * one is skipped.
   */
  readonly sent?: readonly ExpoPushTicket[];
}

/** The error of every ticket in a chunk whose request failed after its retries. */
export const EXPO_REQUEST_FAILED = "RequestFailed";

export interface ExpoPush {
  /**
   * Sends `message` to each token, 100 per request; tickets come back in token
   * order. A request that still fails after its retries gives its tokens a
   * `RequestFailed` ticket instead of throwing, so chunks already sent keep
   * their tickets.
   */
  readonly send: (
    tokens: readonly string[],
    message: ExpoPushMessage,
    options?: ExpoSendOptions,
  ) => Promise<readonly ExpoPushTicket[]>;
  /**
   * Reads the receipts for tickets that have an id, about 15 minutes after
   * sending, and prunes the devices Expo no longer reaches.
   */
  readonly checkReceipts: (
    tickets: readonly ExpoPushTicket[],
  ) => Promise<ExpoReceiptResult>;
}

const SEND_CHUNK = 100;
const RECEIPT_CHUNK = 1000;
const NOT_REGISTERED = "DeviceNotRegistered";

function chunks<T>(items: readonly T[], size: number): T[][] {
  const out: T[][] = [];

  for (let at = 0; at < items.length; at += size) {
    out.push(items.slice(at, at + size));
  }

  return out;
}

const MAX_WAIT = 30_000;

const wait = (milliseconds: number): Promise<void> =>
  new Promise((resolve) => {
    setTimeout(resolve, milliseconds);
  });

const retryable = (status: number): boolean => status === 429 || status >= 500;

/** `Retry-After` in seconds or as a date, else 1, 2, 4 seconds; at most 30. */
function backoff(attempt: number, retryAfter: string | null): number {
  if (retryAfter !== null) {
    const seconds = Number(retryAfter);

    const milliseconds = Number.isFinite(seconds)
      ? seconds * 1000
      : Date.parse(retryAfter) - Date.now();

    if (Number.isFinite(milliseconds) && milliseconds >= 0) {
      return Math.min(milliseconds, MAX_WAIT);
    }
  }

  return Math.min(1000 * 2 ** attempt, MAX_WAIT);
}

function errorCode(entry: Readonly<Record<string, unknown>>): string {
  const details = recordOrEmpty(entry["details"]);
  const code = details["error"];

  return typeof code === "string" ? code : "Unknown";
}

/**
 * A sender for the Expo Push API that needs only `fetch`. Tokens Expo reports
 * as `DeviceNotRegistered`, in a ticket or a receipt, are pruned from
 * `push_devices` when `devices` is set.
 */
export function expoPush(options: ExpoPushOptions = {}): ExpoPush {
  const endpoint = options.endpoint ?? "https://exp.host/--/api/v2/push";
  const doFetch = options.fetch ?? globalThis.fetch;
  const maxRetries = Math.max(0, options.maxRetries ?? 3);
  const sleep = options.sleep ?? wait;

  const headers: Record<string, string> = {
    accept: "application/json",
    "content-type": "application/json",
    ...(options.accessToken
      ? { authorization: `Bearer ${options.accessToken}` }
      : {}),
  };

  const post = async (
    path: string,
    body: unknown,
    idempotencyKey?: string,
  ): Promise<unknown> => {
    const init: RequestInit = {
      method: "POST",
      headers: {
        ...headers,
        ...(idempotencyKey === undefined
          ? {}
          : { "idempotency-key": idempotencyKey }),
      },
      body: JSON.stringify(body),
    };

    for (let attempt = 0; ; attempt += 1) {
      let response: Response;

      try {
        response = await doFetch(`${endpoint}/${path}`, init);
      } catch (error) {
        if (attempt >= maxRetries) {
          throw error;
        }

        await sleep(backoff(attempt, null));
        continue;
      }

      const text = await response.text();

      if (response.ok) {
        const parsed: unknown = text === "" ? {} : JSON.parse(text);

        return recordOrEmpty(parsed)["data"];
      }

      if (attempt < maxRetries && retryable(response.status)) {
        await sleep(backoff(attempt, response.headers.get("retry-after")));
        continue;
      }

      throw new Error(
        `Expo Push API ${path} answered ${String(response.status)}: ${text.slice(0, 500)}`,
      );
    }
  };

  const prune = async (tokens: readonly string[]): Promise<number> => {
    if (!options.devices || tokens.length === 0) {
      return 0;
    }

    let pruned = 0;

    for (const chunk of chunks([...new Set(tokens)], RECEIPT_CHUNK)) {
      pruned += await options.devices.prune(chunk).orThrow();
    }

    return pruned;
  };

  const sendChunk = async (
    tokens: readonly string[],
    message: ExpoPushMessage,
    idempotencyKey: string | undefined,
  ): Promise<readonly ExpoPushTicket[]> => {
    let data: unknown;

    try {
      data = await post(
        "send",
        tokens.map((to) => ({ ...message, to })),
        idempotencyKey,
      );
    } catch (error) {
      const reason = error instanceof Error ? error.message : String(error);

      return tokens.map((token) => ({
        token,
        error: EXPO_REQUEST_FAILED,
        message: reason.slice(0, 500),
      }));
    }

    const list: readonly unknown[] = Array.isArray(data) ? data : [];

    return tokens.map((token, at) => {
      const entry = recordOrEmpty(list[at]);

      const text =
        typeof entry["message"] === "string" ? entry["message"] : undefined;

      return entry["status"] === "ok" && typeof entry["id"] === "string"
        ? { token, id: entry["id"] }
        : {
            token,
            error: errorCode(entry),
            ...(text === undefined ? {} : { message: text }),
          };
    });
  };

  return {
    send: async (tokens, message, sendOptions = {}) => {
      const done = new Map(
        (sendOptions.sent ?? [])
          .filter(
            (ticket) =>
              ticket.id !== undefined || ticket.error === NOT_REGISTERED,
          )
          .map((ticket) => [ticket.token, ticket] as const),
      );

      const tickets: ExpoPushTicket[] = [];
      const fresh: ExpoPushTicket[] = [];

      for (const [index, chunk] of chunks(tokens, SEND_CHUNK).entries()) {
        const pending = chunk.filter((token) => !done.has(token));

        const sent =
          pending.length === 0
            ? []
            : await sendChunk(
                pending,
                message,
                sendOptions.idempotencyKey === undefined
                  ? undefined
                  : `${sendOptions.idempotencyKey}:${String(index)}`,
              );

        fresh.push(...sent);
        const byToken = new Map(sent.map((ticket) => [ticket.token, ticket]));

        for (const token of chunk) {
          const ticket = done.get(token) ?? byToken.get(token);

          if (ticket) {
            tickets.push(ticket);
          }
        }
      }

      await prune(
        fresh
          .filter((ticket) => ticket.error === NOT_REGISTERED)
          .map((ticket) => ticket.token),
      );

      return tickets;
    },
    checkReceipts: async (tickets) => {
      const byId = new Map<string, string>();

      for (const ticket of tickets) {
        if (ticket.id !== undefined) {
          byId.set(ticket.id, ticket.token);
        }
      }

      let delivered = 0;
      const failed: ExpoPushTicket[] = [];
      const receipts: ExpoPushReceipt[] = [];

      for (const ids of chunks([...byId.keys()], RECEIPT_CHUNK)) {
        const answered = recordOrEmpty(await post("getReceipts", { ids }));

        for (const id of ids) {
          const receipt = answered[id];

          if (receipt === undefined) {
            continue;
          }

          const entry = recordOrEmpty(receipt);
          const token = byId.get(id) ?? "";

          if (entry["status"] === "ok") {
            delivered += 1;
            receipts.push({ id, token, status: "ok" });
            continue;
          }

          const text =
            typeof entry["message"] === "string" ? entry["message"] : undefined;

          const ticket: ExpoPushTicket = {
            token,
            id,
            error: errorCode(entry),
            ...(text === undefined ? {} : { message: text }),
          };

          failed.push(ticket);
          receipts.push({
            id,
            token,
            status: "error",
            error: errorCode(entry),
            ...(text === undefined ? {} : { message: text }),
          });
        }
      }

      const pruned = await prune(
        failed
          .filter((ticket) => ticket.error === NOT_REGISTERED)
          .map((ticket) => ticket.token),
      );

      return { delivered, failed, pruned, receipts };
    },
  };
}

export interface ExpoPushChannelOptions {
  /** Over the service role, so `tokensFor` can read every user's devices. */
  readonly devices: PushDevices;
  readonly push: ExpoPush;
  /** The delivery channel name. Defaults to `push`. */
  readonly name?: string;
  /** Overrides the message built from the notification and its rendered text. */
  readonly message?: (message: NotificationMessage) => ExpoPushMessage;
  /**
   * Stores each delivery's tickets in `push_tickets`, so a retried delivery
   * skips the devices Expo already accepted and `devices.checkReceipts()` can
   * confirm them. Needs push module version 2 with the notifications block.
   * Default `true`.
   */
  readonly storeTickets?: boolean;
  /** Receives the tickets, to check their receipts yourself. */
  readonly onTickets?: (
    tickets: readonly ExpoPushTicket[],
    message: NotificationMessage,
  ) => void | Promise<void>;
}

function defaultMessage(message: NotificationMessage): ExpoPushMessage {
  const { notification, text } = message;

  return {
    title: text?.title ?? notification.summary ?? notification.type,
    ...(text?.body === undefined ? {} : { body: text.body }),
    sound: "default",
    data: {
      notificationId: notification.id,
      type: notification.type,
      ...(notification.actionPath === null
        ? {}
        : { actionPath: notification.actionPath }),
    },
  };
}

/**
 * A notifications channel that pushes each delivery to the recipient's Expo
 * devices. A recipient without devices is `skipped`. It throws, so the delivery
 * is retried, when a request to Expo failed after its own retries or when every
 * ticket failed for a reason other than an unregistered device. The retry sends
 * only to the devices without a stored ticket, with the delivery id as the
 * idempotency key.
 *
 * ```ts
 * createNotifications({
 *   transport,
 *   types,
 *   channels: [expoPushChannel({ devices, push: expoPush({ devices }) })],
 * });
 * ```
 */
export function expoPushChannel(
  options: ExpoPushChannelOptions,
): NotificationChannel {
  const build = options.message ?? defaultMessage;

  return {
    apiVersion: 1,
    name: options.name ?? "push",
    async send(message): Promise<NotificationSendResult> {
      const targets = await options.devices
        .tokensFor([message.userId])
        .orThrow();

      const tokens = targets
        .filter((target) => target.provider === "expo")
        .map((target) => target.token);

      if (tokens.length === 0) {
        return { status: "skipped", provider: "expo" };
      }

      const store = options.storeTickets ?? true;

      const stored = store
        ? await options.devices.ticketsFor(message.deliveryId).orThrow()
        : [];

      const tickets = await options.push.send(tokens, build(message), {
        idempotencyKey: message.deliveryId,
        sent: stored,
      });

      if (store) {
        await options.devices
          .recordTickets({ deliveryId: message.deliveryId, tickets })
          .orThrow();
      }

      await options.onTickets?.(tickets, message);

      const failed = tickets.find(
        (ticket) => ticket.error === EXPO_REQUEST_FAILED,
      );

      if (failed) {
        throw new Error(
          `Expo push request failed: ${failed.message ?? EXPO_REQUEST_FAILED}`,
        );
      }

      const sent = tickets.find((ticket) => ticket.id !== undefined);

      if (sent?.id !== undefined) {
        return { provider: "expo", providerMessageId: sent.id };
      }

      const retryable = tickets.find(
        (ticket) => ticket.error !== NOT_REGISTERED,
      );

      if (retryable) {
        throw new Error(
          `Expo rejected the push: ${retryable.error ?? "Unknown"}${retryable.message ? ` (${retryable.message})` : ""}`,
        );
      }

      return { status: "skipped", provider: "expo" };
    },
  };
}
