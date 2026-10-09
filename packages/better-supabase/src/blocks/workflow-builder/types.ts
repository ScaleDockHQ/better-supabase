import type { BlockTransport } from "../../core/block-transport.ts";
import type { ErrorMapper } from "../../core/errors.ts";
import type { AsyncResult } from "../../core/result.ts";
import type {
  CredentialProvider,
  CredentialRef,
  CredentialToken,
} from "../../credentials/provider.ts";
import type { BlockTemporalOptions } from "../shared.ts";
import type {
  WorkflowSchedule,
  WorkflowStarter,
} from "../workflows/workflows.ts";
import type { WorkflowGraph, WorkflowGraphDiff } from "./graph.ts";

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
