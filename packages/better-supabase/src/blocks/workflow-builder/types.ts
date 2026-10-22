import type { ExtraFields, FieldsOf } from "../../core/block-fields.ts";
import type { BlockHooks } from "../../core/block-hooks.ts";
import type { BlockTransport } from "../../core/block-transport.ts";
import type { AuthorizationHooks } from "../../core/contracts/authorization-hooks.ts";
import type { ErrorMapper } from "../../core/errors.ts";
import type { Logger } from "../../core/logger.ts";
import type { AsyncResult } from "../../core/result.ts";
import type { StandardSchemaV1 } from "../../core/standard.ts";
import type {
  CredentialProvider,
  CredentialRef,
  CredentialToken,
} from "../../credentials/provider.ts";
import type { BlockTemporalOptions } from "../shared.ts";
import type {
  Workflows,
  WorkflowRunMode,
  WorkflowSchedule,
  WorkflowStarter,
  WorkflowSubject,
} from "../workflows/workflows.ts";
import type { WorkflowGraph, WorkflowGraphDiff } from "./graph.ts";

export type WorkflowVersionStatus = "draft" | "published" | "archived";

export type WorkflowVersionOwner = "user" | "organization";

export type WorkflowTriggerKind =
  | "manual"
  | "webhook"
  | "schedule"
  | "event"
  | "form"
  | "chat";

/**
 * `tenant`: belongs to one organization. `system`: the app's, with no tenant;
 * every organization can run it, fork it or opt out of it.
 */
export type WorkflowDefinitionScope = "tenant" | "system";

/** Who a definition grant is for: a user id, a team id or an organization role. */
export type WorkflowGrantPrincipal = "user" | "team" | "role";

/** `edit` implies `run`. */
export type WorkflowGrantAction = "run" | "edit";

export type WorkflowNodeRunStatus =
  | "running"
  | "waiting"
  | "completed"
  | "failed"
  | "skipped";

/** A definition. `F` types the extra columns the `fields` schema describes. */
export interface WorkflowDefinition<F extends object = Record<never, never>> {
  readonly id: string;
  readonly tenant: string | undefined;
  readonly slug: string;
  readonly name: string;
  readonly description: string | undefined;
  readonly createdBy: string | undefined;
  readonly createdAt: Temporal.Instant;
  readonly updatedAt: Temporal.Instant;
  /**
   * The record types a run can belong to (`run({ subject })`); empty means runs
   * don't take a subject.
   */
  readonly subjectTypes: readonly string[];
  readonly scope: WorkflowDefinitionScope;
  /** The definition it was forked from, while that one exists. */
  readonly forkedFrom: string | undefined;
  /** The source's published version number when it was forked. */
  readonly forkedFromVersion: number | undefined;
  /**
   * Only admins and grant holders may run or edit it; everyone who can read
   * workflows still sees it.
   */
  readonly restricted: boolean;
  /** The published version's number (lists only). */
  readonly published?: number | undefined;
  /** Whether a draft is open (lists only). */
  readonly draft?: boolean;
  /** A fork's source's published version number (lists and `fork`). */
  readonly upstreamVersion?: number | undefined;
  /**
   * Whether the source published a newer version since the fork (lists and
   * `fork`).
   */
  readonly behind?: boolean;
  /** Whether the listed tenant opted out of it (lists with a tenant only). */
  readonly optedOut?: boolean;
  /** The extra columns, keyed by database name. */
  readonly fields: ExtraFields<F>;
}

export interface WorkflowDefinitionGrant {
  readonly id: string;
  readonly definition: string;
  readonly principalKind: WorkflowGrantPrincipal;
  readonly principalId: string;
  readonly action: WorkflowGrantAction;
  readonly createdBy: string | undefined;
  readonly createdAt: Temporal.Instant;
}

export interface WorkflowVersion {
  readonly id: string;
  readonly definition: string;
  readonly version: number;
  readonly status: WorkflowVersionStatus;
  readonly createdBy: string | undefined;
  readonly createdAt: Temporal.Instant;
  readonly publishedAt: Temporal.Instant | undefined;
  /**
   * The user who published it; `undefined` for an organization-owned version or
   * one not published.
   */
  readonly publishedBy: string | undefined;
  /**
   * `user` when a user published it (its steps run as that user),
   * `organization` when the service role did (its steps run as the app's
   * service principal); `undefined` until it is published.
   */
  readonly owner: WorkflowVersionOwner | undefined;
  /** The permissions its step nodes need, stored when it was published. */
  readonly permissions: readonly string[];
  /** Set by `get`, `save` and `publish`; lists leave it out. */
  readonly graph?: WorkflowGraph;
  /** What the engine's `compile` returned on publish. */
  readonly compiled?: unknown;
  /**
   * The JSON Schema of the input a run takes, as `versions.save` stored it; set
   * by `get`, `save` and `publish` when the version has one.
   */
  readonly inputSchema?: Readonly<Record<string, unknown>>;
}

export interface WorkflowTrigger {
  readonly id: string;
  readonly definition: string;
  readonly kind: WorkflowTriggerKind;
  /**
   * `schedule`: `{ cron, timezone?, input? }`; `event`: `{ type }`; `form`: `{
   * schema }`; the others are the app's.
   */
  readonly config: Readonly<Record<string, unknown>>;
  readonly enabled: boolean;
  readonly createdAt: Temporal.Instant;
  readonly updatedAt: Temporal.Instant;
}

/**
 * A credential a tenant's steps use, by reference: the row never holds the
 * secret.
 */
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
  /**
   * The operation a node of this step checks at publish, in place of
   * `workflow.run`: the provider's entry for it, else the name itself as the
   * permission key. The provider's `workflow.node.<step>` entry still takes
   * precedence.
   */
  readonly operation?: string | undefined;
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
  /**
   * Where the app sends it, e.g. `{ type: "email", to }`; the module only
   * stores it.
   */
  readonly channel: Readonly<Record<string, unknown>>;
  readonly createdBy: string | undefined;
  readonly createdAt: Temporal.Instant;
}

/** What `start` gets to start a run of a published version, or a test run. */
export interface BuilderStartCall {
  readonly definition: WorkflowDefinition;
  /**
   * The published version (a test run's may be the draft), with its graph and
   * compiled form.
   */
  readonly version: WorkflowVersion;
  readonly input: unknown;
  /** The tenant the run belongs to; for a system definition, the one it runs in. */
  readonly tenant: string | undefined;
  readonly actor: string | undefined;
  /** Pass to the engine so a repeated start returns the same run. */
  readonly idempotencyKey: string;
  /** The trigger that started it, when one did. */
  readonly trigger?: WorkflowTrigger;
  /** The record the run belongs to. */
  readonly subject?: WorkflowSubject;
  /**
   * `test` for `test()`: steps return their stubs and don't run. Default
   * `live`.
   */
  readonly mode?: WorkflowRunMode;
  /** The trigger node the run starts at, in a graph with several. */
  readonly triggerNode?: string;
  /** A test run's step outputs, by node id. */
  readonly stubs?: Readonly<Record<string, unknown>>;
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

export interface BuilderOptions<
  S extends StandardSchemaV1 | undefined = undefined,
> extends BlockTemporalOptions {
  /**
   * A Standard Schema for the definition's extra columns
   * (`blocks.workflow-builder.options.extraColumns`), keyed by database name.
   * It types and parses them on the `definitions` reads, and validates them on
   * `definitions.save`.
   */
  readonly fields?: S;
  /** `withBlockHooks` hooks around `run`, `test` and the methods of each group. */
  readonly hooks?: NoInfer<WorkflowBuilderHooks<FieldsOf<S>>>;
  /** Receives the errors `after` hooks throw. Default: `console`. */
  readonly logger?: Logger;
  /** The caller's transport: RLS and the module's permissions apply. */
  readonly transport: BlockTransport;
  /**
   * A service-role transport for the calls only the server makes: webhook and
   * event targets, `credentials.resolve`, `nodeRuns.record`, `steps.sync` and
   * `alerts.check`. Defaults to `transport`.
   */
  readonly service?: BlockTransport;
  /**
   * The module schema, or its API schema: `defineBlocks` passes it from
   * `blocks.generated.ts`. Default `better_supabase`.
   */
  readonly schema?: string;
  readonly mappers?: readonly ErrorMapper[];
  /** The steps `steps.sync()` writes to the library. */
  readonly steps?: readonly WorkflowStepInfo[];
  /**
   * Runs on publish and fails it when it throws; the result is stored through
   * `service`. `better-supabase/workflow-sdk/builder` exports `compileGraph`.
   */
  readonly compile?: GraphCompiler;
  /** Starts runs; `better-supabase/workflow-sdk/builder` exports `graphStarter`. */
  readonly start?: BuilderStarter;
  /** The providers credential rows resolve through, picked by `ref.provider`. */
  readonly credentials?: CredentialProvider | readonly CredentialProvider[];
  /**
   * The provider's runtime hooks, usually `server.authorization`.
   * `automation.mayPublish` can refuse a publish, and `automation.runAs` gives
   * the claims `versions.runAs` returns. Without `runAs`, a step runs as the
   * checked publisher (a user, or the tenant's default service principal for an
   * organization-owned version) capped to the stored permissions.
   */
  readonly authorization?: Pick<AuthorizationHooks, "automation">;
  /**
   * The `workflows` port: the workflows block, which `schedules.sync` writes a
   * schedule trigger's schedule to. Build it with a transport that may create
   * schedules, usually the service role. `createBlocks` passes it.
   */
  readonly workflows?: Pick<Workflows, "schedules">;
}

export interface PublishOptions {
  /**
   * The publisher's verified claims, for `authorization.automation.mayPublish`.
   * A publish with `mayPublish` set and no claims is refused.
   */
  readonly claims?: Readonly<Record<string, unknown>>;
}

export interface DefinitionInput<F extends object = Record<never, never>> {
  readonly tenant?: string;
  /**
   * Lowercase letters, digits and dashes; saving the same slug again renames
   * it.
   */
  readonly slug: string;
  readonly name: string;
  readonly description?: string;
  /** The record types its runs can belong to. Left out keeps the stored ones. */
  readonly subjectTypes?: readonly string[];
  /**
   * `system` needs the service role and no tenant. Fixed once created; left out
   * keeps the stored one (`tenant` for a new definition).
   */
  readonly scope?: WorkflowDefinitionScope;
  /** Changing it needs `workflow.admin`. Left out keeps the stored value. */
  readonly restricted?: boolean;
  /** The extra columns to set. */
  readonly fields?: Partial<F>;
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
  /**
   * Stores the secret first, through a provider that can (`vaultCredentials`
   * can).
   */
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
  /**
   * The record the run belongs to: its type must be one of the definition's
   * `subjectTypes`, and the caller must be able to read it when the `subjects`
   * module is installed.
   */
  readonly subject?: WorkflowSubject;
  /**
   * The tenant a system definition runs in; ignored for a tenant's own
   * definition.
   */
  readonly tenant?: string;
}

export interface TestRunInput {
  readonly definition: string;
  /** Defaults to the open draft, else the published version. */
  readonly version?: string;
  /** Defaults to the graph's only trigger node. */
  readonly triggerNode?: string;
  readonly input?: unknown;
  /**
   * What each step node returns, by node id. A step without one returns the
   * example in its `outputSchema` (from the `steps` passed to
   * `createWorkflowBuilder`: the first `examples` entry, else `default`), else
   * `{ stubbed: true }`. An approval node's stub is its decision (default
   * approved).
   */
  readonly stubs?: Readonly<Record<string, unknown>>;
  readonly subject?: WorkflowSubject;
}

export interface GrantInput {
  readonly definition: string;
  readonly principalKind: WorkflowGrantPrincipal;
  readonly principalId: string;
  readonly action: WorkflowGrantAction;
}

export interface OutboxLikeEvent {
  readonly id: string;
  readonly type: string;
  readonly payload?: unknown;
  readonly tenant?: string | undefined;
  readonly actorId?: string | undefined;
  /** A subject event's record; definitions that list its type run on it. */
  readonly subjectType?: string | undefined;
  readonly subjectId?: string | undefined;
}

export interface VersionSaveOptions {
  /**
   * The JSON Schema of the input a run of the version takes. Leave it out to
   * keep the draft's current one; a new draft starts from the previous
   * version's.
   */
  readonly inputSchema?: Readonly<Record<string, unknown>>;
}

/**
 * Hooks for `run` and `test`, and for the methods of each group of
 * `WorkflowBuilder`.
 */
export type WorkflowBuilderHooks<F extends object = Record<never, never>> =
  BlockHooks<Pick<WorkflowBuilder<F>, "run" | "test">> & {
    readonly definitions?: BlockHooks<WorkflowBuilder<F>["definitions"]>;
    readonly versions?: BlockHooks<WorkflowBuilder<F>["versions"]>;
    readonly triggers?: BlockHooks<WorkflowBuilder<F>["triggers"]>;
    readonly credentials?: BlockHooks<WorkflowBuilder<F>["credentials"]>;
    readonly steps?: BlockHooks<WorkflowBuilder<F>["steps"]>;
    readonly nodeRuns?: BlockHooks<WorkflowBuilder<F>["nodeRuns"]>;
    readonly alerts?: BlockHooks<WorkflowBuilder<F>["alerts"]>;
  };

export interface WorkflowBuilder<F extends object = Record<never, never>> {
  readonly definitions: {
    save(input: DefinitionInput<F>): AsyncResult<WorkflowDefinition<F>>;
    /**
     * The tenant's definitions; with a tenant, the system definitions too,
     * marked `optedOut` when it opted out. `subjectType` keeps the ones that
     * run on that record type.
     */
    list(
      tenant?: string,
      filter?: { readonly subjectType?: string },
    ): AsyncResult<readonly WorkflowDefinition<F>[]>;
    get(id: string): AsyncResult<WorkflowDefinition<F> | undefined>;
    remove(id: string): AsyncResult<boolean>;
    /**
     * Copies a system definition's (or the tenant's own) published graph into a
     * new definition in `tenant` as its draft. The fork doesn't opt the tenant
     * out of the source; call `optOut` for that.
     */
    fork(input: {
      readonly source: string;
      readonly tenant: string;
      readonly slug: string;
    }): AsyncResult<WorkflowDefinition<F>>;
    /**
     * Opts a tenant out of a definition, or back in with `optedOut: false`
     * (`workflow.admin`).
     */
    optOut(input: {
      readonly tenant: string;
      readonly definition: string;
      readonly optedOut?: boolean;
    }): AsyncResult<boolean>;
    readonly grants: {
      /** Grants run or edit on a restricted definition (`workflow.admin`). */
      add(input: GrantInput): AsyncResult<boolean>;
      remove(input: GrantInput): AsyncResult<boolean>;
      list(definition: string): AsyncResult<readonly WorkflowDefinitionGrant[]>;
    };
  };
  readonly versions: {
    /** Saves the draft: updates the open one, or opens the next version. */
    save(
      definition: string,
      graph: WorkflowGraph,
      options?: VersionSaveOptions,
    ): AsyncResult<WorkflowVersion>;
    /**
     * Compiles the graph with `compile`, then publishes as the caller; the
     * previous version is archived. The caller must hold every permission the
     * step nodes need (`WORKFLOW_PUBLISHER_FORBIDDEN` otherwise), and
     * `authorization.automation.mayPublish` must allow it when set. The
     * compiled form is stored through `service` only, and not at all without
     * it.
     */
    publish(
      version: string,
      options?: PublishOptions,
    ): AsyncResult<WorkflowVersion>;
    list(definition: string): AsyncResult<readonly WorkflowVersion[]>;
    get(version: string): AsyncResult<WorkflowVersion | undefined>;
    diff(from: string, to: string): AsyncResult<WorkflowGraphDiff>;
    /**
     * The claims a step of `version` runs with (through `service`): the
     * publisher's (a user, or the tenant's default service principal), narrowed
     * to the stored permissions, from `authorization.automation.runAs` or
     * capped by `bsb_permission_cap` without it. A publisher who is gone or no
     * longer holds a stored permission, a `runAs` that returns `null`, and an
     * organization-owned version with no service principal and no `runAs` are a
     * `forbidden` error (`WORKFLOW_PUBLISHER_REVOKED`); there is no fallback to
     * the service role. Call it inside every step.
     */
    runAs(
      version: string | undefined,
      tenant?: string,
    ): AsyncResult<Readonly<Record<string, unknown>>>;
  };
  /**
   * Starts a run of the published version: `workflow.run` in its tenant, a run
   * grant on a restricted definition, and not opted out
   * (`WORKFLOW_OPTED_OUT`).
   */
  run(input: RunInput): AsyncResult<string>;
  /**
   * Starts a test run (`workflow.edit`, and an edit grant on a restricted
   * definition): mode `test`, steps return their stubs and never run, sleeps
   * are skipped, and it fires no alerts or outbox events.
   */
  test(input: TestRunInput): AsyncResult<string>;
  readonly triggers: {
    save(input: TriggerInput): AsyncResult<WorkflowTrigger>;
    list(definition: string): AsyncResult<readonly WorkflowTrigger[]>;
    remove(id: string): AsyncResult<boolean>;
    /** A new token for a webhook trigger; the old one stops working. Shown once. */
    rotateToken(id: string): AsyncResult<string>;
    /**
     * A route handler for webhook triggers: the token is the last path segment
     * or a `Bearer` header, the JSON body is the input, and an
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
    /**
     * The token for a credential, with the app subject and the row's scopes
     * (service role; call it inside a step).
     */
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
    /**
     * Fires the slow alerts that are due (service role); returns how many
     * fired.
     */
    check(options?: { readonly batch?: number }): AsyncResult<number>;
  };
  /**
   * An outbox consumer handler that passes each event to `triggers.onEvent`,
   * for `outbox.consume("workflows", builder.sink())`. It throws when a start
   * fails, so the outbox retries the event.
   */
  sink(): (events: readonly WorkflowSinkEvent[]) => Promise<void>;
}

/** An outbox row as a consumer hands it over; an `OutboxEvent` fits. */
export interface WorkflowSinkEvent {
  readonly id: string;
  readonly type: string;
  readonly payload?: unknown;
  readonly tenant?: string | null;
  readonly actorId?: string | null;
}
