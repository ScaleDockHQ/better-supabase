import type { World } from "@workflow/world";
import type { Hook, Run } from "workflow/api";

import { getHookByToken, getRun, start } from "workflow/api";
import { getWorld } from "workflow/runtime";

import type { OutboxEvent, OutboxHandler } from "../blocks/outbox/outbox.ts";
import type {
  WorkflowPrincipalKind,
  WorkflowStartCall,
  WorkflowStarter,
  WorkflowSubject,
} from "../blocks/workflows/workflows.ts";
import type { Actor, RequestContext } from "../core/plugin.ts";

import { PERMISSION_CAP_CLAIM } from "../auth/delegation.ts";
import { unwrap, withContext } from "../blocks/queue/envelope.ts";
import { subjectAttribute, WORKFLOW_ATTRIBUTES } from "./attributes.ts";
import { runKeysOf } from "./run-keys.ts";

/** A workflow function (a `"use workflow"` export), typed structurally. */
export type WorkflowFn<
  TArgs extends unknown[] = unknown[],
  TResult = unknown,
> = (...args: TArgs) => Promise<TResult>;

export interface WorkflowContextOptions {
  /** The opaque ticket `bsb.forContext` resolves; wins over `context.ticket`. */
  readonly ticket?: string;
}

/**
 * The actor, tenant and ticket of `context` as plain data, to pass into a
 * workflow as an argument; inside a step, `bsb.forContext(context)` runs as
 * that user with RLS. A delegated token's `client_id`, `scope`,
 * `authorization_details` and `act` chain stay in `claims`, so the step is as
 * narrow as the token; other claims stay out of the run's serialized state.
 * Throws a `TypeError` for an invalid `act` chain or ticket.
 */
export function workflowContext(
  context: RequestContext,
  options: WorkflowContextOptions = {},
): RequestContext {
  return unwrap(withContext(null, context, options)).context;
}

/** The `bsb.tenant`, `bsb.actor` and `bsb.ticket` attributes for `context`. */
export function contextAttributes(
  context: RequestContext,
  options: WorkflowContextOptions = {},
): Record<string, string> {
  const recorded = workflowContext(context, options);
  const ticket = recorded["ticket"];

  return {
    ...(recorded.tenant === undefined
      ? {}
      : { [WORKFLOW_ATTRIBUTES.tenant]: recorded.tenant }),
    ...(recorded.actor?.kind === "user"
      ? { [WORKFLOW_ATTRIBUTES.actor]: recorded.actor.id }
      : {}),
    ...(typeof ticket === "string"
      ? { [WORKFLOW_ATTRIBUTES.ticket]: ticket }
      : {}),
  };
}

export interface StartForOptions {
  /**
   * Starting again with the same key returns the run the first start created,
   * while that run is in the World. Schedules and admission pass
   * `schedule:{id}:{fireAt}` and `admission:{id}`.
   */
  readonly idempotencyKey?: string;
  /**
   * More attributes for the run; `bsb.*` keys are set from the context, and
   * `bsb.principal_kind` and `bsb.principal` only by `runAs` starts.
   */
  readonly attributes?: Readonly<Record<string, string>>;
  /** The record the run belongs to, stored as `bsb.subject`. */
  readonly subject?: WorkflowSubject;
  /** The World to look the key up in. Defaults to the configured one. */
  readonly world?: World;
  /**
   * An opaque ticket, stored as the `bsb.ticket` attribute instead of
   * `context.ticket`. Pass `workflowContext(context, { ticket })` as an
   * argument too, so a step's `bsb.forContext` resolves it.
   */
  readonly ticket?: string;
}

/** The run a start with idempotency `key` created, while it is in the World. */
export async function runForKey(
  key: string,
  world: World | undefined,
): Promise<string | undefined> {
  const target = world ?? (await getWorld());

  if (target.analytics === undefined) {
    return undefined;
  }

  const page = await target.analytics.runs.list({
    attributes: { [WORKFLOW_ATTRIBUTES.key]: key },
    pagination: { limit: 1 },
  });

  return page.data[0]?.runId;
}

/**
 * `start(workflow, args)` for the caller in `context`: the run carries
 * `bsb.tenant` and `bsb.actor`, so `workflow_runs` lists it to the tenant and
 * the actor under RLS. With `idempotencyKey`, a run that already has the key is
 * returned instead of starting another. The Supabase World claims the key in
 * `workflow.workflow_run_keys` first, so concurrent starts with one key start
 * one run; other Worlds need `analytics` to look the key up.
 */
export function startFor<TArgs extends unknown[], TResult>(
  context: RequestContext,
  workflow: WorkflowFn<TArgs, TResult>,
  args: TArgs,
  options: StartForOptions = {},
): Promise<Run<TResult>> {
  return startRun(context, workflow, args, options, {});
}

export interface StartOnceOptions extends Omit<
  StartForOptions,
  "idempotencyKey"
> {
  /** The idempotency key: one run per key while the run is in the World. */
  readonly key: string;
}

/**
 * `startFor` with a required idempotency key: every start with `key` resolves
 * to the run the first one created, also when they race.
 */
export function startOnce<TArgs extends unknown[], TResult>(
  context: RequestContext,
  workflow: WorkflowFn<TArgs, TResult>,
  args: TArgs,
  options: StartOnceOptions,
): Promise<Run<TResult>> {
  const { key, ...rest } = options;

  if (typeof key !== "string" || key === "" || key.length > 500) {
    throw new TypeError(
      "better-supabase: startOnce needs a key of 1 to 500 characters",
    );
  }

  return startRun(
    context,
    workflow,
    args,
    { ...rest, idempotencyKey: key },
    {},
  );
}

const RUN_AS_ATTRIBUTES: ReadonlySet<string> = new Set([
  WORKFLOW_ATTRIBUTES.principalKind,
  WORKFLOW_ATTRIBUTES.principal,
]);

/**
 * `startFor` with `trusted` applied last: a `runAs` start sets the principal
 * and replaces `bsb.actor` with the user who triggered it (`undefined` removes
 * a key).
 */
async function startRun<TArgs extends unknown[], TResult>(
  context: RequestContext,
  workflow: WorkflowFn<TArgs, TResult>,
  args: TArgs,
  options: StartForOptions,
  trusted: Readonly<Record<string, string | undefined>>,
): Promise<Run<TResult>> {
  const key = options.idempotencyKey;
  const attributes: Record<string, string> = {};

  for (const [name, value] of Object.entries(options.attributes ?? {})) {
    if (!RUN_AS_ATTRIBUTES.has(name)) {
      attributes[name] = value;
    }
  }

  Object.assign(
    attributes,
    contextAttributes(
      context,
      options.ticket === undefined ? {} : { ticket: options.ticket },
    ),
    options.subject === undefined
      ? {}
      : { [WORKFLOW_ATTRIBUTES.subject]: subjectAttribute(options.subject) },
    key === undefined ? {} : { [WORKFLOW_ATTRIBUTES.key]: key },
  );

  for (const [name, value] of Object.entries(trusted)) {
    if (value === undefined) {
      delete attributes[name];
    } else {
      attributes[name] = value;
    }
  }

  const launch = (): Promise<Run<TResult>> =>
    start(workflow, args, {
      attributes,
      ...(options.world === undefined ? {} : { world: options.world }),
    });

  return key === undefined ? launch() : startKeyed(key, options.world, launch);
}

const KEY_WAIT_ATTEMPTS = 20;
const KEY_WAIT_MS = 250;

const sleep = (ms: number): Promise<void> =>
  new Promise((resolve) => {
    setTimeout(resolve, ms);
  });

/**
 * Starts the run for `key` once. A World with run keys claims the key first, so
 * a concurrent start with the same key waits for the first one's run instead of
 * starting another; other Worlds look the key up in `analytics`.
 */
async function startKeyed<TResult>(
  key: string,
  world: World | undefined,
  launch: () => Promise<Run<TResult>>,
): Promise<Run<TResult>> {
  const target = world ?? (await getWorld());
  const keys = runKeysOf(target);

  if (keys === undefined) {
    const existing = await runForKey(key, target);

    return existing === undefined ? launch() : getRun<TResult>(existing);
  }

  for (let attempt = 0; attempt < KEY_WAIT_ATTEMPTS; attempt += 1) {
    const claim = await keys.claim(key);

    if (claim.runId !== undefined) {
      return getRun<TResult>(claim.runId);
    }

    if (claim.claimed) {
      // A run started before the key table existed carries the key only as
      // its `bsb.key` attribute.
      const existing = await runForKey(key, target);
      let run: Run<TResult>;

      try {
        run =
          existing === undefined ? await launch() : getRun<TResult>(existing);
      } catch (cause) {
        await keys.release(key).catch(() => undefined);
        throw cause;
      }

      await keys.set(key, run.runId);

      return run;
    }

    await sleep(KEY_WAIT_MS);
  }

  const existing = await runForKey(key, target);

  if (existing === undefined) {
    throw new Error(
      `better-supabase: another start with idempotency key ${JSON.stringify(key)} has not finished`,
    );
  }

  return getRun<TResult>(existing);
}

/**
 * Who an event or schedule start runs as: the publisher, a user who holds the
 * permissions, and the permission keys its steps may use. A step's
 * `bsb.forContext(context)` runs as the publisher, capped to `permissions`, so
 * a publisher who lost one fails the step. The event actor or schedule creator
 * is the run's actor (and `bsb.trigger`) and grants nothing; the publisher is
 * recorded as the run's principal.
 */
export interface WorkflowRunAs {
  readonly publisher: string;
  readonly permissions: readonly string[];
  /** The tenant the steps run in. Defaults to the event's or schedule's. */
  readonly tenant?: string;
  /**
   * What the publisher is, recorded as the run's `principal_kind`: `user`
   * (default), or `service_principal` for the app's service principal (an auth
   * user too, so steps still run as it).
   */
  readonly principalKind?: WorkflowPrincipalKind;
}

/** A fixed `WorkflowRunAs`, or one per start; `null` refuses the start. */
export type WorkflowRunAsFor<T> =
  | WorkflowRunAs
  | ((
      source: T,
    ) =>
      | WorkflowRunAs
      | null
      | undefined
      | Promise<WorkflowRunAs | null | undefined>);

const PRINCIPAL_KINDS: readonly string[] = [
  "user",
  "service_principal",
  "system",
  "external",
] satisfies readonly WorkflowPrincipalKind[];

async function resolveRunAs<T>(
  runAs: WorkflowRunAsFor<T>,
  source: T,
): Promise<WorkflowRunAs | undefined> {
  const resolved = typeof runAs === "function" ? await runAs(source) : runAs;

  if (resolved === null || resolved === undefined) {
    return undefined;
  }

  if (
    typeof resolved.publisher !== "string" ||
    resolved.publisher === "" ||
    !Array.isArray(resolved.permissions) ||
    !resolved.permissions.every((key) => typeof key === "string") ||
    (resolved.principalKind !== undefined &&
      !PRINCIPAL_KINDS.includes(resolved.principalKind))
  ) {
    throw new TypeError(
      "better-supabase: runAs needs a publisher and a list of permission keys",
    );
  }

  return resolved;
}

/**
 * The context and attributes of a start that runs as `runAs`; `trusted`
 * replaces the context's `bsb.actor` with the trigger and records the
 * principal.
 */
function runAsStart(
  runAs: WorkflowRunAs,
  start: {
    readonly tenant: string | undefined;
    readonly trigger: string | undefined;
    readonly ticket?: string | undefined;
  },
): {
  readonly context: RequestContext;
  readonly attributes: Record<string, string>;
  readonly trusted: Readonly<Record<string, string | undefined>>;
} {
  const tenant = runAs.tenant ?? start.tenant;

  return {
    context: workflowContext({
      actor: { id: runAs.publisher, kind: "user" },
      ...(tenant === undefined ? {} : { tenant }),
      claims: { [PERMISSION_CAP_CLAIM]: [...runAs.permissions] },
      ...(start.ticket === undefined ? {} : { ticket: start.ticket }),
    }),
    attributes: {
      [WORKFLOW_ATTRIBUTES.publisher]: runAs.publisher,
      ...(start.trigger === undefined
        ? {}
        : { [WORKFLOW_ATTRIBUTES.trigger]: start.trigger }),
    },
    trusted: {
      [WORKFLOW_ATTRIBUTES.actor]: start.trigger,
      [WORKFLOW_ATTRIBUTES.principalKind]: runAs.principalKind ?? "user",
      [WORKFLOW_ATTRIBUTES.principal]: runAs.publisher,
    },
  };
}

function userContext(call: WorkflowStartCall): RequestContext {
  const actor: Actor | undefined =
    call.actor === undefined ? undefined : { id: call.actor, kind: "user" };

  return {
    ...(actor === undefined ? {} : { actor }),
    ...(call.tenant === undefined ? {} : { tenant: call.tenant }),
  };
}

export interface WorkflowStarterOptions extends Pick<StartForOptions, "world"> {
  /**
   * The publisher a start runs as. Required for schedules: a schedule start
   * without it, or with `null` for it, throws and the tick records the failure.
   * An admission request runs as its actor unless this is set.
   */
  readonly runAs?: WorkflowRunAsFor<WorkflowStartCall>;
  /**
   * The workflow's arguments. Defaults to the stored input. `context` is the
   * context the run starts as, to pass to the workflow for its steps.
   */
  readonly args?: (
    call: WorkflowStartCall,
    context: RequestContext,
  ) => readonly unknown[];
}

/**
 * The `start` callback for `schedules.tick` and `admission.tick` of
 * `better-supabase/blocks/workflows`: looks the workflow up by the name the
 * schedule or request stored and starts it with `startFor`, keyed by the tick's
 * idempotency key. A schedule runs as its `runAs` publisher.
 */
export function workflowStarter(
  workflows: Readonly<Record<string, WorkflowFn<never[]>>>,
  options: WorkflowStarterOptions = {},
): WorkflowStarter {
  return async (call) => {
    const workflow = workflows[call.workflow];

    if (workflow === undefined) {
      throw new Error(
        `better-supabase: no workflow named "${call.workflow}" was passed to workflowStarter`,
      );
    }

    const runAs =
      options.runAs === undefined
        ? undefined
        : await resolveRunAs(options.runAs, call);

    if (runAs === undefined && (call.source === "schedule" || options.runAs)) {
      throw new Error(
        options.runAs === undefined
          ? `better-supabase: the schedule for "${call.workflow}" needs a runAs publisher: pass workflowStarter(workflows, { runAs })`
          : `better-supabase: runAs refused the start of "${call.workflow}"`,
      );
    }

    const started =
      runAs === undefined
        ? { context: userContext(call), attributes: {}, trusted: {} }
        : runAsStart(runAs, { tenant: call.tenant, trigger: call.actor });

    const input = Array.isArray(call.input) ? call.input : [call.input];
    const args = options.args?.(call, started.context) ?? input;

    const run = await startRun(
      started.context,
      workflow,
      // SAFETY: the stored input is the argument list the schedule or request was created with.
      args as never[],
      {
        idempotencyKey: call.idempotencyKey,
        attributes: started.attributes,
        ...(call.subject === undefined ? {} : { subject: call.subject }),
        ...(options.world === undefined ? {} : { world: options.world }),
      },
      started.trusted,
    );

    return run.runId;
  };
}

/**
 * Hook metadata that `authorizeHook` checks: the actor and tenant of `context`,
 * and the permission a tenant member needs to resume it instead.
 */
export function hookMetadata(
  context: RequestContext,
  permission?: string,
): Record<string, string> {
  return {
    ...contextAttributes(context),
    ...(permission === undefined ? {} : { "bsb.permission": permission }),
  };
}

/** `authorizeHook` refused the caller. */
export class HookForbiddenError extends Error {
  readonly status = 403;
  constructor(message: string) {
    super(message);
    this.name = "HookForbiddenError";
  }
}

export interface AuthorizeHookOptions {
  /**
   * Whether the caller holds `permission` in `tenant`, for hooks created with
   * `hookMetadata(context, permission)`, such as an approval any admin of the
   * tenant may give.
   */
  readonly can?: (
    tenant: string,
    permission: string,
  ) => boolean | Promise<boolean>;
}

function stringField(value: unknown, key: string): string | undefined {
  if (typeof value !== "object" || value === null) {
    return undefined;
  }

  const record: Record<string, unknown> = { ...value };
  const field = record[key];

  return typeof field === "string" ? field : undefined;
}

/**
 * The hook for `token` when the caller in `context` may resume it: the actor in
 * its `hookMetadata`, or a member of its tenant whom `can` grants its
 * permission. Throws `HookForbiddenError` otherwise, so a leaked token alone
 * never resumes a run.
 */
export async function authorizeHook(
  token: string,
  context: RequestContext,
  options: AuthorizeHookOptions = {},
): Promise<Hook> {
  const hook = await getHookByToken(token);
  const metadata: unknown = await hook.metadata;
  const actor = context.actor?.kind === "user" ? context.actor.id : undefined;
  const owner = stringField(metadata, WORKFLOW_ATTRIBUTES.actor);

  if (actor !== undefined && owner === actor) {
    return hook;
  }

  const tenant = stringField(metadata, WORKFLOW_ATTRIBUTES.tenant);
  const permission = stringField(metadata, "bsb.permission");

  if (
    actor !== undefined &&
    tenant !== undefined &&
    permission !== undefined &&
    options.can !== undefined &&
    (await options.can(tenant, permission))
  ) {
    return hook;
  }

  throw new HookForbiddenError(
    "better-supabase: the caller may not resume this workflow hook",
  );
}

/** Whether `type` matches `pattern` (`invoice.paid`, `organization.*` or `*`). */
function matches(pattern: string, type: string): boolean {
  if (pattern === "*" || pattern === type) {
    return true;
  }

  return pattern.endsWith(".*") && type.startsWith(pattern.slice(0, -1));
}

export interface StartOnEventOptions<TArgs extends unknown[]> {
  /** Type patterns such as `invoice.paid` or `organization.*`. */
  readonly types: readonly string[];
  /**
   * The workflow's arguments for an event. Defaults to `[event.payload]`.
   * `context` is the event's `workflowContext`, with its ticket.
   */
  readonly args?: (event: OutboxEvent, context: RequestContext) => TArgs;
  /**
   * The opaque ticket for an event's run, stored as `bsb.ticket`; `undefined`
   * for none.
   */
  readonly ticket?: (event: OutboxEvent) => string | undefined;
  /**
   * The publisher each run starts as. The event's actor is recorded as
   * `bsb.trigger` and grants nothing; `null` for an event starts nothing.
   */
  readonly runAs: WorkflowRunAsFor<OutboxEvent>;
  readonly world?: World;
}

/**
 * An outbox handler (`outbox.consume(name, handler)`) that starts `workflow`
 * for each matching event, as its `runAs` publisher in the event's tenant,
 * keyed by `event:{id}` so a redelivered batch starts nothing twice.
 */
export function startOnEvent<TArgs extends unknown[]>(
  workflow: WorkflowFn<TArgs>,
  options: StartOnEventOptions<TArgs>,
): OutboxHandler {
  return async (events) => {
    for (const event of events) {
      if (!options.types.some((pattern) => matches(pattern, event.type))) {
        continue;
      }

      const runAs = await resolveRunAs(options.runAs, event);

      if (runAs === undefined) {
        continue;
      }

      const { context, attributes, trusted } = runAsStart(runAs, {
        tenant: event.tenant ?? undefined,
        trigger: event.actorId ?? undefined,
        ticket: options.ticket?.(event),
      });

      // SAFETY: without `args`, the workflow takes the event payload as its one argument.
      const args = options.args?.(event, context) ?? ([event.payload] as TArgs);
      await startRun(
        context,
        workflow,
        args,
        {
          idempotencyKey: `event:${event.id}`,
          attributes,
          ...(options.world === undefined ? {} : { world: options.world }),
        },
        trusted,
      );
    }
  };
}

export interface ProtectWebHandlerOptions {
  /**
   * Whether the request's caller holds `permission`: resolve the session
   * (`server.context(request)`) and check it, e.g. with `member_can`. Return
   * `undefined` when there is no session (401).
   */
  readonly can: (
    request: Request,
    permission: string,
  ) => boolean | undefined | Promise<boolean | undefined>;
}

function problem(status: 401 | 403): Response {
  return Response.json(
    {
      type: "about:blank",
      title: status === 401 ? "Unauthorized" : "Forbidden",
      status,
    },
    { status, headers: { "content-type": "application/problem+json" } },
  );
}

/**
 * Puts a route of the workflow web UI or a run's stream behind `permission`:
 * answers 401 without a session and 403 without the permission, as
 * `application/problem+json`.
 */
export function protectWebHandler(
  handler: (request: Request) => Response | Promise<Response>,
  permission: string,
  options: ProtectWebHandlerOptions,
): (request: Request) => Promise<Response> {
  return async (request) => {
    const allowed = await options.can(request, permission);

    if (allowed === undefined) {
      return problem(401);
    }

    if (!allowed) {
      return problem(403);
    }

    return handler(request);
  };
}
