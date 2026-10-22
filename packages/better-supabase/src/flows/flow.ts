import type { StandardSchemaV1 } from "@standard-schema/spec";

import type { DbError } from "../core/errors.ts";
import type { Result } from "../core/result.ts";

import { dbError } from "../core/errors.ts";
import { isRecord } from "../core/guards.ts";
import { AsyncResult, err, ok } from "../core/result.ts";

/** A record a flow reads from or creates: its subject type and id. */
export interface FlowRef {
  readonly type: string;
  readonly id: string;
}

/**
 * An event a flow starts from. An outbox event fits; a job keeps only these
 * fields, so they stay JSON.
 */
export interface FlowEvent<P = unknown> {
  readonly id: string;
  readonly type: string;
  readonly payload: P;
  readonly subject?: string | null;
  readonly tenant?: string | null;
  readonly actorId?: string | null;
}

/** The part of the relations block a flow uses; `blocks.relations` fits. */
export interface FlowRelations {
  link(
    source: FlowRef,
    target: FlowRef,
    input: { readonly kind: "created_from" },
  ): PromiseLike<Result<unknown>>;
  convertedInto(
    origin: FlowRef,
    intoType: string,
  ): PromiseLike<Result<string | undefined>>;
}

/** The clients every flow gets; a flow names the other blocks it needs. */
export interface FlowClients {
  readonly relations: FlowRelations;
}

/** What a flow's hooks receive for one event. */
export interface FlowContext<C, P = unknown> {
  readonly clients: C;
  /** The organization the event belongs to. */
  readonly tenant: string;
  readonly event: FlowEvent<P>;
  /** The record the event is about, from `source`. */
  readonly source: FlowRef;
}

export interface FlowSpec<C, P, S, T> {
  /** Unique among the flows of one `createFlows`; it keys the job dedupe. */
  readonly name: string;
  /** The event type, or types, that start the flow. */
  readonly on: string | readonly string[];
  /** The subject type the flow creates, such as `work_item`. */
  readonly target: string;
  /** The record the event is about; `undefined` skips the event. */
  readonly source: (event: FlowEvent<P>) => FlowRef | undefined;
  /** Reads what `map` needs, such as the source record. */
  readonly load?: (context: FlowContext<C, P>) => PromiseLike<Result<S>>;
  /**
   * The target block's input schema (`block.schemas.<entity>.input`): the
   * mapped value must pass it before `create` runs.
   */
  readonly input?: StandardSchemaV1<T>;
  /** Turns what `load` read into the target block's input. */
  readonly map: (loaded: S, context: FlowContext<C, P>) => T;
  /** Creates the target record and returns its id. */
  readonly create: (
    input: T,
    context: FlowContext<C, P>,
  ) => PromiseLike<Result<{ readonly id: string }>>;
  /**
   * The target block records the `created_from` link itself, as
   * `employees.fromApplication` does.
   */
  readonly linksItself?: boolean;
}

/** A flow from `defineFlow` (`apiVersion: 1`). */
export interface Flow<
  C extends FlowClients = FlowClients,
  P = unknown,
  S = unknown,
  T = unknown,
> extends FlowSpec<C, P, S, T> {
  readonly apiVersion: 1;
}

// oxlint-disable-next-line typescript/no-explicit-any -- the payload, loaded value and input vary per flow, and the hooks take them as parameters, so `unknown` would reject every typed flow
type Varies = any;

/** A flow over any payload, loaded value and input, for `createFlows`. */
export type AnyFlow<C extends FlowClients = FlowClients> = Flow<
  C,
  Varies,
  Varies,
  Varies
>;

/**
 * Declares a flow: when an event of type `on` arrives, read the source record,
 * map it to the target block's input and create the target record, once. The
 * new record is linked `created_from` the source, so `relations.lineage` finds
 * the chain and a second run returns the first record.
 */
export function defineFlow<
  C extends FlowClients,
  P = unknown,
  S = undefined,
  T = unknown,
>(spec: FlowSpec<C, P, S, T>): Flow<C, P, S, T> {
  return { ...spec, apiVersion: 1 };
}

/** What `run` did with one event. */
export type FlowOutcome =
  | { readonly status: "created"; readonly target: FlowRef }
  | { readonly status: "exists"; readonly target: FlowRef }
  | { readonly status: "skipped" };

/** A queued flow run: the flow's name and the event, as JSON. */
export interface FlowJob {
  readonly flow: string;
  readonly event: FlowEvent;
}

export interface FlowsOptions<C extends FlowClients> {
  /** The flows to turn on. A built-in runs only when it is listed here. */
  readonly flows: readonly AnyFlow<C>[];
  /**
   * The block clients for one tenant, such as `createBlocks` with `tenant: ()
   * => tenant` over a service connection.
   */
  readonly clients: (tenant: string, event: FlowEvent) => C | PromiseLike<C>;
  /**
   * Queues each run as a job instead of running it in the outbox consumer, such
   * as `(job, dedupeKey) => jobs.enqueueOnce("flows", job, { dedupeKey })`. The
   * key is `flow:<name>:<event id>`, so a redelivered event queues once.
   */
  readonly enqueue?: (
    job: FlowJob,
    dedupeKey: string,
  ) => PromiseLike<Result<unknown>>;
  /** Receives each run's outcome. */
  readonly onOutcome?: (
    flow: string,
    event: FlowEvent,
    outcome: FlowOutcome,
  ) => void;
}

export interface Flows {
  /** The flows that start on an event type. */
  matching(type: string): readonly string[];
  /** Runs one flow for one event, once: a second run returns `exists`. */
  run(flow: string, event: FlowEvent): AsyncResult<FlowOutcome>;
  /**
   * The outbox consumer, for `outbox.consume("flows", flows.sink())`. It throws
   * when a run or an enqueue fails, so the outbox delivers the event again; the
   * runs that already finished find their record and return `exists`.
   */
  sink(): (events: readonly FlowEvent[]) => Promise<void>;
  /** The job handler for the queue `enqueue` writes to. */
  handler(): (payload: FlowJob) => Promise<void>;
}

function flowError(message: string, hint: string): DbError {
  return dbError("invalid_request", message, { hint });
}

/** The event's organization: the outbox tenant, or `organizationId` in it. */
function tenantOf(event: FlowEvent): string | undefined {
  if (typeof event.tenant === "string" && event.tenant !== "") {
    return event.tenant;
  }

  const payload = event.payload;

  const organizationId = isRecord(payload)
    ? payload["organizationId"]
    : undefined;

  return typeof organizationId === "string" && organizationId !== ""
    ? organizationId
    : undefined;
}

/** The fields of an event a job can store. */
function jobEvent(event: FlowEvent): FlowEvent {
  return {
    id: event.id,
    type: event.type,
    payload: event.payload,
    subject: event.subject ?? null,
    tenant: event.tenant ?? null,
    actorId: event.actorId ?? null,
  };
}

async function validated<T>(
  schema: StandardSchemaV1<T> | undefined,
  value: T,
): Promise<Result<T>> {
  if (schema === undefined) {
    return ok(value);
  }

  const checked = await schema["~standard"].validate(value);

  if (checked.issues !== undefined) {
    return err(
      dbError(
        "validation",
        "The flow's mapped input doesn't pass the target schema",
        {
          issues: checked.issues.map((issue) => ({
            message: issue.message,
            ...(issue.path === undefined
              ? {}
              : {
                  path: issue.path.map((part) =>
                    typeof part === "object" ? part.key : part,
                  ),
                }),
          })),
        },
      ),
    );
  }

  return ok(checked.value);
}

async function runFlow<C extends FlowClients>(
  flow: AnyFlow<C>,
  event: FlowEvent,
  options: FlowsOptions<C>,
): Promise<Result<FlowOutcome>> {
  const source = flow.source(event);

  if (source === undefined) {
    return ok({ status: "skipped" });
  }

  const tenant = tenantOf(event);

  if (tenant === undefined) {
    return err(
      flowError(
        `Event ${event.id} names no organization for flow ${flow.name}`,
        "FLOW_TENANT_REQUIRED",
      ),
    );
  }

  const clients = await options.clients(tenant, event);
  const existing = await clients.relations.convertedInto(source, flow.target);

  if (!existing.ok) {
    return existing;
  }

  if (existing.data !== undefined) {
    return ok({
      status: "exists",
      target: { type: flow.target, id: existing.data },
    });
  }

  const context: FlowContext<C> = { clients, tenant, event, source };

  const loaded =
    flow.load === undefined ? ok(undefined) : await flow.load(context);

  if (!loaded.ok) {
    return loaded;
  }

  const { map } = flow;
  const input = await validated(flow.input, map(loaded.data, context));

  if (!input.ok) {
    return input;
  }

  const created = await flow.create(input.data, context);

  if (!created.ok) {
    return created;
  }

  const target = { type: flow.target, id: created.data.id };

  if (flow.linksItself !== true) {
    const linked = await clients.relations.link(target, source, {
      kind: "created_from",
    });

    if (!linked.ok) {
      return linked;
    }
  }

  return ok({ status: "created", target });
}

/**
 * Turns flows on: an outbox consumer that runs, or queues, every flow whose
 * `on` matches an event, and the job handler that runs the queued ones.
 *
 * ```ts
 * const flows = createFlows({
 *   flows: [conversationToWorkItem()],
 *   clients: (tenant) => blocksFor(tenant),
 * });
 * await outbox.consume("flows", flows.sink());
 * ```
 */
export function createFlows<C extends FlowClients>(
  options: FlowsOptions<C>,
): Flows {
  const byName = new Map<string, AnyFlow<C>>();

  for (const flow of options.flows) {
    if (byName.has(flow.name)) {
      throw new TypeError(`Two flows are named ${flow.name}`);
    }

    byName.set(flow.name, flow);
  }

  const matching = (type: string): readonly string[] =>
    options.flows
      .filter((flow) =>
        typeof flow.on === "string" ? flow.on === type : flow.on.includes(type),
      )
      .map((flow) => flow.name);

  const run = (name: string, event: FlowEvent): AsyncResult<FlowOutcome> =>
    AsyncResult.from(async () => {
      const flow = byName.get(name);

      if (flow === undefined) {
        return err(flowError(`No flow is named ${name}`, "FLOW_NOT_FOUND"));
      }

      const outcome = await runFlow(flow, event, options);

      if (outcome.ok) {
        options.onOutcome?.(name, event, outcome.data);
      }

      return outcome;
    });

  return {
    matching,
    run,
    sink: () => async (events) => {
      for (const event of events) {
        for (const name of matching(event.type)) {
          if (options.enqueue === undefined) {
            await run(name, event).orThrow();
            continue;
          }

          const queued = await options.enqueue(
            { flow: name, event: jobEvent(event) },
            `flow:${name}:${event.id}`,
          );

          if (!queued.ok) {
            await AsyncResult.err(queued.error).orThrow();
          }
        }
      }
    },
    handler: () => async (payload) => {
      await run(payload.flow, payload.event).orThrow();
    },
  };
}
