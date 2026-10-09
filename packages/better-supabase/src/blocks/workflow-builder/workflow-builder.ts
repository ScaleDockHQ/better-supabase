import type { BlockTransport } from "../../core/block-transport.ts";
import type {
  CredentialProvider,
  CredentialRef,
  CredentialToken,
} from "../../credentials/provider.ts";
import type {
  WorkflowStartCall,
  WorkflowStarter,
} from "../workflows/workflows.ts";

import { dbError, type ErrorMapper } from "../../core/errors.ts";
import { AsyncResult, err, ok } from "../../core/result.ts";
import {
  credentialRefInTenant,
  foreignCredentialRef,
} from "../../credentials/provider.ts";
import {
  applyTemporal,
  blockCall,
  enumOrThrow,
  type BlockTemporalOptions,
  isRecord,
  optionalInstant,
  optionalText,
  randomToken,
  recordOf,
  recordOrEmpty,
  recordsOf,
  requiredInstant,
  seconds,
  stringsOf,
  textOf,
  injectableOf,
} from "../shared.ts";
import {
  createWorkflows,
  type WorkflowSchedule,
} from "../workflows/workflows.ts";
import {
  diffGraphs,
  graphOf,
  type WorkflowGraph,
  type WorkflowGraphDiff,
} from "./graph.ts";

export type WorkflowVersionStatus = "draft" | "published" | "archived";

export type WorkflowTriggerKind =
  | "manual"
  | "webhook"
  | "schedule"
  | "event"
  | "form"
  | "chat";

export type WorkflowNodeRunStatus =
  | "running"
  | "waiting"
  | "completed"
  | "failed"
  | "skipped";

export interface WorkflowDefinition {
  readonly id: string;
  readonly tenant: string | undefined;
  readonly slug: string;
  readonly name: string;
  readonly description: string | undefined;
  readonly createdBy: string | undefined;
  readonly createdAt: Temporal.Instant;
  readonly updatedAt: Temporal.Instant;
  /** The published version's number (lists only). */
  readonly published?: number | undefined;
  /** Whether a draft is open (lists only). */
  readonly draft?: boolean;
}

export interface WorkflowVersion {
  readonly id: string;
  readonly definition: string;
  readonly version: number;
  readonly status: WorkflowVersionStatus;
  readonly createdBy: string | undefined;
  readonly createdAt: Temporal.Instant;
  readonly publishedAt: Temporal.Instant | undefined;
  /** Set by `get`, `save` and `publish`; lists leave it out. */
  readonly graph?: WorkflowGraph;
  /** What the engine's `compile` returned on publish. */
  readonly compiled?: unknown;
}

export interface WorkflowTrigger {
  readonly id: string;
  readonly definition: string;
  readonly kind: WorkflowTriggerKind;
  /**
   * `schedule`: `{ cron, timezone?, input? }`; `event`: `{ type }`; `form`:
   * `{ schema }`; the others are the app's.
   */
  readonly config: Readonly<Record<string, unknown>>;
  readonly enabled: boolean;
  readonly createdAt: Temporal.Instant;
  readonly updatedAt: Temporal.Instant;
}

/** A credential a tenant's steps use, by reference: the row never holds the secret. */
export interface WorkflowCredential {
  readonly id: string;
  readonly tenant: string | undefined;
  /** What it is for, matched against a step's `credentialKind`. */
  readonly kind: string;
  readonly name: string;
  readonly ref: CredentialRef;
  readonly scopes: readonly string[];
  readonly createdBy: string | undefined;
  readonly createdAt: Temporal.Instant;
}

/** A step the deployment provides, as the builder's palette shows it. */
export interface WorkflowStepInfo {
  readonly name: string;
  readonly title: string;
  readonly description?: string | undefined;
  /** JSON Schema of the node's config. */
  readonly inputSchema?: Readonly<Record<string, unknown>>;
  readonly outputSchema?: Readonly<Record<string, unknown>>;
  /** The credential kind the step resolves, when it needs one. */
  readonly credentialKind?: string | undefined;
}

export interface WorkflowNodeRun {
  readonly run: string;
  readonly node: string;
  readonly status: WorkflowNodeRunStatus;
  readonly attempts: number;
  readonly output: unknown;
  readonly error: string | undefined;
  readonly startedAt: Temporal.Instant | undefined;
  readonly endedAt: Temporal.Instant | undefined;
}

export interface WorkflowAlert {
  readonly id: string;
  readonly definition: string;
  readonly onEvent: "failed" | "slow";
  /** Seconds a run may stay unfinished (slow alerts). */
  readonly threshold: number | undefined;
  /** Where the app sends it, e.g. `{ type: "email", to }`; the module only stores it. */
  readonly channel: Readonly<Record<string, unknown>>;
  readonly createdBy: string | undefined;
  readonly createdAt: Temporal.Instant;
}

/** What `start` gets to start a run of a published version. */
export interface BuilderStartCall {
  readonly definition: WorkflowDefinition;
  /** The published version, with its graph and compiled form. */
  readonly version: WorkflowVersion;
  readonly input: unknown;
  readonly tenant: string | undefined;
  readonly actor: string | undefined;
  /** Pass to the engine so a repeated start returns the same run. */
  readonly idempotencyKey: string;
  /** The trigger that started it, when one did. */
  readonly trigger?: WorkflowTrigger;
}

/** Starts a run with the engine and returns the engine's run id. */
export type BuilderStarter = ((call: BuilderStartCall) => Promise<string>) & {
  /** The starter contract version. Omitted means 1. */
  readonly apiVersion?: 1;
};

/** The engine's compiled form of a graph, stored with the version on publish. */
export type GraphCompiler = ((graph: WorkflowGraph) => unknown) & {
  /** The compiler contract version. Omitted means 1. */
  readonly apiVersion?: 1;
};

export interface BuilderOptions extends BlockTemporalOptions {
  /** The caller's transport: RLS and the module's permissions apply. */
  readonly transport: BlockTransport;
  /**
   * A service-role transport for the calls only the server makes: webhook
   * and event targets, `credentials.resolve`, `nodeRuns.record`,
   * `steps.sync` and `alerts.check`. Defaults to `transport`.
   */
  readonly service?: BlockTransport;
  /** The module schema (`sql.modules.workflow-builder.schema`), default `better_supabase`. */
  readonly schema?: string;
  readonly mappers?: readonly ErrorMapper[];
  /** The steps `steps.sync()` writes to the library. */
  readonly steps?: readonly WorkflowStepInfo[];
  /**
   * Runs on publish and fails it when it throws; the result is stored
   * through `service`. `better-supabase/workflow-sdk/builder` exports `compileGraph`.
   */
  readonly compile?: GraphCompiler;
  /** Starts runs; `better-supabase/workflow-sdk/builder` exports `graphStarter`. */
  readonly start?: BuilderStarter;
  /** The providers credential rows resolve through, picked by `ref.provider`. */
  readonly credentials?: CredentialProvider | readonly CredentialProvider[];
}

export interface DefinitionInput {
  readonly tenant?: string;
  /** Lowercase letters, digits and dashes; saving the same slug again renames it. */
  readonly slug: string;
  readonly name: string;
  readonly description?: string;
}

export interface TriggerInput {
  readonly definition: string;
  readonly kind: WorkflowTriggerKind;
  readonly config?: Readonly<Record<string, unknown>>;
  readonly enabled?: boolean;
  /** Updates this trigger instead of creating one. */
  readonly id?: string;
}

export interface CredentialInput {
  readonly tenant?: string;
  readonly kind: string;
  readonly name: string;
  readonly ref: CredentialRef;
  readonly scopes?: readonly string[];
  /** Stores the secret first, through a provider that can (`vaultCredentials` can). */
  readonly secret?: string;
}

export interface AlertInput {
  readonly definition: string;
  readonly onEvent: "failed" | "slow";
  readonly channel?: Readonly<Record<string, unknown>>;
  /** Seconds a run may stay unfinished (slow alerts). */
  readonly threshold?: number;
  readonly id?: string;
}

export interface NodeRunRecord {
  /** The run's id or its engine's id. */
  readonly run: string;
  readonly node: string;
  readonly status: WorkflowNodeRunStatus;
  readonly attempt?: number;
  readonly output?: unknown;
  readonly error?: string;
}

export interface RunInput {
  readonly definition: string;
  readonly input?: unknown;
  /** Defaults to a fresh key, so every call starts a run. */
  readonly idempotencyKey?: string;
  readonly actor?: string;
}

export interface OutboxLikeEvent {
  readonly id: string;
  readonly type: string;
  readonly payload?: unknown;
  readonly tenant?: string | undefined;
}

export interface WorkflowBuilder {
  readonly definitions: {
    save(input: DefinitionInput): AsyncResult<WorkflowDefinition>;
    list(tenant?: string): AsyncResult<readonly WorkflowDefinition[]>;
    get(id: string): AsyncResult<WorkflowDefinition | undefined>;
    remove(id: string): AsyncResult<boolean>;
  };
  readonly versions: {
    /** Saves the draft: updates the open one, or opens the next version. */
    save(
      definition: string,
      graph: WorkflowGraph,
    ): AsyncResult<WorkflowVersion>;
    /**
     * Compiles the graph with `compile`, then publishes as the caller; the
     * previous version is archived. The compiled form is stored through
     * `service` only, and not at all without it.
     */
    publish(version: string): AsyncResult<WorkflowVersion>;
    list(definition: string): AsyncResult<readonly WorkflowVersion[]>;
    get(version: string): AsyncResult<WorkflowVersion | undefined>;
    diff(from: string, to: string): AsyncResult<WorkflowGraphDiff>;
  };
  /** Starts a run of the published version: `workflow.run` in its tenant. */
  run(input: RunInput): AsyncResult<string>;
  readonly triggers: {
    save(input: TriggerInput): AsyncResult<WorkflowTrigger>;
    list(definition: string): AsyncResult<readonly WorkflowTrigger[]>;
    remove(id: string): AsyncResult<boolean>;
    /** A new token for a webhook trigger; the old one stops working. Shown once. */
    rotateToken(id: string): AsyncResult<string>;
    /**
     * A route handler for webhook triggers: the token is the last path
     * segment or a `Bearer` header, the JSON body is the input, and an
     * `Idempotency-Key` header keys the start. Answers 202 with `{ runId }`.
     */
    webhook(request: Request): Promise<Response>;
    /** Starts the definitions whose event triggers listen for `event.type`. */
    onEvent(event: OutboxLikeEvent): AsyncResult<readonly string[]>;
    /**
     * Creates or updates the `workflows` schedule of a schedule trigger (its
     * `config.cron`), named `builder-trigger:<id>`. Uses `service`.
     */
    syncSchedule(
      trigger: WorkflowTrigger,
      tenant?: string,
    ): AsyncResult<WorkflowSchedule>;
    /**
     * The `start` for `workflows.schedules.tick`: starts `builder:<definition>`
     * schedules here and passes the others to `fallback`.
     */
    starter(fallback?: WorkflowStarter): WorkflowStarter;
  };
  readonly credentials: {
    list(tenant?: string): AsyncResult<readonly WorkflowCredential[]>;
    create(input: CredentialInput): AsyncResult<WorkflowCredential>;
    /** The URL that connects the account, for providers that authorize. */
    authorize(
      id: string,
      options: { readonly redirectUri: string; readonly state?: string },
    ): AsyncResult<string>;
    /** Deletes the row, then revokes the secret it names. */
    revoke(id: string): AsyncResult<boolean>;
    /** The token for a credential, with the app subject and the row's scopes (service role; call it inside a step). */
    resolve(id: string): AsyncResult<CredentialToken>;
  };
  readonly steps: {
    /** Replaces the library with `steps` (service role). */
    sync(steps?: readonly WorkflowStepInfo[]): AsyncResult<number>;
    list(): AsyncResult<readonly WorkflowStepInfo[]>;
  };
  readonly nodeRuns: {
    /** Records a node's status and pings `workflow-run:<id>` (service role). */
    record(input: NodeRunRecord): AsyncResult<boolean>;
    list(run: string): AsyncResult<readonly WorkflowNodeRun[]>;
  };
  readonly alerts: {
    save(input: AlertInput): AsyncResult<WorkflowAlert>;
    list(definition: string): AsyncResult<readonly WorkflowAlert[]>;
    remove(id: string): AsyncResult<boolean>;
    /** Fires the slow alerts that are due (service role); returns how many fired. */
    check(options?: { readonly batch?: number }): AsyncResult<number>;
  };
}

const VERSION_STATUSES: readonly WorkflowVersionStatus[] = [
  "draft",
  "published",
  "archived",
];
const TRIGGER_KINDS: readonly WorkflowTriggerKind[] = [
  "manual",
  "webhook",
  "schedule",
  "event",
  "form",
  "chat",
];
const NODE_RUN_STATUSES: readonly WorkflowNodeRunStatus[] = [
  "running",
  "waiting",
  "completed",
  "failed",
  "skipped",
];

export function definitionOf(row: Record<string, unknown>): WorkflowDefinition {
  const published = row["published"];
  return {
    id: textOf(row["id"]),
    tenant: optionalText(row["tenant"]),
    slug: textOf(row["slug"]),
    name: textOf(row["name"]),
    description: optionalText(row["description"]),
    createdBy: optionalText(row["createdBy"]),
    createdAt: requiredInstant(row["createdAt"], "createdAt"),
    updatedAt: requiredInstant(row["updatedAt"], "updatedAt"),
    ...("published" in row
      ? { published: typeof published === "number" ? published : undefined }
      : {}),
    ...("draft" in row ? { draft: row["draft"] === true } : {}),
  };
}

export function versionOf(row: Record<string, unknown>): WorkflowVersion {
  return {
    id: textOf(row["id"]),
    definition: textOf(row["definition"]),
    version: Number(row["version"]),
    status: enumOrThrow(row["status"], VERSION_STATUSES, "version status"),
    createdBy: optionalText(row["createdBy"]),
    createdAt: requiredInstant(row["createdAt"], "createdAt"),
    publishedAt: optionalInstant(row["publishedAt"]),
    ...("graph" in row ? { graph: graphOf(row["graph"]) } : {}),
    ...("compiled" in row && row["compiled"] !== null
      ? { compiled: row["compiled"] }
      : {}),
  };
}

export function triggerOf(row: Record<string, unknown>): WorkflowTrigger {
  return {
    id: textOf(row["id"]),
    definition: textOf(row["definition"]),
    kind: enumOrThrow(row["kind"], TRIGGER_KINDS, "trigger kind"),
    config: recordOrEmpty(row["config"]),
    enabled: row["enabled"] !== false,
    createdAt: requiredInstant(row["createdAt"], "createdAt"),
    updatedAt: requiredInstant(row["updatedAt"], "updatedAt"),
  };
}

function refOf(value: unknown): CredentialRef {
  if (!isRecord(value) || typeof value["provider"] !== "string") {
    throw new TypeError("workflow-builder: a credential_ref has no provider");
  }
  return { ...value, provider: value["provider"] };
}

export function credentialOf(row: Record<string, unknown>): WorkflowCredential {
  return {
    id: textOf(row["id"]),
    tenant: optionalText(row["tenant"]),
    kind: textOf(row["kind"]),
    name: textOf(row["name"]),
    ref: refOf(row["ref"]),
    scopes: Array.isArray(row["scopes"]) ? stringsOf(row["scopes"]) : [],
    createdBy: optionalText(row["createdBy"]),
    createdAt: requiredInstant(row["createdAt"], "createdAt"),
  };
}

function stepOf(row: Record<string, unknown>): WorkflowStepInfo {
  return {
    name: textOf(row["name"]),
    title: textOf(row["title"]),
    description: optionalText(row["description"]),
    inputSchema: recordOrEmpty(row["inputSchema"]),
    outputSchema: recordOrEmpty(row["outputSchema"]),
    credentialKind: optionalText(row["credentialKind"]),
  };
}

export function nodeRunOf(row: Record<string, unknown>): WorkflowNodeRun {
  return {
    run: textOf(row["run"]),
    node: textOf(row["node"]),
    status: enumOrThrow(row["status"], NODE_RUN_STATUSES, "node status"),
    attempts: Number(row["attempts"] ?? 0),
    output: row["output"] ?? undefined,
    error: optionalText(row["error"]),
    startedAt: optionalInstant(row["startedAt"]),
    endedAt: optionalInstant(row["endedAt"]),
  };
}

function alertOf(row: Record<string, unknown>): WorkflowAlert {
  const threshold = row["threshold"];
  return {
    id: textOf(row["id"]),
    definition: textOf(row["definition"]),
    onEvent: row["onEvent"] === "slow" ? "slow" : "failed",
    threshold:
      threshold === null || threshold === undefined
        ? undefined
        : Number(threshold),
    channel: recordOrEmpty(row["channel"]),
    createdBy: optionalText(row["createdBy"]),
    createdAt: requiredInstant(row["createdAt"], "createdAt"),
  };
}

const optionalOf =
  <T>(map: (row: Record<string, unknown>) => T) =>
  (value: unknown): T | undefined =>
    isRecord(value) ? map(value) : undefined;

const BUILDER_PREFIX = "builder:";

/**
 * The `workflow-builder` module's definitions, versions, triggers,
 * credentials, step library, node runs and alerts. The engine plugs in
 * through `compile` and `start`; credential rows resolve through the
 * `credentials` providers.
 *
 * ```ts
 * const builder = createBuilder({
 *   transport: rpcTransport(supabase),
 *   compile: compileGraph,
 *   start: graphStarter({ executor: builderWorkflow, steps: { runNode } }),
 * });
 * ```
 */
export function createBuilder(options: BuilderOptions): WorkflowBuilder {
  applyTemporal(options);
  injectableOf("workflow-builder compiler", options.compile);
  injectableOf("workflow-builder starter", options.start);
  const call = blockCall(options.transport, options.schema, options.mappers);
  const serviceCall = blockCall(
    options.service ?? options.transport,
    options.schema,
    options.mappers,
  );
  const providers: readonly CredentialProvider[] =
    options.credentials === undefined
      ? []
      : Array.isArray(options.credentials)
        ? options.credentials
        : [options.credentials];
  const providerFor = (ref: CredentialRef): CredentialProvider | undefined =>
    providers.find((provider) => provider.name === ref.provider);
  const noProvider = (ref: CredentialRef) =>
    dbError(
      "invalid_request",
      `No credential provider named "${ref.provider}" was passed to createBuilder`,
    );

  const getVersion = (version: string) =>
    call("workflow_version_get", { version }, optionalOf(versionOf));

  const startTarget = (
    caller: typeof call,
    definition: string,
    start: (target: {
      definition: WorkflowDefinition;
      version: WorkflowVersion;
    }) => Promise<string>,
  ): AsyncResult<string> =>
    caller("workflow_start_target", { definition }, (value) =>
      recordOf(value, "workflow_start_target"),
    ).andThen(async (row) => {
      const target = {
        definition: definitionOf(recordOf(row["definition"], "definition")),
        version: versionOf(recordOf(row["version"], "version")),
      };
      return ok(await start(target));
    });

  const starterOf = (): BuilderStarter | undefined => options.start;
  const missingStarter = () =>
    dbError(
      "invalid_request",
      "Pass `start` to createBuilder to run workflows",
    );

  const runWith = (
    caller: typeof call,
    input: RunInput & { readonly trigger?: WorkflowTrigger },
  ): AsyncResult<string> => {
    const start = starterOf();
    if (start === undefined) return AsyncResult.err(missingStarter());
    return startTarget(caller, input.definition, (target) =>
      start({
        definition: target.definition,
        version: target.version,
        input: input.input ?? {},
        tenant: target.definition.tenant,
        actor: input.actor,
        idempotencyKey: input.idempotencyKey ?? `run:${randomToken(16)}`,
        ...(input.trigger === undefined ? {} : { trigger: input.trigger }),
      }),
    );
  };

  const credentialRow = (id: string) =>
    serviceCall("workflow_credential_get", { credential: id }, (value) =>
      isRecord(value) ? credentialOf(value) : undefined,
    );

  const builder: WorkflowBuilder = {
    definitions: {
      save: (input) =>
        call(
          "save_workflow_definition",
          {
            tenant: input.tenant,
            slug: input.slug,
            name: input.name,
            description: input.description,
          },
          (value) => definitionOf(recordOf(value, "save_workflow_definition")),
        ),
      list: (tenant) =>
        call("workflow_definitions_list", { tenant }, (value) =>
          recordsOf(value, "workflow_definitions_list").map(definitionOf),
        ),
      get: (id) =>
        call(
          "workflow_definition_get",
          { definition: id },
          optionalOf(definitionOf),
        ),
      remove: (id) =>
        call(
          "remove_workflow_definition",
          { definition: id },
          (value) => value === true,
        ),
    },
    versions: {
      save: (definition, graph) =>
        call("save_workflow_draft", { definition, graph }, (value) =>
          versionOf(recordOf(value, "save_workflow_draft")),
        ),
      publish: (version) =>
        getVersion(version).andThen(async (found) => {
          if (found === undefined) {
            return err(dbError("not_found", "No such workflow version"));
          }
          let compiled: unknown = null;
          if (options.compile !== undefined && found.status !== "published") {
            try {
              compiled =
                (await options.compile(found.graph ?? graphOf(undefined))) ??
                null;
            } catch (cause) {
              return err(
                dbError(
                  "invalid_input",
                  cause instanceof Error ? cause.message : String(cause),
                ),
              );
            }
          }
          const publish = (caller: typeof call, stored: unknown) =>
            caller(
              "publish_workflow_version",
              { version, compiled: stored },
              (value) => versionOf(recordOf(value, "publish_workflow_version")),
            );
          const result = await publish(call, null);
          if (
            !result.ok ||
            compiled === null ||
            options.service === undefined
          ) {
            return result;
          }
          return publish(serviceCall, compiled);
        }),
      list: (definition) =>
        call("workflow_versions_list", { definition }, (value) =>
          recordsOf(value, "workflow_versions_list").map(versionOf),
        ),
      get: getVersion,
      diff: (from, to) =>
        getVersion(from).andThen(async (before) => {
          const after = await getVersion(to);
          if (!after.ok) return after;
          if (before === undefined || after.data === undefined) {
            return err(dbError("not_found", "No such workflow version"));
          }
          return ok(
            diffGraphs(
              before.graph ?? graphOf(undefined),
              after.data.graph ?? graphOf(undefined),
            ),
          );
        }),
    },
    run: (input) => runWith(call, input),
    triggers: {
      save: (input) =>
        call(
          "save_workflow_trigger",
          {
            definition: input.definition,
            kind: input.kind,
            config: input.config ?? {},
            enabled: input.enabled ?? true,
            trigger: input.id,
          },
          (value) => triggerOf(recordOf(value, "save_workflow_trigger")),
        ),
      list: (definition) =>
        call("workflow_triggers_list", { definition }, (value) =>
          recordsOf(value, "workflow_triggers_list").map(triggerOf),
        ),
      remove: (id) =>
        call(
          "remove_workflow_trigger",
          { trigger: id },
          (value) => value === true,
        ),
      rotateToken: (id) =>
        call("rotate_workflow_webhook_token", { trigger: id }, textOf),
      webhook: async (request) => {
        if (request.method !== "POST") {
          return Response.json(
            { error: "Method not allowed" },
            { status: 405, headers: { allow: "POST" } },
          );
        }
        const token = webhookToken(request);
        if (token === undefined) {
          return Response.json({ error: "Not found" }, { status: 404 });
        }
        const target = await serviceCall(
          "workflow_webhook_target",
          { token },
          (value) => (isRecord(value) ? value : undefined),
        );
        if (!target.ok) {
          return Response.json(
            { error: target.error.message },
            { status: 500 },
          );
        }
        if (target.data === undefined) {
          return Response.json({ error: "Not found" }, { status: 404 });
        }
        const trigger = triggerOf(recordOf(target.data["trigger"], "trigger"));
        const key = request.headers.get("idempotency-key");
        const started = await runWith(serviceCall, {
          definition: trigger.definition,
          input: await bodyOf(request),
          idempotencyKey:
            key === null || key.length === 0
              ? `webhook:${trigger.id}:${randomToken(16)}`
              : `webhook:${trigger.id}:${key}`,
          trigger,
        });
        return started.ok
          ? Response.json({ runId: started.data }, { status: 202 })
          : Response.json(
              { error: started.error.message },
              { status: started.error.status },
            );
      },
      onEvent: (event) =>
        serviceCall(
          "workflow_event_targets",
          { type: event.type, tenant: event.tenant },
          (value) => recordsOf(value, "workflow_event_targets"),
        ).andThen(async (rows) => {
          const runs: string[] = [];
          for (const row of rows) {
            const trigger = triggerOf(recordOf(row["trigger"], "trigger"));
            const started = await runWith(serviceCall, {
              definition: trigger.definition,
              input: event.payload ?? {},
              idempotencyKey: `event:${trigger.id}:${event.id}`,
              trigger,
            });
            if (!started.ok) return started;
            runs.push(started.data);
          }
          return ok(runs);
        }),
      syncSchedule: (trigger, tenant) => {
        const cron = trigger.config["cron"];
        if (trigger.kind !== "schedule" || typeof cron !== "string") {
          return AsyncResult.err(
            dbError(
              "invalid_input",
              "Only a schedule trigger with config.cron has a schedule",
            ),
          );
        }
        const timezone = trigger.config["timezone"];
        const workflows = createWorkflows({
          transport: options.service ?? options.transport,
          ...(options.mappers === undefined
            ? {}
            : { mappers: options.mappers }),
        });
        return workflows.schedules.create({
          name: `builder-trigger:${trigger.id}`,
          workflow: `${BUILDER_PREFIX}${trigger.definition}`,
          cron,
          ...(typeof timezone === "string" ? { timezone } : {}),
          input: trigger.config["input"] ?? {},
          ...(tenant === undefined ? {} : { tenant }),
        });
      },
      starter: (fallback) => async (scheduled: WorkflowStartCall) => {
        if (!scheduled.workflow.startsWith(BUILDER_PREFIX)) {
          if (fallback === undefined) {
            throw new Error(
              `better-supabase: no starter for workflow "${scheduled.workflow}"`,
            );
          }
          return fallback(scheduled);
        }
        return runWith(serviceCall, {
          definition: scheduled.workflow.slice(BUILDER_PREFIX.length),
          input: scheduled.input,
          idempotencyKey: scheduled.idempotencyKey,
          ...(scheduled.actor === undefined ? {} : { actor: scheduled.actor }),
        }).orThrow();
      },
    },
    credentials: {
      list: (tenant) =>
        call("workflow_credentials_list", { tenant }, (value) =>
          recordsOf(value, "workflow_credentials_list").map(credentialOf),
        ),
      create: (input) => {
        const save = () =>
          call(
            "save_workflow_credential",
            {
              tenant: input.tenant,
              kind: input.kind,
              name: input.name,
              ref: input.ref,
              scopes: input.scopes ?? [],
            },
            (value) =>
              credentialOf(recordOf(value, "save_workflow_credential")),
          );
        if (input.secret === undefined) return save();
        if (!credentialRefInTenant(input.ref, input.tenant)) {
          return AsyncResult.err(foreignCredentialRef(input.tenant));
        }
        const provider = providerFor(input.ref);
        if (provider === undefined) {
          return AsyncResult.err(noProvider(input.ref));
        }
        if (provider.set === undefined) {
          return AsyncResult.err(
            dbError(
              "unsupported",
              `The credential provider "${provider.name}" can't store secrets`,
            ),
          );
        }
        return provider
          .set(input.ref, input.secret, { subject: { type: "app" } })
          .andThen(() => save());
      },
      authorize: (id, authorize) =>
        credentialRow(id).andThen(async (row) => {
          if (row === undefined) {
            return err(dbError("not_found", "No such credential"));
          }
          const provider = providerFor(row.ref);
          if (provider === undefined) return err(noProvider(row.ref));
          if (
            provider.startAuthorization === undefined ||
            !provider.capabilities(row.ref).authorization
          ) {
            return err(
              dbError(
                "unsupported",
                `The credential provider "${provider.name}" doesn't authorize accounts`,
              ),
            );
          }
          return provider
            .startAuthorization(row.ref, {
              subject: { type: "app" },
              redirectUri: authorize.redirectUri,
              scopes: row.scopes,
              ...(authorize.state === undefined
                ? {}
                : { state: authorize.state }),
            })
            .map((started) => started.url);
        }),
      revoke: (id) =>
        call("remove_workflow_credential", { credential: id }, (value) =>
          isRecord(value) ? credentialOf(value) : undefined,
        ).andThen(async (row) => {
          if (row === undefined) return ok(false);
          if (!credentialRefInTenant(row.ref, row.tenant)) return ok(true);
          const provider = providerFor(row.ref);
          if (provider === undefined) return err(noProvider(row.ref));
          if (!provider.capabilities(row.ref).revoke) return ok(true);
          const revoked = await provider.revoke(row.ref, {
            subject: { type: "app" },
          });
          return revoked.ok ? ok(true) : revoked;
        }),
      resolve: (id) =>
        credentialRow(id).andThen(async (row) => {
          if (row === undefined) {
            return err(dbError("not_found", "No such credential"));
          }
          if (!credentialRefInTenant(row.ref, row.tenant)) {
            return err(foreignCredentialRef(row.tenant));
          }
          const provider = providerFor(row.ref);
          if (provider === undefined) return err(noProvider(row.ref));
          return provider.getToken(row.ref, {
            subject: { type: "app" },
            scopes: row.scopes,
          });
        }),
    },
    steps: {
      sync: (steps = options.steps ?? []) =>
        serviceCall(
          "sync_workflow_steps",
          {
            steps: Object.fromEntries(
              steps.map((step) => [
                step.name,
                {
                  title: step.title,
                  description: step.description,
                  inputSchema: step.inputSchema ?? {},
                  outputSchema: step.outputSchema ?? {},
                  credentialKind: step.credentialKind,
                },
              ]),
            ),
          },
          Number,
        ),
      list: () =>
        call("workflow_steps_list", {}, (value) =>
          recordsOf(value, "workflow_steps_list").map(stepOf),
        ),
    },
    nodeRuns: {
      record: (input) =>
        serviceCall(
          "record_workflow_node_run",
          {
            run: input.run,
            node: input.node,
            status: input.status,
            attempt: input.attempt,
            output: input.output,
            error: input.error,
          },
          (value) => value === true,
        ),
      list: (run) =>
        call("workflow_node_runs_list", { run }, (value) =>
          recordsOf(value, "workflow_node_runs_list").map(nodeRunOf),
        ),
    },
    alerts: {
      save: (input) =>
        call(
          "save_workflow_alert",
          {
            definition: input.definition,
            on_event: input.onEvent,
            channel: input.channel ?? {},
            threshold:
              input.threshold === undefined
                ? undefined
                : seconds(input.threshold),
            alert: input.id,
          },
          (value) => alertOf(recordOf(value, "save_workflow_alert")),
        ),
      list: (definition) =>
        call("workflow_alerts_list", { definition }, (value) =>
          recordsOf(value, "workflow_alerts_list").map(alertOf),
        ),
      remove: (id) =>
        call("remove_workflow_alert", { alert: id }, (value) => value === true),
      check: (check = {}) =>
        serviceCall("check_workflow_alerts", { batch: check.batch }, Number),
    },
  };
  return builder;
}

function webhookToken(request: Request): string | undefined {
  const header = request.headers.get("authorization");
  if (header !== null && /^bearer\s+/i.test(header)) {
    const token = header.replace(/^bearer\s+/i, "").trim();
    return token.length > 0 ? token : undefined;
  }
  const segment = new URL(request.url).pathname.split("/").findLast(Boolean);
  return segment?.startsWith("wfh_") === true
    ? decodeURIComponent(segment)
    : undefined;
}

async function bodyOf(request: Request): Promise<unknown> {
  const text = await request.text();
  if (text.length === 0) return {};
  try {
    const parsed: unknown = JSON.parse(text);
    return parsed;
  } catch {
    return { body: text };
  }
}
