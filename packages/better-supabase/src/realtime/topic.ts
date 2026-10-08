import type { StandardSchemaV1 } from "@standard-schema/spec";

import {
  type RealtimeChannel,
  type RealtimePresenceState,
  REALTIME_SUBSCRIBE_STATES,
  type SupabaseClient,
} from "@supabase/supabase-js";

import type { BetterSupabase } from "../core/define.ts";
import type {
  AnyFunctions,
  AnyModels,
  PermdockTopicPolicy,
  Row,
  TableKey,
  TableMeta,
} from "../schema/types.ts";

import { tenantClaimPaths } from "../core/claims.ts";
import { dbError, type DbError, type ValidationIssue } from "../core/errors.ts";
import { type PermdockCatalog, permdockCheck } from "../core/permdock-sql.ts";
import { AsyncResult, err, ok } from "../core/result.ts";
import {
  parseTemplate,
  slug,
  sqlIdent,
  sqlString,
  type Template,
  type TemplateParams,
  type TemplateValues,
} from "../core/template.ts";
import { toApp } from "../plugins/shared.ts";
import { refreshRealtimeAuth } from "./auth.ts";

export type EventSchemas = Readonly<Record<string, StandardSchemaV1>>;

/** `true`, or a schema every tracked presence state is validated against. */
export type PresenceSchema = boolean | StandardSchemaV1;

export interface TopicOptions<
  E extends EventSchemas,
  R extends PresenceSchema = PresenceSchema,
> {
  /** Name used for generated policies and functions. Defaults to the template's literal parts. */
  readonly name?: string;
  /** Payload schemas per event. Incoming and outgoing payloads are validated. */
  readonly events?: E;
  /** Private channels are authorized by `realtime.messages` policies. Defaults to `true`. */
  readonly private?: boolean;
  /**
   * Tenant check for the generated policy. Defaults to `{organizationId}` against
   * `tenant_id` / `app_metadata.tenant_id` when the template has `{organizationId}`.
   */
  readonly tenant?:
    | false
    | {
        readonly param?: string;
        readonly claim?: string | readonly string[];
        readonly sql?: string;
      };
  /** Owner check. Defaults to `{userId}` against `auth.uid()` when the template has `{userId}`. */
  readonly owner?: false | { readonly param?: string };
  /**
   * Authorize with PermDock's SQL helpers instead of the tenant claim:
   * `permitted_<scope>_ids(receive)` on the scope segment (or
   * `permdock_has` for `scope: 'global'`), and `send` for broadcasting.
   *
   * The helpers check role and scope only. Use this just for permissions
   * whose grants have no row conditions beyond the scope: for a permission
   * with row conditions (e.g. `authorId = principal.id`) every member of the
   * scope could join. Pass `catalog` to refuse those keys here;
   * `better-supabase doctor` (BS214) refuses them from the catalog file.
   */
  readonly permdock?: PermdockTopicPolicy;
  /**
   * PermDock's `permissions.catalog.json`. With it, a `permdock` policy
   * naming a permission without `rowConditions: false` (including one the
   * catalog doesn't list) throws.
   */
  readonly catalog?: PermdockCatalog;
  /** Let clients broadcast on the topic, not only receive. Defaults to `false`. */
  readonly send?: boolean;
  /**
   * Presence: authorizes it in the policies and adds `track` and
   * `onPresence` to subscriptions. Pass a schema to validate the states
   * this client tracks and the ones it receives. Defaults to `false`.
   */
  readonly presence?: R;
}

export interface TopicMessage {
  readonly event: string;
  readonly payload: unknown;
  readonly topic: string;
}

type Output<S> = S extends StandardSchemaV1
  ? StandardSchemaV1.InferOutput<S>
  : unknown;
type Input<S> = S extends StandardSchemaV1
  ? StandardSchemaV1.InferInput<S>
  : unknown;

export type TopicHandlers<E extends EventSchemas> = [keyof E] extends [never]
  ? {
      readonly [event: string]:
        | ((payload: unknown, message: TopicMessage) => void)
        | undefined;
    }
  : {
      readonly [K in keyof E & string]?: (
        payload: Output<E[K]>,
        message: TopicMessage,
      ) => void;
    } & {
      readonly "*"?: (payload: unknown, message: TopicMessage) => void;
    };

export type TopicEvent<E extends EventSchemas> = [keyof E] extends [never]
  ? string
  : keyof E & string;
export type TopicPayload<E extends EventSchemas, K extends string> = [
  keyof E,
] extends [never]
  ? unknown
  : Input<E[K]>;

export type SubscriptionStatus = "joining" | "subscribed" | "closed" | "error";

export interface SubscribeOptions {
  /** Receive your own broadcasts. */
  readonly self?: boolean;
  readonly onStatus?: (status: SubscriptionStatus, error?: Error) => void;
  /** Called when a payload fails its event schema. The handler is skipped. */
  readonly onInvalid?: (
    message: TopicMessage,
    issues: readonly ValidationIssue[],
  ) => void;
}

export interface Subscription extends Disposable, AsyncDisposable {
  readonly topic: string;
  readonly channel: RealtimeChannel;
  /** Resolves once joined; rejects if the join is refused or times out. */
  readonly ready: Promise<void>;
  unsubscribe(): Promise<void>;
}

/** One tracked state on a presence topic. */
export interface PresenceMember<S> {
  /** The connection's presence key; a client tracking twice keeps one key. */
  readonly key: string;
  readonly state: S;
}

export interface PresenceOptions<S> {
  /**
   * Called with everyone on the topic, this client included, after each
   * presence sync. States that fail the presence schema are left out and
   * passed to `onInvalid` as a `presence` message.
   */
  readonly onPresence?: (members: readonly PresenceMember<S>[]) => void;
}

export interface PresenceSubscription<I, O> extends Subscription {
  /**
   * Validates the state, waits for the join and shares it with the topic.
   * One state per client and topic: the last `track` wins, and leaving the
   * topic removes it.
   */
  track(state: I): AsyncResult<void>;
  /** Removes this client's state from the topic. */
  untrack(): AsyncResult<void>;
  /** Everyone from the last sync, as `onPresence` received them. */
  members(): readonly PresenceMember<O>[];
}

type PresenceState = Readonly<Record<string, unknown>>;
export type PresenceInput<R> = R extends StandardSchemaV1
  ? StandardSchemaV1.InferInput<R>
  : PresenceState;
export type PresenceOutput<R> = R extends StandardSchemaV1
  ? StandardSchemaV1.InferOutput<R>
  : PresenceState;

/** What `subscribe` returns: with `track` and `members` on presence topics. */
export type TopicSubscription<R> = [R] extends [false]
  ? Subscription
  : PresenceSubscription<PresenceInput<R>, PresenceOutput<R>>;

/** `subscribe` options: with `onPresence` on presence topics. */
export type TopicSubscribeOptions<R> = [R] extends [false]
  ? SubscribeOptions
  : SubscribeOptions & PresenceOptions<PresenceOutput<R>>;

export type RealtimeClient = Pick<
  SupabaseClient,
  "channel" | "getChannels" | "removeChannel" | "realtime"
>;

/**
 * A value read from another table: the `select` column of the `from` row
 * whose `key` (its primary key by default) equals `via`, a column of the
 * changed row or another lookup.
 */
export interface TriggerLookup<M extends AnyModels> {
  readonly from: TableKey<M>;
  readonly via: string | TriggerLookup<M>;
  readonly select: string;
  readonly key?: string;
}

/** A trigger value: a column of the changed row, or a lookup through it. */
export type TriggerValue<M extends AnyModels, T extends keyof M> =
  | Extract<keyof Row<M, T>, string>
  | TriggerLookup<M>;

type TriggerOperation = "insert" | "update" | "delete";

export interface TriggerOptions<
  M extends AnyModels,
  T extends keyof M,
  P extends string,
> {
  /**
   * What fills each placeholder: a column of the changed row, or a lookup
   * (`{ from, via, select }`) for a value on a parent row. A row whose
   * topic comes out null is not sent.
   */
  readonly values: {
    readonly [K in TemplateParams<P>]: TriggerValue<M, T>;
  };
  /** Defaults to all three. */
  readonly events?: readonly TriggerOperation[];
  /**
   * The broadcast event name, or one per operation. Defaults to the
   * operation (`INSERT`, `UPDATE`, `DELETE`).
   */
  readonly event?: string | { readonly [O in TriggerOperation]?: string };
  /**
   * Send this payload with `realtime.send` instead of the row change from
   * `realtime.broadcast_changes`: each key is a column, a lookup, or
   * `{ sql }`, an expression on the row `{row}` (`tg_op` is the operation).
   */
  readonly payload?: Readonly<
    Record<string, TriggerValue<M, T> | { readonly sql: string }>
  >;
  /**
   * Schema for the generated function. Defaults to `better_supabase`, which
   * the Data API does not expose.
   */
  readonly functionSchema?: string;
}

export interface RowChange<R> {
  readonly operation: "INSERT" | "UPDATE" | "DELETE";
  readonly table: string;
  readonly record: R | null;
  readonly oldRecord: Partial<R> | null;
}

export interface Topic<
  P extends string,
  E extends EventSchemas,
  R extends PresenceSchema = false,
> {
  readonly template: P;
  readonly name: string;
  readonly params: readonly TemplateParams<P>[];
  readonly private: boolean;
  /** Whether subscriptions get `track` and `onPresence`. */
  readonly presence: boolean;
  topic(values: TemplateValues<P>): string;
  match(topic: string): TemplateValues<P> | null;
  /** `realtime.messages` policies for this topic. Idempotent. */
  sql(): string;
  /** A trigger that broadcasts row changes (`realtime.broadcast_changes`) to this topic. */
  triggerSql<
    M extends AnyModels,
    D,
    F extends AnyFunctions,
    X,
    T extends TableKey<M>,
  >(
    betterSupabase: BetterSupabase<M, D, F, X>,
    table: T,
    options: TriggerOptions<M, T, P>,
  ): string;
  subscribe(
    client: RealtimeClient,
    values: TemplateValues<P>,
    handlers: TopicHandlers<E>,
    options?: TopicSubscribeOptions<R>,
  ): TopicSubscription<R>;
  /** Sends over HTTP, without joining the channel. */
  send<K extends TopicEvent<E>>(
    client: RealtimeClient,
    values: TemplateValues<P>,
    event: K,
    payload: TopicPayload<E, K>,
  ): AsyncResult<void>;
}

interface Subscriber {
  readonly onStatus: SubscribeOptions["onStatus"];
  readonly receive: (message: TopicMessage) => void;
  readonly sync?: (state: RealtimePresenceState) => void;
}

interface SharedTopic {
  readonly channel: RealtimeChannel;
  readonly self: boolean;
  readonly presence: boolean;
  readonly subscribers: Set<Subscriber>;
  readonly ready: Promise<void>;
  subscribed: boolean;
  synced: boolean;
  /** The subscriber whose `track` set this client's presence state. */
  tracker: Subscriber | undefined;
}

const topicChannels = new WeakMap<RealtimeClient, Map<string, SharedTopic>>();

/**
 * One channel per topic and client, shared by every `subscribe()` on it:
 * supabase-js hands back the open channel for a topic, so a second join or
 * an early `removeChannel` would break the first subscription.
 */
function joinTopic(
  client: RealtimeClient,
  topic: string,
  isPrivate: boolean,
  self: boolean,
  presence: boolean,
  subscriber: Subscriber,
): {
  shared: SharedTopic;
  leave: () => Promise<void>;
} {
  let byTopic = topicChannels.get(client);
  if (!byTopic) {
    byTopic = new Map();
    topicChannels.set(client, byTopic);
  }
  const topics = byTopic;
  let shared = topics.get(topic);
  if (shared && shared.self !== self) {
    throw new TypeError(
      `better-supabase: "${topic}" is already subscribed with self: ${String(shared.self)}; every subscription on a topic needs the same \`self\``,
    );
  }
  if (shared && shared.presence !== presence) {
    throw new TypeError(
      `better-supabase: "${topic}" is already subscribed ${shared.presence ? "with" : "without"} presence; every topic definition for it needs the same \`presence\``,
    );
  }
  if (!shared) {
    const channel = client.channel(topic, {
      config: { private: isPrivate, broadcast: { self } },
    });
    const subscribers = new Set<Subscriber>();
    const status = (next: SubscriptionStatus, error?: Error): void => {
      for (const each of subscribers) each.onStatus?.(next, error);
    };
    channel.on("broadcast", { event: "*" }, (raw) => {
      const message: TopicMessage = {
        event: raw.event,
        payload: raw["payload"],
        topic,
      };
      for (const each of subscribers) each.receive(message);
    });
    // realtime-js refuses presence listeners after `subscribe()`, so the
    // shared channel registers one for every subscriber up front.
    if (presence) {
      channel.on("presence", { event: "sync" }, () => {
        entry.synced = true;
        const state = channel.presenceState();
        for (const each of subscribers) each.sync?.(state);
      });
    }
    const evict = (): void => {
      if (topics.get(topic) !== entry) return;
      topics.delete(topic);
      void client.removeChannel(channel);
    };
    const ready = (async () => {
      // Yields for public topics too: the first subscriber is added after
      // this starts, and one that leaves before the join skips it.
      await (isPrivate ? refreshRealtimeAuth(client) : undefined);
      if (subscribers.size === 0) return;
      await new Promise<void>((resolve, reject) => {
        channel.subscribe((state, error) => {
          // Dropped channels still report CLOSED on removal.
          if (topics.get(topic) !== entry) return;
          switch (state) {
            case REALTIME_SUBSCRIBE_STATES.SUBSCRIBED:
              entry.subscribed = true;
              status("subscribed");
              resolve();
              return;
            case REALTIME_SUBSCRIBE_STATES.CLOSED:
              entry.subscribed = false;
              status("closed");
              resolve();
              return;
            case REALTIME_SUBSCRIBE_STATES.CHANNEL_ERROR:
            case REALTIME_SUBSCRIBE_STATES.TIMED_OUT: {
              const failure =
                error ??
                new Error(`Realtime ${state.toLowerCase()} on ${topic}`);
              status("error", failure);
              reject(failure);
              // A joined channel rejoins on its own; one that never joined is
              // dropped so the next subscribe opens a fresh channel.
              if (!entry.subscribed) evict();
              return;
            }
            default: {
              const unknown: never = state;
              reject(new Error(`Unknown realtime status ${String(unknown)}`));
            }
          }
        });
      });
    })();
    ready.catch(() => undefined);
    const entry: SharedTopic = {
      channel,
      self,
      presence,
      subscribers,
      ready,
      subscribed: false,
      synced: false,
      tracker: undefined,
    };
    shared = entry;
    topics.set(topic, entry);
  }
  const current = shared;
  current.subscribers.add(subscriber);
  subscriber.onStatus?.("joining");
  if (current.subscribed) subscriber.onStatus?.("subscribed");
  if (current.synced) subscriber.sync?.(current.channel.presenceState());
  return {
    shared: current,
    leave: async () => {
      current.subscribers.delete(subscriber);
      if (current.subscribers.size > 0) {
        if (current.tracker === subscriber) {
          current.tracker = undefined;
          await current.channel.untrack();
        }
        return;
      }
      // Removed right away rather than on the next tick like live queries: a
      // resubscribe for another user must join with that user's token.
      if (topics.get(topic) !== current) return;
      topics.delete(topic);
      await client.removeChannel(current.channel);
    },
  };
}

const VALUE = /^[\w.@+=-]+$/;

function validateValue(_name: string, value: string): string | undefined {
  return VALUE.test(value)
    ? undefined
    : "contains characters topics do not allow";
}

function claimSql(claim: string | readonly string[]): string {
  const paths = typeof claim === "string" ? [claim] : claim;
  const expressions = paths.map((path) => {
    const keys = path.split(".");
    const last = keys.pop()!;
    return `(select auth.jwt())${keys.map((key) => ` -> ${sqlString(key)}`).join("")} ->> ${sqlString(last)}`;
  });
  return expressions.length === 1
    ? expressions[0]!
    : `coalesce(${expressions.join(", ")})`;
}

async function validate(
  schema: StandardSchemaV1 | undefined,
  value: unknown,
): Promise<
  | { ok: true; value: unknown }
  | { ok: false; issues: readonly ValidationIssue[] }
> {
  if (!schema) return { ok: true, value };
  const result = await schema["~standard"].validate(value);
  if (result.issues) {
    return {
      ok: false,
      issues: result.issues.map((issue) => ({
        message: issue.message,
        ...(issue.path
          ? {
              path: issue.path.map((part) =>
                typeof part === "object" ? part.key : part,
              ),
            }
          : {}),
      })),
    };
  }
  return { ok: true, value: result.value };
}

function sendError(status: number, message: string): DbError {
  if (status === 401) return dbError("unauthorized", message);
  if (status === 403) return dbError("forbidden", message);
  if (status === 429 || status >= 500 || status === 0)
    return dbError("network", message, status ? { status } : {});
  return dbError("invalid_request", message, { status });
}

type AnyTriggerValue =
  | string
  | {
      readonly from: string;
      readonly via: AnyTriggerValue;
      readonly select: string;
      readonly key?: string;
    };

function columnSql(meta: TableMeta, column: string, where: string): string {
  const db = meta.columns[column]?.db;
  if (!db)
    throw new TypeError(
      `defineTopic: no column for ${where} on "${meta.key}" ("${column}")`,
    );
  return sqlIdent(db);
}

/** A trigger value as SQL on `rec`, with one subquery per lookup. */
function triggerValueSql(
  tables: Readonly<Record<string, TableMeta | undefined>>,
  meta: TableMeta,
  value: AnyTriggerValue,
  where: string,
  depth = 0,
): string {
  if (typeof value === "string") return `rec.${columnSql(meta, value, where)}`;
  const joined = tables[value.from];
  if (!joined)
    throw new TypeError(
      `defineTopic: unknown table "${value.from}" for ${where}`,
    );
  const key =
    value.key ??
    (joined.primaryKey.length === 1 ? joined.primaryKey[0] : undefined);
  if (key === undefined)
    throw new TypeError(
      `defineTopic: "${value.from}" has no single-column primary key; name its key for ${where}`,
    );
  const alias = `j${String(depth)}`;
  const via = triggerValueSql(tables, meta, value.via, where, depth + 1);
  return `(select ${alias}.${columnSql(joined, value.select, where)} from ${sqlIdent(joined.schema)}.${sqlIdent(joined.name)} ${alias} where ${alias}.${columnSql(joined, key, where)} = ${via} limit 1)`;
}

/** The event name: one for every operation, one per operation, or the operation. */
function eventSql(
  event: string | Readonly<Record<string, string | undefined>> | undefined,
): string {
  if (event === undefined) return "tg_op";
  if (typeof event === "string") return sqlString(event);
  const cases = Object.entries(event)
    .filter((entry): entry is [string, string] => entry[1] !== undefined)
    .map(
      ([operation, name]) =>
        ` when ${sqlString(operation.toUpperCase())} then ${sqlString(name)}`,
    );
  return cases.length === 0
    ? "tg_op"
    : `case tg_op${cases.join("")} else tg_op end`;
}

/**
 * A typed Realtime broadcast topic: names from a template, RLS policies for
 * private channels, row-change triggers, and disposable subscriptions.
 *
 * ```ts
 * export const notifications = defineTopic('organization:{organizationId}:notifications:{userId}', {
 *   events: { created: v.object({ id: v.string(), title: v.string() }) },
 * });
 * using sub = notifications.subscribe(supabase, { organizationId, userId }, { created: (n) => toast(n.title) });
 * ```
 */
export function defineTopic<
  const P extends string,
  const E extends EventSchemas = Record<never, never>,
  const R extends PresenceSchema = false,
>(template: P, options: TopicOptions<E, R> = {}): Topic<P, E, R> {
  const parsed: Template = parseTemplate(template, ":", validateValue);
  const literal = template.replaceAll(/\{[^}]+\}/g, " ");
  const name = slug(options.name ?? literal) || "topic";
  const isPrivate = options.private ?? true;
  const schemas: EventSchemas = options.events ?? {};
  const hasPresence =
    options.presence !== undefined && options.presence !== false;
  const presenceSchema =
    typeof options.presence === "object" ? options.presence : undefined;

  const segment = (param: string, kind: string): number => {
    const index = parsed.segmentOf(param);
    if (index === undefined) {
      throw new TypeError(
        `defineTopic: the ${kind} check needs {${param}} as a whole segment in "${template}"`,
      );
    }
    return index;
  };
  const checks: string[] = [];
  const permdock = options.permdock;
  const tenantParam =
    options.tenant === false
      ? undefined
      : (options.tenant?.param ?? "organizationId");
  const permdockChecks = ((): { receive: string; send: string } | undefined => {
    if (!permdock) return undefined;
    const where = `defineTopic(${template})`;
    const id =
      permdock.scope === "global"
        ? undefined
        : `split_part((select realtime.topic()), ':', ${String(permdock.segment ?? segment(tenantParam ?? "organizationId", "PermDock"))})`;
    const receive = permdockCheck(
      where,
      permdock,
      permdock.receive,
      id,
      options.catalog,
    );
    return {
      receive,
      send:
        permdock.send === undefined
          ? receive
          : permdockCheck(where, permdock, permdock.send, id, options.catalog),
    };
  })();
  if (
    !permdock &&
    tenantParam &&
    (options.tenant || parsed.params.includes(tenantParam))
  ) {
    const tenant = options.tenant === false ? {} : (options.tenant ?? {});
    const expression =
      tenant.sql ?? claimSql(tenant.claim ?? tenantClaimPaths());
    checks.push(
      `split_part((select realtime.topic()), ':', ${String(segment(tenantParam, "tenant"))}) = (${expression})`,
    );
  }
  const ownerParam =
    options.owner === false ? undefined : (options.owner?.param ?? "userId");
  if (ownerParam && (options.owner || parsed.params.includes(ownerParam))) {
    checks.push(
      `split_part((select realtime.topic()), ':', ${String(segment(ownerParam, "owner"))}) = (select auth.uid())::text`,
    );
  }

  const topicOf = (values: TemplateValues<P>): string => parsed.build(values);

  // SAFETY: the template parser returns the parameter names written in P.
  return {
    template,
    name,
    params: parsed.params as TemplateParams<P>[],
    private: isPrivate,
    presence: hasPresence,
    topic: topicOf,
    match: (topic) => parsed.match(topic) as TemplateValues<P> | null,
    sql() {
      const extensions = hasPresence
        ? "('broadcast', 'presence')"
        : "('broadcast')";
      const condition = (extra: string | undefined) =>
        [
          `(select realtime.topic()) ~ ${sqlString(parsed.sqlPattern)}`,
          `realtime.messages.extension in ${extensions}`,
          ...checks,
          ...(extra === undefined ? [] : [extra]),
        ].join("\n    and ");
      const lines = [`-- better-supabase: topic ${template}`];
      const policies: [string, string, "using" | "with check", string][] = [
        ["receive", "select", "using", condition(permdockChecks?.receive)],
      ];
      if (options.send || hasPresence || permdock?.send !== undefined)
        policies.push([
          "send",
          "insert",
          "with check",
          condition(permdockChecks?.send),
        ]);
      for (const [suffix, command, clause, check] of policies) {
        const policy = sqlIdent(`bs_topic_${name}_${suffix}`);
        lines.push(
          `drop policy if exists ${policy} on realtime.messages;`,
          `create policy ${policy} on realtime.messages for ${command} to authenticated\n  ${clause} (\n    ${check}\n  );`,
        );
      }
      return `${lines.join("\n")}\n`;
    },
    triggerSql(betterSupabase, table, trigger) {
      const meta: TableMeta | undefined = betterSupabase.meta.tables[table];
      if (!meta) throw new TypeError(`defineTopic: unknown table "${table}"`);
      // SAFETY: trigger values name table columns or lookups by topic
      // parameter, and templates hold strings.
      const values = trigger.values as Readonly<
        Record<string, AnyTriggerValue | undefined>
      >;
      const tables = betterSupabase.meta.tables;
      const parts = template
        .split(/(\{[^}]+\})/)
        .filter(Boolean)
        .map((part) => {
          const param = /^\{(.+)\}$/.exec(part)?.[1];
          if (param === undefined) return sqlString(part);
          const value = values[param];
          if (value === undefined)
            throw new TypeError(
              `defineTopic: no column for {${param}} on "${table}"`,
            );
          return `${triggerValueSql(tables, meta, value, `{${param}}`)}::text`;
        });
      const schema = trigger.functionSchema ?? "better_supabase";
      const fn = `${sqlIdent(schema)}.${sqlIdent(`bs_broadcast_${name}_${slug(meta.name)}`)}`;
      const triggerName = sqlIdent(`bs_broadcast_${name}`);
      const target = `${sqlIdent(meta.schema)}.${sqlIdent(meta.name)}`;
      const events = (trigger.events ?? ["insert", "update", "delete"]).join(
        " or ",
      );
      const event = eventSql(trigger.event);
      // SAFETY: payload values are columns, lookups or `{ sql }`.
      const payload = trigger.payload as
        | Readonly<Record<string, AnyTriggerValue | { readonly sql: string }>>
        | undefined;
      const send = payload
        ? [
            "  perform realtime.send(",
            `    jsonb_build_object(${Object.entries(payload)
              .map(
                ([key, value]) =>
                  `${sqlString(key)}, ${
                    typeof value === "object" && "sql" in value
                      ? `(${value.sql.replaceAll("{row}", "rec")})`
                      : triggerValueSql(tables, meta, value, `payload.${key}`)
                  }`,
              )
              .join(", ")}),`,
            `    ${event}, topic, ${String(isPrivate)}`,
            "  );",
          ]
        : [
            "  perform realtime.broadcast_changes(",
            `    topic, ${event}, tg_op, tg_table_name, tg_table_schema, new, old`,
            "  );",
          ];
      return [
        `-- better-supabase: broadcast ${meta.name} changes to ${template}`,
        `create schema if not exists ${sqlIdent(schema)};`,
        `create or replace function ${fn}()`,
        "returns trigger",
        "language plpgsql",
        "security definer",
        "set search_path = ''",
        "as $$",
        "declare",
        "  rec record;",
        "  topic text;",
        "begin",
        "  if tg_op = 'DELETE' then rec := old; else rec := new; end if;",
        `  topic := ${parts.join(" || ")};`,
        "  if topic is null then",
        "    return null;",
        "  end if;",
        ...send,
        "  return null;",
        "end;",
        "$$;",
        `revoke execute on function ${fn}() from public, anon, authenticated;`,
        "",
        `drop trigger if exists ${triggerName} on ${target};`,
        `create trigger ${triggerName} after ${events} on ${target}`,
        `  for each row execute function ${fn}();`,
        "",
      ].join("\n");
    },
    subscribe(client, values, handlers, given) {
      const topic = topicOf(values);
      // SAFETY: handlers maps event names to callbacks; the per-event payload
      // types stop at this boundary.
      const table = handlers as Readonly<
        Record<
          string,
          ((payload: unknown, message: TopicMessage) => void) | undefined
        >
      >;
      // SAFETY: `onPresence` is only typed in on presence topics, and the
      // member states it receives passed the presence schema.
      const subscribeOptions = (given ?? {}) as SubscribeOptions &
        PresenceOptions<unknown>;
      let members: readonly PresenceMember<unknown>[] = [];
      let syncs = 0;
      const sync = async (state: RealtimePresenceState): Promise<void> => {
        const run = ++syncs;
        const checked = await Promise.all(
          Object.entries(state).flatMap(([key, metas]) =>
            metas.map(async ({ presence_ref: _ref, ...meta }) => ({
              key,
              meta,
              checked: await validate(presenceSchema, meta),
            })),
          ),
        );
        // A later sync finished validating first.
        if (run !== syncs) return;
        const valid: PresenceMember<unknown>[] = [];
        for (const each of checked) {
          if (each.checked.ok) {
            valid.push({ key: each.key, state: each.checked.value });
          } else {
            subscribeOptions.onInvalid?.(
              { event: "presence", payload: each.meta, topic },
              each.checked.issues,
            );
          }
        }
        members = valid;
        subscribeOptions.onPresence?.(valid);
      };
      const subscriber: Subscriber = {
        onStatus: subscribeOptions.onStatus,
        receive: (message) => {
          const handler = table[message.event] ?? table["*"];
          if (!handler) return;
          void validate(schemas[message.event], message.payload).then(
            (checked) => {
              if (checked.ok) handler(checked.value, message);
              else subscribeOptions.onInvalid?.(message, checked.issues);
            },
          );
        },
        ...(hasPresence ? { sync: (state) => void sync(state) } : {}),
      };
      const { shared, leave } = joinTopic(
        client,
        topic,
        isPrivate,
        subscribeOptions.self ?? false,
        hasPresence,
        subscriber,
      );
      let closed = false;
      const unsubscribe = async () => {
        if (closed) return;
        closed = true;
        await leave();
      };
      const presenceCall = (
        action: "track" | "untrack",
        run: () => Promise<string>,
      ): AsyncResult<void> =>
        AsyncResult.from(async () => {
          if (closed)
            return err(
              dbError(
                "invalid_request",
                `Presence ${action} after unsubscribe on ${topic}`,
              ),
            );
          try {
            await shared.ready;
          } catch (cause) {
            return err(
              dbError(
                "network",
                `Presence ${action} on ${topic}: the join failed`,
                {
                  details:
                    cause instanceof Error ? cause.message : String(cause),
                },
              ),
            );
          }
          const answer = await run();
          return answer === "ok"
            ? ok(undefined)
            : err(
                dbError("network", `Presence ${action} ${answer} on ${topic}`),
              );
        });
      const subscription: Subscription = {
        topic,
        channel: shared.channel,
        ready: shared.ready,
        unsubscribe,
        [Symbol.dispose]: () => void unsubscribe(),
        [Symbol.asyncDispose]: unsubscribe,
      };
      const result = hasPresence
        ? {
            ...subscription,
            track: (state: unknown) =>
              AsyncResult.from(async () => {
                const checked = await validate(presenceSchema, state);
                if (!checked.ok)
                  return err(
                    dbError(
                      "validation",
                      `Invalid presence state for ${topic}`,
                      {
                        issues: checked.issues,
                      },
                    ),
                  );
                return presenceCall("track", async () => {
                  shared.tracker = subscriber;
                  return shared.channel.track(
                    // SAFETY: a presence schema's output is the tracked object.
                    checked.value as Record<string, unknown>,
                  );
                });
              }),
            untrack: () =>
              presenceCall("untrack", async () => {
                if (shared.tracker === subscriber) shared.tracker = undefined;
                return shared.channel.untrack();
              }),
            members: () => members,
          }
        : subscription;
      // SAFETY: the presence methods are added exactly when R allows presence.
      return result as TopicSubscription<R>;
    },
    send(client, values, event, payload) {
      return AsyncResult.from(async () => {
        const topic = topicOf(values);
        const checked = await validate(schemas[event], payload);
        if (!checked.ok)
          return err(
            dbError("validation", `Invalid payload for ${event}`, {
              issues: checked.issues,
            }),
          );
        // client.channel() returns the open channel for a subscribed topic;
        // removing that one would end the caller's subscription.
        const open = client
          .getChannels()
          .some((existing) => existing.topic === `realtime:${topic}`);
        if (isPrivate && !open) await refreshRealtimeAuth(client);
        const channel = client.channel(topic, {
          config: { private: isPrivate },
        });
        try {
          const response = await channel.httpSend(event, checked.value);
          return response.success
            ? ok(undefined)
            : err(sendError(response.status, response.error));
        } finally {
          if (!open) await client.removeChannel(channel);
        }
      });
    },
  };
}

/**
 * Reads a `realtime.broadcast_changes` message as an app-cased row change.
 * Returns `null` for messages about other tables.
 */
export function rowChange<
  M extends AnyModels,
  D,
  F extends AnyFunctions,
  X,
  T extends TableKey<M>,
>(
  betterSupabase: BetterSupabase<M, D, F, X>,
  table: T,
  message: TopicMessage,
): RowChange<Row<M, T>> | null {
  const meta: TableMeta | undefined = betterSupabase.meta.tables[table];
  // SAFETY: the broadcast trigger sends this payload shape, and every field is checked below.
  const payload = message.payload as {
    table?: string;
    schema?: string;
    operation?: string;
    record?: Record<string, unknown> | null;
    old_record?: Record<string, unknown> | null;
  } | null;
  if (
    !meta ||
    !payload ||
    payload.table !== meta.name ||
    (payload.schema && payload.schema !== meta.schema)
  )
    return null;
  const operation = payload.operation ?? message.event;
  if (
    operation !== "INSERT" &&
    operation !== "UPDATE" &&
    operation !== "DELETE"
  )
    return null;
  return {
    operation,
    table,
    record: payload.record ? toApp(meta, payload.record) : null,
    oldRecord: payload.old_record ? toApp(meta, payload.old_record) : null,
  };
}
