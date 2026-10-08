import type { BlockTransport } from "../../core/block-transport.ts";
import type { ErrorMapper } from "../../core/errors.ts";
import type { AsyncResult } from "../../core/result.ts";
import type {
  NotificationChannel,
  NotificationMessage,
  NotificationSendResult,
} from "../notifications/channel.ts";

import {
  applyTemporal,
  type BlockTemporalOptions,
  blockCall,
  recordsOf,
  run,
  textOf,
} from "../shared.ts";

export type PushPlatform = "ios" | "android" | "web";
export type PushProvider = "expo" | "fcm" | "apns" | "webpush";

const PLATFORMS: ReadonlySet<string> = new Set(["ios", "android", "web"]);

function isPlatform(value: string): value is PushPlatform {
  return PLATFORMS.has(value);
}

export interface PushDeviceInput {
  readonly token: string;
  readonly platform: PushPlatform;
  /** Defaults to `expo`. */
  readonly provider?: PushProvider;
  readonly deviceName?: string;
  readonly appVersion?: string;
}

/** One device a user gets pushes on. */
export interface PushTarget {
  readonly userId: string;
  readonly token: string;
  readonly platform: PushPlatform;
  readonly provider: PushProvider;
}

export interface PushDevicesOptions extends BlockTemporalOptions {
  /** `sqlTransport(postgres.asUser(claims))`, `rpcTransport(supabase)`, or over `postgres.admin` for the sender. */
  readonly transport: BlockTransport;
  /** `sql.modules.push.schema`. Defaults to `better_supabase`. */
  readonly schema?: string;
  readonly mappers?: readonly ErrorMapper[];
}

/** The `push` SQL module as typed calls. */
export interface PushDevices {
  /** Registers the caller's device, or refreshes it; resolves with the device id. */
  readonly register: (device: PushDeviceInput) => AsyncResult<string>;
  /** Removes the caller's device; `false` when the caller had none with `token`. */
  readonly unregister: (token: string) => AsyncResult<boolean>;
  /** Service role: every device of `userIds`, newest first per user. */
  readonly tokensFor: (
    userIds: readonly string[],
  ) => AsyncResult<readonly PushTarget[]>;
  /** Service role: deletes the devices with `tokens`; resolves with how many. */
  readonly prune: (tokens: readonly string[]) => AsyncResult<number>;
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
          },
        ]
      : [];
  });
}

export function createPushDevices(options: PushDevicesOptions): PushDevices {
  applyTemporal(options);
  const call = blockCall(options.transport, options.schema, options.mappers);
  return {
    register: (device) =>
      call(
        "register_push_device",
        {
          token: device.token,
          platform: device.platform,
          provider: device.provider ?? "expo",
          device_name: device.deviceName,
          app_version: device.appVersion,
        },
        textOf,
      ),
    unregister: (token) =>
      call("unregister_push_device", { token }, (value) => value === true),
    tokensFor: (userIds) =>
      call("push_tokens_for", { users: [...userIds] }, targetsOf),
    prune: (tokens) =>
      call("prune_push_tokens", { tokens: [...tokens] }, (value) =>
        typeof value === "number" ? value : Number(value ?? 0),
      ),
  };
}

/** The part of `expo-notifications` `registerDevice` uses. */
export interface ExpoNotificationsLike {
  getPermissionsAsync(): Promise<{ readonly status: string }>;
  requestPermissionsAsync(): Promise<{ readonly status: string }>;
  getExpoPushTokenAsync(options?: {
    readonly projectId?: string;
  }): Promise<{ readonly data: string }>;
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
 *   devices: createPushDevices({ transport: rpcTransport(supabase) }),
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
    if (!isPlatform(platform)) return null;
    let { status } = await notifications.getPermissionsAsync();
    if (status !== "granted" && (options.request ?? true))
      ({ status } = await notifications.requestPermissionsAsync());
    if (status !== "granted") return null;
    const { data: token } = await notifications.getExpoPushTokenAsync(
      options.projectId === undefined ? {} : { projectId: options.projectId },
    );
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
 * Wraps `signOut` so it first removes this device's token, while the
 * session can still call `unregister_push_device`. A failed unregister
 * doesn't stop the sign-out.
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
    if (token) await options.devices.unregister(token);
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

export interface ExpoReceiptResult {
  readonly delivered: number;
  readonly failed: readonly ExpoPushTicket[];
  /** Tokens deleted because Expo reported `DeviceNotRegistered`. */
  readonly pruned: number;
}

export interface ExpoPushOptions {
  /** The Expo access token, when the project turns on push security. */
  readonly accessToken?: string;
  /** Prunes tokens Expo reports as `DeviceNotRegistered`. */
  readonly devices?: PushDevices;
  readonly fetch?: typeof fetch;
  /** Defaults to `https://exp.host/--/api/v2/push`. */
  readonly endpoint?: string;
}

export interface ExpoPush {
  /** Sends `message` to each token, 100 per request; tickets come back in token order. */
  readonly send: (
    tokens: readonly string[],
    message: ExpoPushMessage,
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
  for (let at = 0; at < items.length; at += size)
    out.push(items.slice(at, at + size));
  return out;
}

function recordOrEmpty(value: unknown): Readonly<Record<string, unknown>> {
  return typeof value === "object" && value !== null && !Array.isArray(value)
    ? Object.fromEntries(Object.entries(value))
    : {};
}

function errorCode(entry: Readonly<Record<string, unknown>>): string {
  const details = recordOrEmpty(entry["details"]);
  const code = details["error"];
  return typeof code === "string" ? code : "Unknown";
}

/**
 * A sender for the Expo Push API that needs only `fetch`. Tokens Expo
 * reports as `DeviceNotRegistered`, in a ticket or a receipt, are pruned
 * from `push_devices` when `devices` is set.
 */
export function expoPush(options: ExpoPushOptions = {}): ExpoPush {
  const endpoint = options.endpoint ?? "https://exp.host/--/api/v2/push";
  const doFetch = options.fetch ?? globalThis.fetch;
  const headers: Record<string, string> = {
    accept: "application/json",
    "content-type": "application/json",
    ...(options.accessToken
      ? { authorization: `Bearer ${options.accessToken}` }
      : {}),
  };
  const post = async (path: string, body: unknown): Promise<unknown> => {
    const response = await doFetch(`${endpoint}/${path}`, {
      method: "POST",
      headers,
      body: JSON.stringify(body),
    });
    const text = await response.text();
    if (!response.ok)
      throw new Error(
        `Expo Push API ${path} answered ${String(response.status)}: ${text.slice(0, 500)}`,
      );
    const parsed: unknown = text === "" ? {} : JSON.parse(text);
    return recordOrEmpty(parsed)["data"];
  };
  const prune = async (tokens: readonly string[]): Promise<number> => {
    if (!options.devices || tokens.length === 0) return 0;
    let pruned = 0;
    for (const chunk of chunks([...new Set(tokens)], RECEIPT_CHUNK))
      pruned += await options.devices.prune(chunk).orThrow();
    return pruned;
  };
  return {
    send: async (tokens, message) => {
      const tickets: ExpoPushTicket[] = [];
      for (const chunk of chunks(tokens, SEND_CHUNK)) {
        const data = await post(
          "send",
          chunk.map((to) => ({ ...message, to })),
        );
        const list: readonly unknown[] = Array.isArray(data) ? data : [];
        chunk.forEach((token, at) => {
          const entry = recordOrEmpty(list[at]);
          const message =
            typeof entry["message"] === "string" ? entry["message"] : undefined;
          tickets.push(
            entry["status"] === "ok" && typeof entry["id"] === "string"
              ? { token, id: entry["id"] }
              : {
                  token,
                  error: errorCode(entry),
                  ...(message === undefined ? {} : { message }),
                },
          );
        });
      }
      await prune(
        tickets
          .filter((ticket) => ticket.error === NOT_REGISTERED)
          .map((ticket) => ticket.token),
      );
      return tickets;
    },
    checkReceipts: async (tickets) => {
      const byId = new Map<string, string>();
      for (const ticket of tickets)
        if (ticket.id !== undefined) byId.set(ticket.id, ticket.token);
      let delivered = 0;
      const failed: ExpoPushTicket[] = [];
      for (const ids of chunks([...byId.keys()], RECEIPT_CHUNK)) {
        const receipts = recordOrEmpty(await post("getReceipts", { ids }));
        for (const id of ids) {
          const receipt = receipts[id];
          if (receipt === undefined) continue;
          const entry = recordOrEmpty(receipt);
          if (entry["status"] === "ok") {
            delivered += 1;
            continue;
          }
          const message =
            typeof entry["message"] === "string" ? entry["message"] : undefined;
          failed.push({
            token: byId.get(id) ?? "",
            id,
            error: errorCode(entry),
            ...(message === undefined ? {} : { message }),
          });
        }
      }
      const pruned = await prune(
        failed
          .filter((ticket) => ticket.error === NOT_REGISTERED)
          .map((ticket) => ticket.token),
      );
      return { delivered, failed, pruned };
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
  /** Receives the tickets, to check their receipts later. */
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
 * devices. A recipient without devices is `skipped`; when every ticket
 * fails for a reason other than an unregistered device, it throws so the
 * delivery is retried.
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
      if (tokens.length === 0) return { status: "skipped", provider: "expo" };
      const tickets = await options.push.send(tokens, build(message));
      await options.onTickets?.(tickets, message);
      const sent = tickets.find((ticket) => ticket.id !== undefined);
      if (sent?.id !== undefined)
        return { provider: "expo", providerMessageId: sent.id };
      const retryable = tickets.find(
        (ticket) => ticket.error !== NOT_REGISTERED,
      );
      if (retryable)
        throw new Error(
          `Expo rejected the push: ${retryable.error ?? "Unknown"}${retryable.message ? ` (${retryable.message})` : ""}`,
        );
      return { status: "skipped", provider: "expo" };
    },
  };
}
