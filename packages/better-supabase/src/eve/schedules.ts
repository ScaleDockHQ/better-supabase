import type { StandardSchemaV1 } from "@standard-schema/spec";

import type { ScheduleOptions } from "../blocks/queue/types.ts";
import type { RequestContext } from "../core/plugin.ts";
import type { AsyncResult } from "../core/result.ts";
import type { EveSessionAuth } from "./types.ts";

import { isRecord } from "../core/block-helpers.ts";

/** What one `eve` queue job asks for: a prompt sent to a channel's target. */
export interface EveAgentJob {
  readonly prompt: string;
  /** A key of `queueSchedules`' `channels`. */
  readonly channel: string;
  /** The channel's proactive target, such as `{ channelId }` for Slack. */
  readonly target: unknown;
}

/**
 * The queue schema for `EveAgentJob`: pass it as the `eve` queue in
 * `createQueue({ queues })`.
 */
export const eveAgentJob: StandardSchemaV1<EveAgentJob> = {
  "~standard": {
    version: 1,
    vendor: "better-supabase",
    validate(value) {
      if (
        !isRecord(value) ||
        typeof value["prompt"] !== "string" ||
        value["prompt"] === "" ||
        typeof value["channel"] !== "string" ||
        value["channel"] === ""
      ) {
        return {
          issues: [
            {
              message:
                "an eve job needs a non-empty prompt and channel, and a target",
            },
          ],
        };
      }

      return {
        value: {
          prompt: value["prompt"],
          channel: value["channel"],
          target: value["target"] ?? null,
        },
      };
    },
  },
};

/** The handle eve's `to(channel, target)` returns. */
export interface EveTargetHandle {
  send(
    message: string,
    options: { readonly auth: EveSessionAuth | null },
  ): Promise<unknown>;
}

/**
 * The part of eve's `ScheduleHandlerArgs` (and route handler args) the dispatch
 * uses. `to` is generic in eve, so its parameters are `never` here.
 */
export interface EveDispatchArgs {
  readonly to: (channel: never, target: never) => EveTargetHandle;
  /** The app principal, for jobs that record no user. */
  readonly appAuth: EveSessionAuth;
}

/** Eve's `ScheduleHandlerArgs`. */
export interface EveScheduleArgs extends EveDispatchArgs {
  readonly waitUntil: (task: Promise<unknown>) => void;
}

/** The part of a queue job the dispatch reads. */
export interface EveQueueJob {
  readonly context: RequestContext;
}

/** The part of the queue block `queueSchedules` drains. */
export interface EveQueueDrainer {
  /** Enqueues the due schedules' jobs; a pg_cron scheduler has none. */
  runSchedules(): AsyncResult<number>;
  drain(input: {
    queue: never;
    handler: (payload: EveAgentJob, job: EveQueueJob) => unknown;
    readonly budgetMs?: number;
  }): Promise<unknown>;
}

/** The part of the queue block `scheduleAgent` writes to. */
export interface EveQueueScheduler {
  schedule(
    input: {
      name: string;
      cron: string;
      queue: string;
      payload: EveAgentJob;
    } & ScheduleOptions,
  ): AsyncResult<void>;
}

/** Options for `agentJobHandler` and `queueSchedules`. */
export interface AgentJobOptions {
  /** Eve channel definitions by the key jobs name in `channel`. */
  readonly channels: Readonly<Record<string, object>>;
}

/**
 * The session auth for a job: its recorded user as a Supabase principal with
 * the job's tenant, else eve's app principal.
 */
export function jobAuth(
  context: RequestContext,
  appAuth: EveSessionAuth,
): EveSessionAuth {
  const actor = context.actor;

  if (actor?.kind !== "user") {
    return appAuth;
  }

  return {
    authenticator: "supabase",
    principalType: "user",
    principalId: actor.id,
    subject: actor.id,
    attributes:
      context.tenant === undefined ? {} : { tenantId: context.tenant },
  };
}

const sendTo = (
  args: EveDispatchArgs,
  channel: object,
  target: unknown,
): EveTargetHandle =>
  // SAFETY: `channel` is an eve channel definition and `target` the job's
  // proactive target for it; eve's generic `to` can't be named structurally.
  args.to(channel as never, target as never);

/**
 * The handler for one `eve` queue job: sends its prompt to the channel's target
 * as the job's user (`jobAuth`). Pass it to `drain`, or to `vercelQueueRoute`
 * from an eve route so pushed deliveries start sessions.
 */
export function agentJobHandler(
  options: AgentJobOptions,
  args: EveDispatchArgs,
): (payload: EveAgentJob, job: EveQueueJob) => Promise<void> {
  return async (payload, job) => {
    const channel = options.channels[payload.channel];

    if (channel === undefined) {
      throw new TypeError(
        `eve: no channel "${payload.channel}" in queueSchedules' channels`,
      );
    }

    await sendTo(args, channel, payload.target).send(payload.prompt, {
      auth: jobAuth(job.context, args.appAuth),
    });
  };
}

/** Options for `queueSchedules`. */
export interface QueueSchedulesOptions extends AgentJobOptions {
  readonly queue: EveQueueDrainer;
  /** The queue jobs wait in. Default: `eve`. */
  readonly queueName?: string;
  /** Stop claiming after this many ms. Default: 50 000. */
  readonly budgetMs?: number;
}

/**
 * The `run` handler for an eve schedule that fires every minute
 * (`defineSchedule({ cron: "* * * * *", run })`): it enqueues the queue block's
 * due schedules (per tenant and time zone), then drains the `eve` queue and
 * starts a session for each job with `agentJobHandler`.
 */
export function queueSchedules(
  options: QueueSchedulesOptions,
): (args: EveScheduleArgs) => void {
  const run = async (args: EveScheduleArgs) => {
    await options.queue.runSchedules().orThrow();

    return options.queue.drain({
      // SAFETY: the drainer's queue names are the app's own; `never` keeps a
      // `Queue` with literal names assignable, and the name is checked there.
      queue: (options.queueName ?? "eve") as never,
      handler: agentJobHandler(options, args),
      budgetMs: options.budgetMs ?? 50_000,
    });
  };

  return (args) => {
    args.waitUntil(run(args));
  };
}

/** Options for `scheduleAgent`: the queue block's, and the queue name. */
export interface ScheduleAgentOptions extends ScheduleOptions {
  /** Default: `eve`. */
  readonly queue?: string;
}

/**
 * Writes a queue block schedule that sends `job.prompt` to the channel's target
 * on `cron`. Pass `context` to run each session as that user and `timeZone` to
 * read the cron in the tenant's zone.
 */
export function scheduleAgent(
  queue: EveQueueScheduler,
  name: string,
  cron: string,
  job: EveAgentJob,
  options: ScheduleAgentOptions = {},
): AsyncResult<void> {
  const { queue: queueName, ...rest } = options;

  return queue.schedule({
    name,
    cron,
    queue: queueName ?? "eve",
    payload: job,
    ...rest,
  });
}
