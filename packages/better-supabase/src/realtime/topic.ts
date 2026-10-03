import type { StandardSchemaV1 } from "@standard-schema/spec";

import {
  type RealtimeChannel,
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

export type EventSchemas = Readonly<Record<string, StandardSchemaV1>>;

export interface TopicOptions<E extends EventSchemas> {
  /** Name used for generated policies and functions. Defaults to the template's literal parts. */
  readonly name?: string;
  /** Payload schemas per event. Incoming and outgoing payloads are validated. */
  readonly events?: E;
  /** Private channels are authorized by `realtime.messages` policies. Defaults to `true`. */
  readonly private?: boolean;
  /**
   * Tenant check for the generated policy. Defaults to `{orgId}` against
   * `tenant_id` / `app_metadata.tenant_id` when the template has `{orgId}`.
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
   * naming a permission with `rowConditions: true` throws.
   */
  readonly catalog?: PermdockCatalog;
  /** Let clients broadcast on the topic, not only receive. Defaults to `false`. */
  readonly send?: boolean;
  /** Also authorize presence. Defaults to `false`. */
  readonly presence?: boolean;
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

export type RealtimeClient = Pick<
  SupabaseClient,
  "channel" | "removeChannel" | "realtime"
>;

export interface TriggerOptions<
  M extends AnyModels,
  T extends keyof M,
  P extends string,
> {
  /** Column that fills each placeholder. */
  readonly values: {
    readonly [K in TemplateParams<P>]: Extract<keyof Row<M, T>, string>;
  };
  /** Defaults to all three. */
  readonly events?: readonly ("insert" | "update" | "delete")[];
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

export interface Topic<P extends string, E extends EventSchemas> {
  readonly template: P;
  readonly name: string;
  readonly params: readonly TemplateParams<P>[];
  readonly private: boolean;
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
    options?: SubscribeOptions,
  ): Subscription;
  /** Sends over HTTP, without joining the channel. */
  send<K extends TopicEvent<E>>(
    client: RealtimeClient,
    values: TemplateValues<P>,
    event: K,
    payload: TopicPayload<E, K>,
  ): AsyncResult<void>;
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

/**
 * A typed Realtime broadcast topic: names from a template, RLS policies for
 * private channels, row-change triggers, and disposable subscriptions.
 *
 * ```ts
 * export const notifications = defineTopic('org:{orgId}:notifications:{userId}', {
 *   events: { created: v.object({ id: v.string(), title: v.string() }) },
 * });
 * using sub = notifications.subscribe(supabase, { orgId, userId }, { created: (n) => toast(n.title) });
 * ```
 */
export function defineTopic<
  const P extends string,
  const E extends EventSchemas = Record<never, never>,
>(template: P, options: TopicOptions<E> = {}): Topic<P, E> {
  const parsed: Template = parseTemplate(template, ":", validateValue);
  const literal = template.replaceAll(/\{[^}]+\}/g, " ");
  const name = slug(options.name ?? literal) || "topic";
  const isPrivate = options.private ?? true;
  const schemas: EventSchemas = options.events ?? {};

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
    options.tenant === false ? undefined : (options.tenant?.param ?? "orgId");
  const permdockChecks = ((): { receive: string; send: string } | undefined => {
    if (!permdock) return undefined;
    const where = `defineTopic(${template})`;
    const id =
      permdock.scope === "global"
        ? undefined
        : `split_part((select realtime.topic()), ':', ${String(permdock.segment ?? segment(tenantParam ?? "orgId", "PermDock"))})`;
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
    topic: topicOf,
    match: (topic) => parsed.match(topic) as TemplateValues<P> | null,
    sql() {
      const extensions = options.presence
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
      if (options.send || options.presence || permdock?.send !== undefined)
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
      // SAFETY: trigger values name table columns by topic parameter, and
      // templates hold strings.
      const values = trigger.values as Readonly<Record<string, string>>;
      const parts = template
        .split(/(\{[^}]+\})/)
        .filter(Boolean)
        .map((part) => {
          const param = /^\{(.+)\}$/.exec(part)?.[1];
          if (param === undefined) return sqlString(part);
          const column = values[param];
          const db =
            column === undefined ? undefined : meta.columns[column]?.db;
          if (!db)
            throw new TypeError(
              `defineTopic: no column for {${param}} on "${table}"`,
            );
          return `rec.${sqlIdent(db)}::text`;
        });
      const schema = trigger.functionSchema ?? "better_supabase";
      const fn = `${sqlIdent(schema)}.${sqlIdent(`bs_broadcast_${name}_${slug(meta.name)}`)}`;
      const triggerName = sqlIdent(`bs_broadcast_${name}`);
      const target = `${sqlIdent(meta.schema)}.${sqlIdent(meta.name)}`;
      const events = (trigger.events ?? ["insert", "update", "delete"]).join(
        " or ",
      );
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
        "begin",
        "  if tg_op = 'DELETE' then rec := old; else rec := new; end if;",
        "  perform realtime.broadcast_changes(",
        `    ${parts.join(" || ")},`,
        "    tg_op, tg_op, tg_table_name, tg_table_schema, new, old",
        "  );",
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
    subscribe(client, values, handlers, subscribeOptions = {}) {
      const topic = topicOf(values);
      const channel = client.channel(topic, {
        config: {
          private: isPrivate,
          broadcast: { self: subscribeOptions.self ?? false },
        },
      });
      // SAFETY: handlers maps event names to callbacks; the per-event payload
      // types stop at this boundary.
      const table = handlers as Readonly<
        Record<
          string,
          ((payload: unknown, message: TopicMessage) => void) | undefined
        >
      >;
      channel.on("broadcast", { event: "*" }, (raw) => {
        const message: TopicMessage = {
          event: raw.event,
          payload: raw["payload"],
          topic,
        };
        const handler = table[message.event] ?? table["*"];
        if (!handler) return;
        void validate(schemas[message.event], message.payload).then(
          (checked) => {
            if (checked.ok) handler(checked.value, message);
            else subscribeOptions.onInvalid?.(message, checked.issues);
          },
        );
      });
      let closed = false;
      subscribeOptions.onStatus?.("joining");
      const ready = (async () => {
        if (isPrivate) await client.realtime.setAuth();
        // oxlint-disable-next-line typescript/no-unnecessary-condition -- `close()` can run while `setAuth` is awaited.
        if (closed) return;
        await new Promise<void>((resolve, reject) => {
          channel.subscribe((status, error) => {
            switch (status) {
              case REALTIME_SUBSCRIBE_STATES.SUBSCRIBED:
                subscribeOptions.onStatus?.("subscribed");
                resolve();
                return;
              case REALTIME_SUBSCRIBE_STATES.CLOSED:
                subscribeOptions.onStatus?.("closed");
                resolve();
                return;
              case REALTIME_SUBSCRIBE_STATES.CHANNEL_ERROR:
              case REALTIME_SUBSCRIBE_STATES.TIMED_OUT: {
                const failure =
                  error ??
                  new Error(`Realtime ${status.toLowerCase()} on ${topic}`);
                subscribeOptions.onStatus?.("error", failure);
                reject(failure);
                return;
              }
              default: {
                const unknown: never = status;
                reject(new Error(`Unknown realtime status ${String(unknown)}`));
              }
            }
          });
        });
      })();
      ready.catch(() => undefined);
      const unsubscribe = async () => {
        if (closed) return;
        closed = true;
        await client.removeChannel(channel);
      };
      return {
        topic,
        channel,
        ready,
        unsubscribe,
        [Symbol.dispose]: () => void unsubscribe(),
        [Symbol.asyncDispose]: unsubscribe,
      };
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
        if (isPrivate) await client.realtime.setAuth();
        const channel = client.channel(topic, {
          config: { private: isPrivate },
        });
        try {
          const response = await channel.httpSend(event, checked.value);
          return response.success
            ? ok(undefined)
            : err(sendError(response.status, response.error));
        } finally {
          await client.removeChannel(channel);
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
