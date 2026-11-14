import type { QueueProvider } from "../../../src/blocks/queue/backends.ts";
import type { VercelQueueClient } from "../../../src/blocks/queue/vercel-queue.ts";
import type { VercelQueueCallbackClient } from "../../../src/blocks/queue/vercel-route.ts";
import type {
  VercelSchedule,
  VercelSchedulesClient,
  VercelScheduleWrite,
} from "../../../src/blocks/queue/vercel-scheduler.ts";
import type { VercelScheduleQueueMessage } from "../../../src/blocks/queue/vercel-schedules.ts";

/** A `SchedulesApiError` as `@vercel/schedules` throws it. */
export class FakeSchedulesApiError extends Error {
  readonly status: number;
  readonly code: string;
  readonly retryAfter?: number;

  constructor(status: number, code: string, retryAfter?: number) {
    super(`${code} (${String(status)})`);
    this.status = status;
    this.code = code;

    if (retryAfter !== undefined) {
      this.retryAfter = retryAfter;
    }
  }
}

interface StoredVercelSchedule extends VercelSchedule {
  readonly payload?: unknown;
}

export interface FakeSchedules {
  readonly client: VercelSchedulesClient;
  readonly calls: string[];
  fire(
    name: string,
    namespace?: string,
  ): { readonly topic: string; readonly message: VercelScheduleQueueMessage };
  addStatic(name: string, cron: string, topic: string): void;
  space(namespace?: string): Map<string, StoredVercelSchedule>;
}

/** Vercel Schedules in memory, with the API's errors and paging. */
export function fakeSchedules(): FakeSchedules {
  const spaces = new Map<string, Map<string, StoredVercelSchedule>>();
  const calls: string[] = [];
  let executions = 0;
  let created = 0;

  const space = (namespace = "default") => {
    const found =
      spaces.get(namespace) ?? new Map<string, StoredVercelSchedule>();

    spaces.set(namespace, found);

    return found;
  };

  const stored = (
    params: VercelScheduleWrite,
    source = "dynamic",
  ): StoredVercelSchedule => ({
    name: params.name,
    namespace: params.namespace ?? "default",
    expression: params.expression,
    timezone: params.timezone ?? "UTC",
    target: { type: "queue", topic: params.target.topic },
    source,
    createdAt: 1_700_000_000_000 + created,
    ...(params.payload === undefined ? {} : { payload: params.payload }),
  });

  const client: VercelSchedulesClient = {
    create: async (params) => {
      calls.push(`create ${params.namespace ?? "default"}/${params.name}`);
      const names = space(params.namespace);

      if (names.has(params.name)) {
        throw new FakeSchedulesApiError(409, "schedule_already_exists");
      }

      if (/[A-Z]{3}|\b7\b/.test(params.expression.cron)) {
        throw new FakeSchedulesApiError(400, "invalid_cron_expression");
      }

      created += 1;
      names.set(params.name, stored(params));

      return names.get(params.name)!;
    },
    update: async (params) => {
      calls.push(`update ${params.namespace ?? "default"}/${params.name}`);
      const names = space(params.namespace);
      const current = names.get(params.name);

      if (current === undefined) {
        throw new FakeSchedulesApiError(404, "not_found");
      }

      if (current.source === "static") {
        throw new FakeSchedulesApiError(400, "static_schedule");
      }

      const next = { ...stored(params), createdAt: current.createdAt };

      names.set(params.name, next);

      return next;
    },
    delete: async (params) => {
      calls.push(`delete ${params.namespace ?? "default"}/${params.name}`);

      if (!space(params.namespace).delete(params.name)) {
        throw new FakeSchedulesApiError(404, "not_found");
      }
    },
    list: async (params = {}) => {
      const all = [...space(params.namespace).values()];
      const start = Number(params.cursor ?? 0);
      const limit = params.limit ?? 20;
      const data = all.slice(start, start + limit);

      return {
        data,
        cursor: start + limit < all.length ? String(start + limit) : null,
      };
    },
  };

  /** The message a run of the schedule publishes on its topic. */
  const fire = (
    name: string,
    namespace = "default",
  ): {
    readonly topic: string;
    readonly message: VercelScheduleQueueMessage;
  } => {
    const schedule = space(namespace).get(name);

    if (schedule === undefined) {
      throw new Error(`No schedule ${namespace}/${name}`);
    }

    executions += 1;

    return {
      topic: schedule.target.topic ?? "",
      message: {
        scheduleId: `sch_${name}`,
        executionId: `schx_${String(executions)}`,
        name,
        namespace,
        scheduledAt: "2026-11-14T09:00:00.000Z",
        expression:
          schedule.expression.type === "cron" ? schedule.expression.cron : "",
        source: schedule.source === "static" ? "static" : "dynamic",
        ...(schedule.payload === undefined
          ? {}
          : { payload: schedule.payload }),
      },
    };
  };

  /** A static schedule from `vercel.json`, in the `default` namespace. */
  const addStatic = (name: string, cron: string, topic: string): void => {
    space("default").set(
      name,
      stored(
        { name, expression: { type: "cron", cron }, target: { topic } },
        "static",
      ),
    );
  };

  return { client, calls, fire, addStatic, space };
}

interface Message {
  readonly id: string;
  readonly body: unknown;
  deliveries: number;
  done: boolean;
}

type Handler = Parameters<VercelQueueCallbackClient["handleCallback"]>[0];

type HandlerOptions = Parameters<
  VercelQueueCallbackClient["handleCallback"]
>[1];

export interface FakeVercelQueues {
  readonly client: VercelQueueClient & VercelQueueCallbackClient;
  /** The size of each `sendBatch`. */
  readonly batches: number[];
  publish(topic: string, body: unknown): string;
  /** The errors the route threw. */
  deliver(topic: string, index?: number): Promise<unknown[]>;
  /** The bodies not yet acknowledged. */
  open(topic: string): readonly unknown[];
}

/**
 * Vercel Queues in memory for push delivery: `send` and `sendBatch` keep
 * messages per topic, and `deliver` runs the handler a route registered with
 * `handleCallback`, retrying or acknowledging as its `retry` says.
 */
export function fakeVercelQueues(
  options: { readonly batch?: boolean } = {},
): FakeVercelQueues {
  const topics = new Map<string, Message[]>();
  const routes: { handler: Handler; options: HandlerOptions }[] = [];
  const batches: number[] = [];
  let count = 0;

  const publish = (topic: string, body: unknown): string => {
    count += 1;
    const id = `m${String(count)}`;
    const list = topics.get(topic) ?? [];

    list.push({ id, body, deliveries: 0, done: false });
    topics.set(topic, list);

    return id;
  };

  const client: VercelQueueClient & VercelQueueCallbackClient = {
    send: async (topic, payload) => ({ messageId: publish(topic, payload) }),
    ...(options.batch === false
      ? {}
      : {
          sendBatch: async (topic, messages) => {
            batches.push(messages.length);

            return messages.map((message) => ({
              status: "sent" as const,
              messageId: publish(topic, message.payload),
            }));
          },
        }),
    handleCallback: (handler, handlerOptions) => {
      routes.push({ handler, options: handlerOptions });

      return async () => new Response(null, { status: 200 });
    },
  };

  /** Runs each open message on `topic` once through the route at `index`. */
  const deliver = async (
    topic: string,
    index = routes.length - 1,
  ): Promise<unknown[]> => {
    const route = routes[index];

    if (route === undefined) {
      throw new Error("No route registered");
    }

    const errors: unknown[] = [];

    for (const message of topics.get(topic) ?? []) {
      if (message.done) {
        continue;
      }

      message.deliveries += 1;

      const metadata = {
        messageId: message.id,
        deliveryCount: message.deliveries,
        createdAt: new Date("2026-11-14T09:00:00Z"),
        expiresAt: new Date("2026-11-15T09:00:00Z"),
        topicName: topic,
      };

      try {
        await route.handler(message.body, metadata);
        message.done = true;
      } catch (error) {
        errors.push(error);
        const directive = route.options?.retry?.(error, metadata);

        if (directive && "acknowledge" in directive) {
          message.done = true;
        }
      }
    }

    return errors;
  };

  const open = (topic: string): readonly unknown[] =>
    (topics.get(topic) ?? [])
      .filter((message) => !message.done)
      .map((message) => message.body);

  return { client, publish, deliver, open, batches };
}

/**
 * A database queue in memory with `sendOnce` and `hasWork`: what the bridge
 * route needs from a pgmq queue. `work` answers each probe.
 */
export function memoryOnceQueue(work: Readonly<Record<string, boolean>> = {}): {
  readonly provider: QueueProvider;
  readonly sent: { queue: string; payload: unknown; key: string }[];
  readonly probes: string[];
} {
  const sent: { queue: string; payload: unknown; key: string }[] = [];
  const probes: string[] = [];

  const provider: QueueProvider = {
    apiVersion: 1,
    name: "sql",
    leases: false,
    send: async () => 1,
    sendOnce: async (queue, payload, _delay, _max, key) => {
      const index = sent.findIndex((entry) => entry.key === key);

      if (index !== -1) {
        return { id: index + 1, duplicate: true };
      }

      sent.push({ queue, payload, key });

      return { id: sent.length, duplicate: false };
    },
    hasWork: async (probe) => {
      probes.push(probe);

      return work[probe] ?? true;
    },
    read: async () => [],
    complete: async () => false,
    fail: async () => null,
    extend: async () => false,
    schedule: async () => undefined,
    unschedule: async () => false,
  };

  return { provider, sent, probes };
}
