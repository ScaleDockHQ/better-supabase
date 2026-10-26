import type { BlockTransport } from "../core/block-transport.ts";
import type { Result } from "../core/result.ts";
import type { TopicPort } from "../realtime/watch-topic.ts";
import type { UploadFunction } from "./connector.ts";
import type { PowerSyncDatabaseLike, SqliteContextLike } from "./executor.ts";

import { quoteSqliteIdent } from "../compile/sqlite.ts";
import { dbError } from "../core/errors.ts";
import { err, ok } from "../core/result.ts";
import { postgrestTimestamp } from "./executor.ts";

/** The notification functions the local transport answers from SQLite. */
export type LocalNotificationFunction =
  | "get_notification"
  | "list_notifications"
  | "notification_page"
  | "notification_counts"
  | "mark_notifications_read"
  | "mark_notifications_unread"
  | "dismiss_notifications";

const FUNCTIONS: readonly LocalNotificationFunction[] = [
  "get_notification",
  "list_notifications",
  "notification_page",
  "notification_counts",
  "mark_notifications_read",
  "mark_notifications_unread",
  "dismiss_notifications",
];

export interface PowerSyncNotificationsOptions {
  /**
   * Where every other function goes, and every call when `local` is `false`:
   * `rpcTransport(supabase)`.
   */
  readonly server: BlockTransport;
  /**
   * The synced table names, as `powersync streams` wrote them into the client
   * schema. Default `notification_recipients` and `notification_events`.
   */
  readonly tables?: { readonly recipients?: string; readonly events?: string };
  /**
   * The tenant column, when `config.tenancy` renames it. Default
   * `organization_id`.
   */
  readonly tenantColumn?: string;
  /** Function names, when the instance renames them (`blocks.<name>.entities`). */
  readonly functions?: Partial<Record<LocalNotificationFunction, string>>;
}

/** Event columns the item reads by name; any other column becomes a field. */
const EVENT_COLUMNS = new Set([
  "id",
  "type",
  "data",
  "actor_id",
  "subject_type",
  "subject_id",
  "subject_label",
  "summary",
  "action_path",
  "actions",
  "priority",
  "created_at",
  "updated_at",
]);

type Row = Readonly<Record<string, unknown>>;

/**
 * A block transport for the notifications module on PowerSync: the feed, its
 * counts and marking read, unread or dismissed run on the synced tables, so the
 * inbox works offline. Writes go into PowerSync's upload queue, which
 * `notificationRecipientsRoute` replays on the server. Every other function
 * (sending, preferences, resolving) goes to `server`.
 *
 * ```ts
 * const notifications = createNotifications({
 *   transport: powersyncNotificationsTransport(powersync, {
 *     server: rpcTransport(supabase),
 *   }),
 * });
 * ```
 *
 * The synced rows are the signed-in user's only (the `powersync streams` query
 * filters by `auth.user_id()`), so the local reads add no user filter.
 */
export function powersyncNotificationsTransport(
  database: PowerSyncDatabaseLike,
  options: PowerSyncNotificationsOptions,
): BlockTransport {
  const recipients = quoteSqliteIdent(
    options.tables?.recipients ?? "notification_recipients",
  );

  const events = quoteSqliteIdent(
    options.tables?.events ?? "notification_events",
  );

  const tenant = options.tenantColumn ?? "organization_id";
  const tenantColumn = quoteSqliteIdent(tenant);

  const byName = new Map<string, LocalNotificationFunction>(
    FUNCTIONS.map((fn) => [options.functions?.[fn] ?? fn, fn]),
  );

  const toItem = (recipient: Row, event: Row): Record<string, unknown> => {
    const fields: Record<string, unknown> = {};

    for (const [key, value] of Object.entries(event)) {
      if (!EVENT_COLUMNS.has(key) && key !== tenant) {
        fields[key] = value;
      }
    }

    return {
      id: recipient["id"],
      event_id: event["id"],
      type: event["type"],
      data: json(event["data"]) ?? {},
      created_at: timestamp(recipient["created_at"]),
      read_at: timestamp(recipient["read_at"]),
      tenant: event[tenant] ?? null,
      actor_id: event["actor_id"] ?? null,
      subject_type: event["subject_type"] ?? null,
      subject_id: event["subject_id"] ?? null,
      subject_label: event["subject_label"] ?? null,
      summary: event["summary"] ?? null,
      action_path: event["action_path"] ?? null,
      actions: json(event["actions"]) ?? [],
      priority: event["priority"] ?? null,
      resolved_at: timestamp(recipient["resolved_at"]),
      resolution: json(recipient["resolution"]) ?? null,
      ...(Object.keys(fields).length === 0 ? {} : { fields }),
    };
  };

  /** Recipients with their events, newest first. */
  const items = async (
    context: SqliteContextLike,
    where: string,
    parameters: unknown[],
  ): Promise<Record<string, unknown>[]> => {
    const rows = await context.getAll<Row>(
      `SELECT rc.* FROM ${recipients} rc JOIN ${events} ev ON ev.id = rc.event_id WHERE ${where}`,
      parameters,
    );

    const ids = [...new Set(rows.map((row) => String(row["event_id"])))];

    const found =
      ids.length === 0
        ? []
        : await context.getAll<Row>(
            `SELECT * FROM ${events} WHERE id IN (${marks(ids)})`,
            ids,
          );

    const eventsById = new Map(found.map((row) => [String(row["id"]), row]));

    return rows
      .flatMap((row) => {
        const event = eventsById.get(String(row["event_id"]));

        return event === undefined ? [] : [toItem(row, event)];
      })
      .toSorted(newestFirst);
  };

  const filters = (args: Row, clauses: string[], parameters: unknown[]) => {
    const add = (clause: string, ...values: unknown[]): void => {
      clauses.push(clause);
      parameters.push(...values);
    };

    if (typeof args["tenant"] === "string") {
      add(`rc.${tenantColumn} = ?`, args["tenant"]);
    }

    const dismissed =
      args["status"] === "settled" ? null : (args["dismissed"] ?? false);

    if (dismissed !== null) {
      clauses.push(
        dismissed === true
          ? "rc.dismissed_at IS NOT NULL"
          : "rc.dismissed_at IS NULL",
      );
    }

    switch (args["status"]) {
      case "unread": {
        clauses.push("rc.read_at IS NULL");
        break;
      }

      case "read": {
        clauses.push("rc.read_at IS NOT NULL");
        break;
      }

      case "unresolved": {
        clauses.push("rc.resolved_at IS NULL");
        break;
      }

      case "settled": {
        clauses.push(
          "(rc.resolved_at IS NOT NULL OR rc.dismissed_at IS NOT NULL)",
        );
        break;
      }

      default: {
        break;
      }
    }

    if (typeof args["read"] === "boolean") {
      clauses.push(
        args["read"] ? "rc.read_at IS NOT NULL" : "rc.read_at IS NULL",
      );
    }

    if (typeof args["resolved"] === "boolean") {
      clauses.push(
        args["resolved"]
          ? "rc.resolved_at IS NOT NULL"
          : "rc.resolved_at IS NULL",
      );
    }

    for (const [key, column] of [
      ["types", "ev.type"],
      ["subject_types", "ev.subject_type"],
    ] as const) {
      const values = arrayOf(args[key]);

      if (values !== undefined) {
        add(
          values.length === 0 ? "0" : `${column} IN (${marks(values)})`,
          ...values,
        );
      }
    }

    if (typeof args["search"] === "string" && args["search"] !== "") {
      add(
        "(coalesce(ev.summary, '') || ' ' || coalesce(ev.subject_label, '') || ' ' || ev.type) LIKE ? ESCAPE '\\'",
        `%${args["search"].replaceAll(/[\\%_]/gu, (match) => `\\${match}`)}%`,
      );
    }
  };

  const list = async (args: Row): Promise<Record<string, unknown>[]> => {
    const clauses: string[] = [];
    const parameters: unknown[] = [];

    filters(args, clauses, parameters);

    const all = await items(database, joined(clauses), parameters);
    const before = typeof args["before"] === "string" ? args["before"] : null;

    const beforeId =
      typeof args["before_id"] === "string" ? args["before_id"] : null;

    return before === null
      ? all
      : all.filter((item) => {
          const at = time(item["created_at"]);
          const cursor = Date.parse(postgrestTimestamp(before));

          return (
            at < cursor ||
            (at === cursor &&
              beforeId !== null &&
              String(item["id"]) < beforeId)
          );
        });
  };

  const mark = async (
    set: string,
    stamps: number,
    where: string,
    args: Row,
  ): Promise<{ count: number; items: Record<string, unknown>[] }> =>
    database.writeTransaction(async (tx) => {
      const clauses = [where];
      const parameters: unknown[] = [];
      const ids = arrayOf(args["ids"]);

      if (ids !== undefined) {
        clauses.push(ids.length === 0 ? "0" : `rc.id IN (${marks(ids)})`);
        parameters.push(...ids);
      }

      if (typeof args["tenant"] === "string") {
        clauses.push(`rc.${tenantColumn} = ?`);
        parameters.push(args["tenant"]);
      }

      const targets = await tx.getAll<{ id: unknown }>(
        `SELECT rc.id FROM ${recipients} rc WHERE ${clauses.join(" AND ")}`,
        parameters,
      );

      const changed = targets.map((row) => row.id);

      if (changed.length === 0) {
        return { count: 0, items: [] };
      }

      const now = new Date().toISOString();

      await tx.execute(
        `UPDATE ${recipients} SET ${set} WHERE id IN (${marks(changed)})`,
        [...Array.from({ length: stamps }, () => now), ...changed],
      );

      const updated = await items(tx, `rc.id IN (${marks(changed)})`, changed);

      return { count: updated.length, items: updated };
    });

  const local = async (
    fn: LocalNotificationFunction,
    args: Row,
  ): Promise<unknown> => {
    switch (fn) {
      case "get_notification": {
        const [item] = await items(database, "rc.id = ?", [args["id"]]);

        return item ?? null;
      }

      case "list_notifications": {
        return (await list(args)).slice(0, limit(args["max_items"], 0));
      }

      case "notification_page": {
        const all = await list(args);
        const skip = Math.max(Number(args["skip"] ?? 0), 0);

        return {
          items: all.slice(skip, skip + limit(args["max_items"], 1)),
          total: all.length,
        };
      }

      case "notification_counts": {
        return counts(await list({ tenant: args["tenant"] }), args);
      }

      case "mark_notifications_read": {
        return mark(
          "read_at = ?",
          1,
          "rc.read_at IS NULL AND rc.dismissed_at IS NULL",
          args,
        );
      }

      case "mark_notifications_unread": {
        return mark(
          "read_at = NULL",
          0,
          "rc.read_at IS NOT NULL AND rc.dismissed_at IS NULL",
          args,
        );
      }

      case "dismiss_notifications": {
        return mark(
          "dismissed_at = ?, read_at = coalesce(read_at, ?)",
          2,
          "rc.dismissed_at IS NULL",
          { ids: args["ids"] },
        );
      }

      default: {
        const unhandled: never = fn;

        throw new TypeError(
          `Unhandled notification function ${String(unhandled)}`,
        );
      }
    }
  };

  return {
    call(schema, fn, args) {
      const handled = byName.get(fn);

      return handled === undefined
        ? options.server.call(schema, fn, args)
        : local(handled, args);
    },
  };
}

function counts(
  all: readonly Record<string, unknown>[],
  args: Row,
): { unread: number; actionable: number; actionable_subjects: number } {
  const actionable = new Set(
    Array.isArray(args["actionable"]) ? args["actionable"].map(String) : [],
  );

  const open = all.filter(
    (item) =>
      item["resolved_at"] === null && actionable.has(String(item["type"])),
  );

  const subjects = new Set(
    open.map((item) =>
      item["subject_id"] === null
        ? `recipient:${String(item["id"])}`
        : JSON.stringify([
            item["tenant"],
            item["subject_type"],
            item["subject_id"],
          ]),
    ),
  );

  return {
    unread: all.filter((item) => item["read_at"] === null).length,
    actionable: open.length,
    actionable_subjects: subjects.size,
  };
}

/**
 * The upload route's notifications client: the server one, not the local
 * transport.
 */
export interface NotificationRecipientWrites {
  markRead(options: {
    readonly ids: readonly string[];
  }): PromiseLike<Result<unknown>>;
  markUnread(options: {
    readonly ids: readonly string[];
  }): PromiseLike<Result<unknown>>;
  dismiss(ids: readonly string[]): PromiseLike<Result<unknown>>;
}

/**
 * The upload route for `notification_recipients`: replays a local mark read,
 * unread or dismiss through the server's functions, which check the caller owns
 * the row. Pass a notifications client on `rpcTransport(supabase)`; one on
 * `powersyncNotificationsTransport` would write the change locally again.
 *
 * ```ts
 * createUploadConnector({
 *   tables: {
 *     notification_recipients: notificationRecipientsRoute(
 *       serverNotifications,
 *     ),
 *   },
 * });
 * ```
 */
export function notificationRecipientsRoute(
  notifications: NotificationRecipientWrites,
): UploadFunction {
  return async (entry) => {
    const data = entry.opData ?? {};
    const ids = [entry.id];

    if (entry.op !== "PATCH") {
      return err(
        dbError(
          "unsupported",
          `notification_recipients takes updates only, not ${entry.op}`,
        ),
      );
    }

    if (data["dismissed_at"] !== undefined && data["dismissed_at"] !== null) {
      return notifications.dismiss(ids);
    }

    if (data["read_at"] === undefined) {
      return ok(null);
    }

    return data["read_at"] === null
      ? notifications.markUnread({ ids })
      : notifications.markRead({ ids });
  };
}

/**
 * A topic port for the notifications feed on PowerSync: the feed reads again
 * when the synced notification tables change, from a sync or a local write,
 * instead of on a Realtime broadcast.
 *
 * ```ts
 * createNotificationsController({
 *   ports: { topic: powersyncTopicPort(powersync) },
 * });
 * ```
 */
export function powersyncTopicPort(
  database: PowerSyncDatabaseLike,
  tables: readonly string[] = [
    "notification_recipients",
    "notification_events",
  ],
): TopicPort {
  return (_topic, watch) => {
    const unsubscribe = database.onChange?.(
      {
        onChange: (event) => {
          if (event.changedTables.some((table) => tables.includes(table))) {
            watch.onMessage("change", { tables: event.changedTables });
          }
        },
      },
      { tables: [...tables] },
    );

    watch.onStatus("subscribed");

    let left = false;

    return {
      leave: () => {
        if (!left) {
          left = true;
          unsubscribe?.();
        }
      },
      send: () => undefined,
    };
  };
}

function arrayOf(value: unknown): readonly unknown[] | undefined {
  return Array.isArray(value) ? value.map((item: unknown) => item) : undefined;
}

function marks(values: readonly unknown[]): string {
  return values.map(() => "?").join(", ");
}

function joined(clauses: readonly string[]): string {
  return clauses.length === 0 ? "1" : clauses.join(" AND ");
}

function limit(value: unknown, least: number): number {
  const parsed = Number(value ?? 50);

  return Math.min(Math.max(Number.isFinite(parsed) ? parsed : 50, least), 200);
}

function json(value: unknown): unknown {
  if (typeof value !== "string") {
    return value ?? undefined;
  }

  try {
    return JSON.parse(value);
  } catch {
    return value;
  }
}

function timestamp(value: unknown): string | null {
  return typeof value === "string" ? postgrestTimestamp(value) : null;
}

function time(value: unknown): number {
  return typeof value === "string" ? Date.parse(value) : 0;
}

function newestFirst(
  left: Record<string, unknown>,
  right: Record<string, unknown>,
): number {
  const order = time(right["created_at"]) - time(left["created_at"]);

  if (order !== 0) {
    return order;
  }

  return String(right["id"]).localeCompare(String(left["id"]));
}
