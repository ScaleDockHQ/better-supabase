import type { InboxSql } from "./inbox-names.ts";

import { sqlString } from "../../core/template.ts";

/** A column and the SQL value written to it. */
export type InboxEntry = readonly [column: string, value: string];

/** Helpers for the columns an app's table may lack. */
export interface InboxColumns {
  /** `alias.column`, or `fallback` where the app's table lacks the column. */
  readonly or: (
    table: string,
    alias: string,
    column: string,
    fallback?: string,
  ) => string;
  /** `column` of the updated row, or null where the app's table lacks it. */
  readonly own: (table: string, column: string) => string;
  /** The entries whose column exists. */
  readonly present: (
    table: string,
    entries: readonly InboxEntry[],
  ) => InboxEntry[];
  /** The column list of `entries`. */
  readonly columnsOf: (table: string, entries: readonly InboxEntry[]) => string;
  /** The value list of `entries`. */
  readonly valuesOf: (entries: readonly InboxEntry[]) => string;
}

export function inboxColumns(q: InboxSql): InboxColumns {
  const { has } = q;

  return {
    or: (table, alias, column, fallback = "null") =>
      has(table, column) ? `${alias}.${q.cols(table)(column)}` : fallback,
    own: (table, column) =>
      has(table, column) ? q.cols(table)(column) : "null",
    present: (table, entries) =>
      entries.filter(([column]) => has(table, column)),
    columnsOf: (table, entries) =>
      entries.map(([column]) => q.cols(table)(column)).join(", "),
    valuesOf: (entries) => entries.map(([, value]) => value).join(", "),
  };
}

/** What the inbox's functions write, without the columns the app's table lacks. */
export interface InboxWrites {
  readonly newInbox: readonly InboxEntry[];
  readonly inboxPatch: readonly InboxEntry[];
  readonly detailsHead: readonly InboxEntry[];
  readonly detailsTail: readonly InboxEntry[];
  readonly startHead: readonly InboxEntry[];
  readonly startMid: readonly InboxEntry[];
  readonly startTail: readonly InboxEntry[];
  readonly inboundConversation: readonly InboxEntry[];
}

export function inboxWrites(q: InboxSql): InboxWrites {
  const { own, present } = inboxColumns(q);

  // A typed optional column's value; `present` drops it where the app's table
  // lacks the column.
  const typed = (table: string, column: string, value: string): string =>
    q.has(table, column) ? q.cast(table, column, value) : "null";

  const ib = q.cols("inboxes");
  const cv = q.cols("conversations");

  const newInbox = present("inboxes", [
    ["tenant", "create_inbox.tenant"],
    ["name", "create_inbox.name"],
    [
      "channel",
      q.cast("inboxes", "channel", "coalesce(create_inbox.channel, 'in_app')"),
    ],
    ["settings", "coalesce(create_inbox.settings, '{}'::jsonb)"],
    [
      "botMode",
      q.cast("inboxes", "botMode", "coalesce(create_inbox.bot_mode, 'human')"),
    ],
    ["address", "create_inbox.address"],
  ]);

  const inboxPatch = present("inboxes", [
    ["name", `coalesce(patch ->> 'name', ${ib("name")})`],
    [
      "settings",
      `${own("inboxes", "settings")} || coalesce(patch -> 'settings', '{}'::jsonb)`,
    ],
    [
      "botMode",
      `coalesce(${q.cast("inboxes", "botMode", "patch ->> 'bot_mode'")}, ${ib("botMode")})`,
    ],
    [
      "address",
      `case when patch ? 'address' then patch ->> 'address' else ${own("inboxes", "address")} end`,
    ],
    [
      "installation",
      `case when patch ? 'installation_id' then (patch ->> 'installation_id')::uuid else ${own("inboxes", "installation")} end`,
    ],
    [
      "archivedAt",
      `case when patch ? 'archived' then (case when (patch ->> 'archived')::boolean then coalesce(${own("inboxes", "archivedAt")}, now()) end) else ${own("inboxes", "archivedAt")} end`,
    ],
  ]);

  const detailsHead: InboxEntry[] = [
    ["message", "v_id"],
    ["tenant", `v_conv.${cv("tenant")}`],
    ["conversation", `v_conv.${cv("id")}`],
    [
      "direction",
      q.cast("details", "direction", "inbox_add_message.direction"),
    ],
    [
      "authorType",
      q.cast("details", "authorType", "inbox_add_message.author_type"),
    ],
  ];

  const detailsTail = present("details", [
    [
      "format",
      typed("details", "format", "coalesce(input ->> 'format', 'text')"),
    ],
    ["externalId", "input ->> 'external_id'"],
    ["replyTo", "(input ->> 'reply_to')::uuid"],
    ["metadata", "coalesce(input -> 'metadata', '{}'::jsonb)"],
  ]);

  const startHead: InboxEntry[] = [
    ["id", "v_id"],
    ["tenant", `v_inbox.${ib("tenant")}`],
    ["inbox", `v_inbox.${ib("id")}`],
    ["contact", "v_contact"],
  ];

  const startMid = present("conversations", [
    ["subject", "input ->> 'subject'"],
    [
      "priority",
      typed(
        "conversations",
        "priority",
        "coalesce(input ->> 'priority', 'normal')",
      ),
    ],
  ]);

  const startTail = present("conversations", [
    [
      "botMode",
      q.cast(
        "conversations",
        "botMode",
        `coalesce(input ->> 'bot_mode', ${q.text("inboxes", `v_inbox.${ib("botMode")}`)})`,
      ),
    ],
    [
      "thread",
      `coalesce(input ->> 'thread_id', ${sqlString(`${q.topic}:`)} || v_inbox.${ib("id")}::text || ':' || v_id::text)`,
    ],
    ["assignee", "case when v_staff then (input ->> 'assignee_id')::uuid end"],
    ["metadata", "coalesce(input -> 'metadata', '{}'::jsonb)"],
  ]);

  const inboundConversation = present("conversations", [
    ["id", "v_id"],
    ["tenant", `v_inbox.${ib("tenant")}`],
    ["inbox", `v_inbox.${ib("id")}`],
    ["contact", "v_contact"],
    ["subject", "input ->> 'subject'"],
    [
      "botMode",
      q.cast(
        "conversations",
        "botMode",
        q.text("inboxes", `v_inbox.${ib("botMode")}`),
      ),
    ],
    ["thread", "input ->> 'thread_id'"],
    ["metadata", "coalesce(input -> 'metadata', '{}'::jsonb)"],
  ]);

  return {
    newInbox,
    inboxPatch,
    detailsHead,
    detailsTail,
    startHead,
    startMid,
    startTail,
    inboundConversation,
  };
}
