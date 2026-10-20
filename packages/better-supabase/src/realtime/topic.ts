import type { StandardSchemaV1 } from "@standard-schema/spec";
import type {
  RealtimeChannel,
  RealtimePresenceState,
  SupabaseClient,
} from "@supabase/supabase-js";

import type { AuthorizationFunctions } from "../config/authorization.ts";
import type {
  Subscriber as FanOutSubscriber,
  SubscriberPolicy,
} from "../core/contracts/authorization-hooks.ts";
import type { BetterSupabase } from "../core/define.ts";
import type {
  AnyFunctions,
  AccessTopicPolicy,
  AnyModels,
  Row,
  TableKey,
  TableMeta,
} from "../schema/types.ts";
import type { FanOutResult, TopicFanOutOptions } from "./fan-out.ts";

import { accessCheck, resolveProviderSql } from "../core/access-sql.ts";
import { tenantClaimPaths } from "../core/claims.ts";
import { dbError, type DbError, type ValidationIssue } from "../core/errors.ts";
import { type RealtimeStatus, topicStatus } from "../core/realtime-status.ts";
import { AsyncResult, err, ok } from "../core/result.ts";
import {
  parseTemplate,
  slug,
  sqlIdent,
  claimSql,
  sqlString,
  type Template,
  type TemplateParams,
  type TemplateValues,
} from "../core/template.ts";
import { toApp } from "../schema/casing.ts";
import { refreshRealtimeAuth } from "./auth.ts";
import { joinTopic, type Subscriber } from "./channels.ts";
import { fanOutTopic } from "./fan-out.ts";
import {
  changedSql,
  eventSql,
  splitTable,
  topicPermissionSql,
  TriggerLookups,
  triggerValueSql,
  type AnyTriggerValue,
} from "./topic-sql.ts";
import {
  CATALOG_ID_SQL,
  idSql,
  triggerFunctionSql,
  type TriggerPayloadSql,
  type TriggerTopicSql,
} from "./topic-trigger.ts";

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
   * Authorize with the SQL modules' access contract instead of the tenant
   * claim: `tenant_ids_with(receive)` on the tenant segment (or
   * `is_platform` for `scope: 'platform'`), or the `sql` templates it is
   * given, and `send` for broadcasting.
   *
   * The checks decide by role and scope only: for a permission with row
   * conditions (e.g. `authorId = principal.id`) every member of the scope
   * could join. `better-supabase doctor` (BS214) refuses keys the
   * authorization provider doesn't mark `sqlComplete: true`.
   */
  readonly access?: AccessTopicPolicy;
  /**
   * A permission on the instance the topic is about, such as
   * `'posts.read'` on `org:{organizationId}:posts:{postId}`: every receiver
   * and sender must hold it on that instance. With an authorization
   * provider, `sql({ functions })` checks it with the provider's `permitted`
   * template; without one, with the access contract's tenant check.
   */
  readonly permission?: string | TopicPermission;
  /**
   * Narrows `fanOut` to the subscribers that may read the event. Defaults
   * to `server.authorization.delivery.subscribers` when `fanOut` gets the
   * server.
   */
  readonly subscribers?: SubscriberPolicy;
  /** Let clients broadcast on the topic, not only receive. Defaults to `false`. */
  readonly send?: boolean;
  /**
   * Presence: authorizes it in the policies and adds `track` and
   * `onPresence` to subscriptions. Pass a schema to validate the states
   * this client tracks and the ones it receives. Defaults to `false`.
   */
  readonly presence?: R;
}

/** A topic's instance permission. */
export interface TopicPermission {
  readonly key: string;
  /** The placeholder holding the instance id, as a whole segment. Defaults to the last one. */
  readonly param?: string;
  /** `{resource}` in the `permitted` template. Defaults to the key up to its first `.`. */
  readonly resource?: string;
  /** `{scope}` in the `permitted` template. Defaults to `tenant`. */
  readonly scope?: string;
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

/**
 * What a broadcast trigger sends. `"keys"` (the default) sends
 * `{ operation, schema, table, id, values }`: the primary key and the
 * topic's placeholder values, so clients refetch the row through RLS.
 * `"row"` sends the whole row as `record` and `old_record`, which bypasses
 * column grants: every receiver of the topic sees every column.
 */
export type TriggerPayloadMode = "keys" | "row";

/** A topic the same row change also goes to (`topics` on `trigger()`). */
export interface TriggerTopic<V> {
  readonly topic: {
    readonly template: string;
    readonly params: readonly string[];
    readonly private: boolean;
  };
  /** What fills each of its placeholders, as in `values`. */
  readonly values?: Readonly<Record<string, V>>;
}

interface TriggerCommonOptions {
  /** Defaults to all three. */
  readonly events?: readonly TriggerOperation[];
  /**
   * The broadcast event name, or one per operation. Defaults to the
   * operation (`INSERT`, `UPDATE`, `DELETE`).
   */
  readonly event?: string | { readonly [O in TriggerOperation]?: string };
  /**
   * Schema for a generated function. Defaults to `better_supabase`, which
   * the Data API does not expose.
   */
  readonly functionSchema?: string;
}

/** `topic.trigger()` with the app's `betterSupabase`: typed columns and lookups. */
export interface TriggerOptions<
  M extends AnyModels,
  T extends keyof M,
  P extends string,
> extends TriggerCommonOptions {
  /**
   * What fills each placeholder: a column of the changed row, or a lookup
   * (`{ from, via, select }`) for a value on a parent row. A row whose
   * topic comes out null is not sent to that topic.
   */
  readonly values: {
    readonly [K in TemplateParams<P>]: TriggerValue<M, T>;
  };
  /**
   * `"keys"` (default), `"row"` (bypasses column grants), or the payload
   * itself: each key is a column, a lookup, or `{ sql }`, an expression on
   * the row `{row}` (`tg_op` is the operation).
   */
  readonly payload?:
    | TriggerPayloadMode
    | Readonly<Record<string, TriggerValue<M, T> | { readonly sql: string }>>;
  /** More topics the row change goes to, each with its own values. */
  readonly topics?: readonly TriggerTopic<TriggerValue<M, T>>[];
  /**
   * Send an UPDATE only when one of these columns changed. Inserts and
   * deletes always send.
   */
  readonly when?: {
    readonly changed: readonly Extract<keyof Row<M, T>, string>[];
  };
}

export interface TopicTriggerLookup {
  readonly from: string;
  readonly via: string | TopicTriggerLookup;
  readonly select: string;
  readonly key?: string;
}

export type TopicTriggerValue = string | TopicTriggerLookup;

/** `topic.trigger()` without `betterSupabase`: database names. */
export interface TopicTriggerOptions<
  P extends string,
> extends TriggerCommonOptions {
  /**
   * The column or lookup that fills each placeholder. Defaults to the
   * placeholder in snake_case (`{organizationId}` reads `organization_id`).
   */
  readonly values?: { readonly [K in TemplateParams<P>]?: TopicTriggerValue };
  /**
   * `"keys"` (default), `"row"` (bypasses column grants), or the payload
   * itself: each key is a column, a lookup, or `{ sql }`, an expression on
   * the row `{row}` (`tg_op` is the operation).
   */
  readonly payload?:
    | TriggerPayloadMode
    | Readonly<Record<string, TopicTriggerValue | { readonly sql: string }>>;
  /** More topics the row change goes to, each with its own values. */
  readonly topics?: readonly TriggerTopic<TopicTriggerValue>[];
  /**
   * Send an UPDATE only when one of these columns (database names)
   * changed. Inserts and deletes always send.
   */
  readonly when?: { readonly changed: readonly string[] };
}

/** A row change sent with `payload: "row"`. */
export interface RowChange<R> {
  readonly operation: "INSERT" | "UPDATE" | "DELETE";
  readonly table: string;
  readonly record: R | null;
  readonly oldRecord: Partial<R> | null;
}

/** A row change sent with the default `payload: "keys"`: refetch the row through RLS. */
export interface RowKeys {
  readonly operation: "INSERT" | "UPDATE" | "DELETE";
  readonly schema: string;
  readonly table: string;
  /** The primary key value, or an object keyed by column for a composite key. */
  readonly id: unknown;
  /** The topic's placeholder values. */
  readonly values: Readonly<Record<string, string>>;
}

/** Options for `topic.sql()`. */
export interface TopicSqlOptions {
  /**
   * The provider's templates, for an access policy with `sql: "provider"`
   * and for `permission` (its `permitted` template).
   */
  readonly functions?: AuthorizationFunctions;
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
  /** The schema tracked presence states are validated against, if any. */
  readonly presenceSchema: StandardSchemaV1 | undefined;
  /** Payload schemas per event, as given to `defineTopic`. */
  readonly events: E;
  /** Whether clients may broadcast on the topic (the `send` option). */
  readonly clientSend: boolean;
  /** The instance permission's key, when the topic has one. */
  readonly permission: string | undefined;
  /**
   * Supabase's status for what the topic relies on: `beta` for a private
   * topic (Realtime Authorization is in public beta), `ga` otherwise.
   */
  readonly status: RealtimeStatus;
  topic(values: TemplateValues<P>): string;
  match(topic: string): TemplateValues<P> | null;
  /**
   * `realtime.messages` policies for this topic. Idempotent. An access
   * policy with `sql: "provider"` needs the provider's templates in
   * `options.functions`; `better-supabase sql sync` passes them.
   */
  sql(options?: TopicSqlOptions): string;
  /**
   * A trigger that broadcasts row changes on `table` to this topic, and to
   * each of `topics`. A topic whose values come out null is skipped, and
   * a value topics don't allow skips that topic with a warning instead of
   * failing the write.
   *
   * With `betterSupabase`, `table`, columns and lookup tables are app keys.
   * Without it they are database names, and a single topic whose values
   * are columns, with a mode payload and one event name, calls
   * `better_supabase.broadcast_topic()` from the `realtime-tables` module.
   * Every other trigger creates a function for the topic.
   *
   * The payload carries keys only unless `payload` says otherwise:
   * `payload: "row"` sends whole rows and bypasses column grants.
   */
  trigger<
    M extends AnyModels,
    D,
    F extends AnyFunctions,
    X,
    T extends TableKey<M>,
  >(
    table: T,
    options: TriggerOptions<M, T, P> & {
      readonly betterSupabase: BetterSupabase<M, D, F, X>;
    },
  ): string;
  trigger(table: string, options?: TopicTriggerOptions<P>): string;
  /**
   * @deprecated Use `trigger(table, { ...options, betterSupabase })`. The
   * payload default is keys only; pass `payload: "row"` for whole rows.
   */
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
  /**
   * Sends one event to each subscriber's own topic (such as
   * `notifications:{userId}`) after the subscriber policy narrows them.
   * A policy that throws sends to no one and returns a `forbidden` error.
   */
  fanOut<S extends FanOutSubscriber, K extends TopicEvent<E>>(
    client: RealtimeClient,
    options: TopicFanOutOptions<P, E, K, S>,
  ): AsyncResult<FanOutResult<S>>;
}

interface AnyTriggerOptions {
  readonly betterSupabase?: {
    readonly meta: {
      readonly tables: Readonly<Record<string, TableMeta | undefined>>;
    };
  };
  readonly values?: Readonly<Record<string, AnyTriggerValue | undefined>>;
  readonly events?: readonly TriggerOperation[];
  readonly event?: string | Readonly<Record<string, string | undefined>>;
  readonly payload?:
    | TriggerPayloadMode
    | Readonly<Record<string, AnyTriggerValue | { readonly sql: string }>>;
  readonly topics?: readonly TriggerTopic<AnyTriggerValue>[];
  readonly functionSchema?: string;
  readonly when?: { readonly changed: readonly string[] };
}

const columnsOnly = (
  values: Readonly<Record<string, AnyTriggerValue | undefined>> | undefined,
): Readonly<Record<string, string>> | undefined => {
  const columns: Record<string, string> = {};

  for (const [param, value] of Object.entries(values ?? {})) {
    if (typeof value === "object") {
      return undefined;
    }

    if (value !== undefined) {
      columns[param] = value;
    }
  }

  return columns;
};

const VALUE = /^[\w.@+=-]+$/;

const snakeCase = (name: string): string =>
  name.replaceAll(/([a-z0-9])([A-Z])/g, "$1_$2").toLowerCase();

function validateValue(_name: string, value: string): string | undefined {
  return VALUE.test(value)
    ? undefined
    : "contains characters topics do not allow";
}

async function validate(
  schema: StandardSchemaV1 | undefined,
  value: unknown,
): Promise<
  | { ok: true; value: unknown }
  | { ok: false; issues: readonly ValidationIssue[] }
> {
  if (!schema) {
    return { ok: true, value };
  }

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
  if (status === 401) {
    return dbError("unauthorized", message);
  }

  if (status === 403) {
    return dbError("forbidden", message);
  }

  if (status === 429 || status >= 500 || status === 0) {
    return dbError("network", message, status ? { status } : {});
  }

  return dbError("invalid_request", message, { status });
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
  const access = options.access;

  const tenantParam =
    options.tenant === false
      ? undefined
      : (options.tenant?.param ?? "organizationId");

  const accessChecksFor = (
    functions?: AuthorizationFunctions,
  ): { receive: string; send: string } | undefined => {
    if (!access) {
      return undefined;
    }

    const where = `defineTopic(${template})`;
    const target = resolveProviderSql(where, access, functions);

    const id =
      access.scope === "platform"
        ? undefined
        : `split_part((select realtime.topic()), ':', ${String(access.segment ?? segment(tenantParam ?? "organizationId", "access"))})`;

    const receive = accessCheck(where, target, access.receive, id);

    return {
      receive,
      send:
        access.send === undefined
          ? receive
          : accessCheck(where, target, access.send, id),
    };
  };

  const fixedChecks =
    access?.sql === "provider" ? undefined : accessChecksFor();

  if (
    !access &&
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

  const permission =
    typeof options.permission === "string"
      ? { key: options.permission }
      : options.permission;

  const permissionTarget = (() => {
    if (permission === undefined) {
      return;
    }

    const key = permission.key;

    if (key === "") {
      throw new TypeError(`defineTopic(${template}): the permission is empty`);
    }

    const param = permission.param ?? parsed.params.at(-1);

    if (param === undefined) {
      throw new TypeError(
        `defineTopic(${template}): permission "${key}" needs a placeholder for the instance id`,
      );
    }

    return {
      key,
      idSegment: segment(param, "permission"),
      tenantSegment:
        tenantParam === undefined ? undefined : parsed.segmentOf(tenantParam),
      resource: permission.resource ?? key.split(".")[0] ?? key,
      scope: permission.scope ?? "tenant",
    };
  })();

  const topicOf = (values: TemplateValues<P>): string => parsed.build(values);

  const triggerStatement = (
    table: string,
    trigger: AnyTriggerOptions,
  ): string => {
    const where = `defineTopic(${template}).trigger`;
    const tables = trigger.betterSupabase?.meta.tables;
    const meta = tables?.[table];

    if (tables && !meta) {
      throw new TypeError(`defineTopic: unknown table "${table}"`);
    }

    const [schema, relation] = meta
      ? [meta.schema, meta.name]
      : splitTable(table);

    const target = `${sqlIdent(schema)}.${sqlIdent(relation)}`;
    const triggerName = `bs_broadcast_${name}`;
    const extra = trigger.topics ?? [];
    const { payload } = trigger;

    const operations = trigger.events ?? ["insert", "update", "delete"];
    const events = operations.join(" or ");

    if (trigger.when && !operations.includes("update")) {
      throw new TypeError(
        `${where}: when.changed filters updates, but events has no "update"`,
      );
    }

    // Postgres allows OLD and NEW in WHEN only on a trigger for UPDATE alone.
    const changed = trigger.when
      ? {
          sql: changedSql(meta, trigger.when.changed, where),
          when: operations.length === 1,
        }
      : undefined;

    const checkKeys = (
      params: readonly string[],
      given: Readonly<Record<string, unknown>> | undefined,
      topic: string,
    ): void => {
      for (const key of Object.keys(given ?? {})) {
        if (!params.includes(key)) {
          throw new TypeError(
            `${where}: "${key}" is not a placeholder of ${topic}`,
          );
        }
      }
    };

    checkKeys(parsed.params, trigger.values, template);

    const columns = columnsOnly(trigger.values);

    if (
      !meta &&
      columns !== undefined &&
      extra.length === 0 &&
      typeof trigger.event !== "object" &&
      (payload === undefined || typeof payload === "string") &&
      (changed === undefined || changed.when)
    ) {
      const sqlTemplate = template.replaceAll(
        /\{([^}]+)\}/g,
        (_, param: string) => {
          const column = columns[param] ?? snakeCase(param);

          if (/[{}=]/.test(column)) {
            throw new TypeError(
              `${where}: the column for {${param}} can't contain braces or =`,
            );
          }

          return column === param ? `{${param}}` : `{${param}=${column}}`;
        },
      );

      const args = [sqlString(sqlTemplate), sqlString(trigger.event ?? "")];

      if (!isPrivate || payload === "row") {
        args.push(sqlString(isPrivate ? "" : "false"));
      }

      if (payload === "row") {
        args.push(sqlString("row"));
      }

      return [
        `-- better-supabase: broadcast ${schema}.${relation} changes to ${template}`,
        `drop trigger if exists ${sqlIdent(triggerName)} on ${target};`,
        `create trigger ${sqlIdent(triggerName)} after ${events} on ${target}`,
        `  for each row${changed ? ` when (${changed.sql})` : ""} execute function better_supabase.broadcast_topic(${args.join(", ")});`,
        "",
      ].join("\n");
    }

    const lookups = new TriggerLookups();

    const valueSql = (value: AnyTriggerValue, label: string): string =>
      triggerValueSql(tables, meta, value, label, lookups);

    const topicValues = (
      params: readonly string[],
      given: Readonly<Record<string, AnyTriggerValue | undefined>> | undefined,
      topic: string,
    ): Record<string, string> =>
      Object.fromEntries(
        params.map((param) => {
          const value = given?.[param] ?? (meta ? undefined : snakeCase(param));

          if (value === undefined) {
            throw new TypeError(
              `defineTopic: no column for {${param}} of ${topic} on "${table}"`,
            );
          }

          return [param, valueSql(value, `{${param}}`)];
        }),
      );

    const topics: TriggerTopicSql[] = [
      {
        template,
        private: isPrivate,
        values: topicValues(parsed.params, trigger.values, template),
      },
      ...extra.map((each) => {
        checkKeys(each.topic.params, each.values, each.topic.template);

        return {
          template: each.topic.template,
          private: each.topic.private,
          values: topicValues(
            each.topic.params,
            each.values,
            each.topic.template,
          ),
        };
      }),
    ];

    const payloadSql: TriggerPayloadSql =
      payload === undefined || payload === "keys"
        ? {
            kind: "keys",
            id: meta
              ? idSql(
                  meta.primaryKey.map((key) => meta.columns[key]?.db ?? key),
                )
              : CATALOG_ID_SQL,
          }
        : payload === "row"
          ? { kind: "row" }
          : {
              kind: "custom",
              sql: `jsonb_build_object(${Object.entries(payload)
                .map(
                  ([key, value]) =>
                    `${sqlString(key)}, ${
                      typeof value === "object" && "sql" in value
                        ? `(${value.sql.replaceAll("{row}", "rec")})`
                        : valueSql(value, `payload.${key}`)
                    }`,
                )
                .join(", ")})`,
            };

    return triggerFunctionSql({
      subject: meta ? meta.name : `${schema}.${relation}`,
      functionSchema: trigger.functionSchema ?? "better_supabase",
      functionName: `bs_broadcast_${name}_${slug(schema)}_${slug(relation)}`,
      triggerName,
      target,
      events,
      event: eventSql(trigger.event),
      topics,
      payload: payloadSql,
      lookups: lookups.list,
      ...(changed ? { changed } : {}),
    });
  };

  // SAFETY: the template parser returns the parameter names written in P.
  const api: Topic<P, E, R> = {
    template,
    name,
    params: parsed.params as TemplateParams<P>[],
    private: isPrivate,
    presence: hasPresence,
    presenceSchema,
    // SAFETY: `schemas` is `options.events`, or `{}` when E is the empty default.
    events: schemas as E,
    clientSend: options.send ?? false,
    permission: permission?.key,
    status: topicStatus({ private: isPrivate }),
    topic: topicOf,
    match: (topic) => parsed.match(topic) as TemplateValues<P> | null,
    sql(sqlOptions) {
      const accessChecks =
        access?.sql === "provider"
          ? accessChecksFor(sqlOptions?.functions)
          : fixedChecks;

      const extensions = hasPresence
        ? "('broadcast', 'presence')"
        : "('broadcast')";

      const permissionCheck =
        permissionTarget === undefined
          ? undefined
          : topicPermissionSql({
              where: `defineTopic(${template})`,
              ...permissionTarget,
              permitted: sqlOptions?.functions?.permitted,
            });

      const condition = (extra: string | undefined) =>
        [
          `(select realtime.topic()) ~ ${sqlString(parsed.sqlPattern)}`,
          `realtime.messages.extension in ${extensions}`,
          ...checks,
          ...(extra === undefined ? [] : [extra]),
          ...(permissionCheck === undefined ? [] : [permissionCheck]),
        ].join("\n    and ");

      const lines = [`-- better-supabase: topic ${template}`];

      const policies: [string, string, "using" | "with check", string][] = [
        ["receive", "select", "using", condition(accessChecks?.receive)],
      ];

      if (options.send || hasPresence || access?.send !== undefined) {
        policies.push([
          "send",
          "insert",
          "with check",
          condition(accessChecks?.send),
        ]);
      }

      for (const [suffix, command, clause, check] of policies) {
        const policy = sqlIdent(`bs_topic_${name}_${suffix}`);
        lines.push(
          `drop policy if exists ${policy} on realtime.messages;`,
          `create policy ${policy} on realtime.messages for ${command} to authenticated\n  ${clause} (\n    ${check}\n  );`,
        );
      }

      return `${lines.join("\n")}\n`;
    },
    // oxlint-disable-next-line typescript/no-deprecated -- the deprecated alias itself (1 finding)
    triggerSql(betterSupabase, table, trigger) {
      return triggerStatement(table, { ...trigger, betterSupabase });
    },
    trigger(table: string, trigger?: AnyTriggerOptions) {
      return triggerStatement(table, trigger ?? {});
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
        if (run !== syncs) {
          return;
        }

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

          if (!handler) {
            return;
          }

          void validate(schemas[message.event], message.payload).then(
            (checked) => {
              if (checked.ok) {
                handler(checked.value, message);
              } else {
                subscribeOptions.onInvalid?.(message, checked.issues);
              }
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
        if (closed) {
          return;
        }

        closed = true;
        await leave();
      };

      const presenceCall = (
        action: "track" | "untrack",
        run: () => Promise<string>,
      ): AsyncResult<void> =>
        AsyncResult.from(async () => {
          if (closed) {
            return err(
              dbError(
                "invalid_request",
                `Presence ${action} after unsubscribe on ${topic}`,
              ),
            );
          }

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

                if (!checked.ok) {
                  return err(
                    dbError(
                      "validation",
                      `Invalid presence state for ${topic}`,
                      {
                        issues: checked.issues,
                      },
                    ),
                  );
                }

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
                if (shared.tracker === subscriber) {
                  shared.tracker = undefined;
                }

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

        if (!checked.ok) {
          return err(
            dbError("validation", `Invalid payload for ${event}`, {
              issues: checked.issues,
            }),
          );
        }

        // client.channel() returns the open channel for a subscribed topic;
        // removing that one would end the caller's subscription.
        const open = client
          .getChannels()
          .some((existing) => existing.topic === `realtime:${topic}`);

        if (isPrivate && !open) {
          await refreshRealtimeAuth(client);
        }

        const channel = client.channel(topic, {
          config: { private: isPrivate },
        });

        try {
          const response = await channel.httpSend(event, checked.value);

          return response.success
            ? ok(undefined)
            : err(sendError(response.status, response.error));
        } finally {
          if (!open) {
            await client.removeChannel(channel);
          }
        }
      });
    },
    fanOut(client, fanOutOptions) {
      return fanOutTopic(options.subscribers, fanOutOptions, (subscriber) =>
        api.send(
          client,
          fanOutOptions.values(subscriber),
          fanOutOptions.event,
          fanOutOptions.payload,
        ),
      );
    },
  };

  return api;
}

/**
 * Reads a broadcast trigger's default message (`payload: "keys"`). Returns
 * `null` for messages about other tables or with another shape.
 */
export function rowKeys<
  M extends AnyModels,
  D,
  F extends AnyFunctions,
  X,
  T extends TableKey<M>,
>(
  betterSupabase: BetterSupabase<M, D, F, X>,
  table: T,
  message: TopicMessage,
): RowKeys | null {
  const meta: TableMeta | undefined = betterSupabase.meta.tables[table];
  const payload = message.payload;

  if (!meta || typeof payload !== "object" || payload === null) {
    return null;
  }

  const fields: Readonly<Record<string, unknown>> = { ...payload };
  const { operation, schema, values } = fields;

  if (
    fields["table"] !== meta.name ||
    (schema !== undefined && schema !== meta.schema) ||
    (operation !== "INSERT" &&
      operation !== "UPDATE" &&
      operation !== "DELETE") ||
    !("id" in fields)
  ) {
    return null;
  }

  const strings: Record<string, string> = {};

  if (typeof values === "object" && values !== null) {
    for (const [key, value] of Object.entries(values)) {
      if (typeof value === "string") {
        strings[key] = value;
      }
    }
  }

  return {
    operation,
    schema: meta.schema,
    table: meta.name,
    id: fields["id"],
    values: strings,
  };
}

/**
 * Reads a `payload: "row"` message as an app-cased row change. Returns
 * `null` for messages about other tables.
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
  ) {
    return null;
  }

  const operation = payload.operation ?? message.event;

  if (
    operation !== "INSERT" &&
    operation !== "UPDATE" &&
    operation !== "DELETE"
  ) {
    return null;
  }

  return {
    operation,
    table,
    record: payload.record ? toApp(meta, payload.record) : null,
    oldRecord: payload.old_record ? toApp(meta, payload.old_record) : null,
  };
}
