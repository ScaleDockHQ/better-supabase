import type { StandardSchemaV1 } from "../../core/standard.ts";
import type {
  CredentialProvider,
  CredentialRef,
} from "../../credentials/provider.ts";
import type {
  WorkflowStartCall,
  WorkflowSubject,
} from "../workflows/workflows.ts";
import type {
  BuilderOptions,
  BuilderStarter,
  GrantInput,
  RunInput,
  TestRunInput,
  WorkflowBuilder,
  WorkflowBuilderHooks,
  WorkflowDefinition,
  WorkflowStepInfo,
  WorkflowTrigger,
  WorkflowVersion,
} from "./types.ts";

import {
  type BlockFields,
  blockFields,
  type FieldsOf,
} from "../../core/block-fields.ts";
import { withBlockHooks } from "../../core/block-hooks.ts";
import { dbError } from "../../core/errors.ts";
import { AsyncResult, err, ok } from "../../core/result.ts";
import {
  credentialRefInTenant,
  foreignCredentialRef,
} from "../../credentials/provider.ts";
import {
  applyTemporal,
  blockCall,
  injectableOf,
  isRecord,
  optionalText,
  randomToken,
  recordOf,
  recordsOf,
  seconds,
  stringsOf,
  textOf,
} from "../shared.ts";
import { diffGraphs, graphOf } from "./graph.ts";
import { mayPublishRefusal, runAsPublisher } from "./publisher.ts";
import {
  alertOf,
  credentialOf,
  definitionOf,
  grantOf,
  nodeRunOf,
  optionalOf,
  stepOf,
  triggerOf,
  versionOf,
} from "./rows.ts";

export type {
  AlertInput,
  BuilderOptions,
  BuilderStartCall,
  BuilderStarter,
  CredentialInput,
  DefinitionInput,
  GraphCompiler,
  GrantInput,
  NodeRunRecord,
  OutboxLikeEvent,
  PublishOptions,
  RunInput,
  TestRunInput,
  TriggerInput,
  VersionSaveOptions,
  WorkflowAlert,
  WorkflowBuilder,
  WorkflowBuilderHooks,
  WorkflowCredential,
  WorkflowDefinition,
  WorkflowDefinitionGrant,
  WorkflowDefinitionScope,
  WorkflowGrantAction,
  WorkflowGrantPrincipal,
  WorkflowNodeRun,
  WorkflowNodeRunStatus,
  WorkflowStepInfo,
  WorkflowTrigger,
  WorkflowTriggerKind,
  WorkflowVersion,
  WorkflowVersionOwner,
  WorkflowVersionStatus,
} from "./types.ts";

const BUILDER_PREFIX = "builder:";

/**
 * The `workflow-builder` module's definitions, versions, triggers,
 * credentials, step library, node runs and alerts. The engine plugs in
 * through `compile` and `start`; credential rows resolve through the
 * `credentials` providers.
 *
 * ```ts
 * const builder = createWorkflowBuilder({
 *   transport: rpcTransport(supabase),
 *   compile: compileGraph,
 *   start: graphStarter({ executor: builderWorkflow, steps: { runNode } }),
 * });
 * ```
 */
export function createWorkflowBuilder<
  S extends StandardSchemaV1 | undefined = undefined,
>(options: BuilderOptions<S>): WorkflowBuilder<FieldsOf<S>> {
  type F = FieldsOf<S>;
  applyTemporal(options);
  const fields: BlockFields<F> = blockFields(
    options.fields,
    "workflow definition fields",
  );
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
      `No credential provider named "${ref.provider}" was passed to createWorkflowBuilder`,
    );

  const getVersion = (version: string) =>
    call("workflow_version_get", { version }, optionalOf(versionOf));

  const startTarget = (
    caller: typeof call,
    input: {
      readonly definition: string;
      readonly tenant: string | undefined;
      readonly subject: WorkflowSubject | undefined;
    },
    start: (target: StartTarget) => Promise<string>,
  ): AsyncResult<string> =>
    (input.subject === undefined
      ? caller(
          "workflow_start_target",
          { definition: input.definition, tenant: input.tenant },
          (value) => recordOf(value, "workflow_start_target"),
        )
      : caller(
          "workflow_subject_start_target",
          {
            definition: input.definition,
            subject_type: input.subject.type,
            subject_id: input.subject.id,
            tenant: input.tenant,
          },
          (value) => recordOf(value, "workflow_subject_start_target"),
        )
    ).andThen(async (row) => ok(await start(startTargetOf(row))));

  const starterOf = (): BuilderStarter | undefined => options.start;
  const missingStarter = () =>
    dbError(
      "invalid_request",
      "Pass `start` to createWorkflowBuilder to run workflows",
    );

  const runWith = (
    caller: typeof call,
    input: RunInput & { readonly trigger?: WorkflowTrigger },
  ): AsyncResult<string> => {
    const start = starterOf();
    if (start === undefined) return AsyncResult.err(missingStarter());
    return startTarget(
      caller,
      {
        definition: input.definition,
        tenant: input.tenant,
        subject: input.subject,
      },
      (target) => {
        const node = input.trigger?.config["node"];
        return start({
          definition: target.definition,
          version: target.version,
          input: input.input ?? {},
          tenant: target.tenant,
          actor: input.actor,
          idempotencyKey: input.idempotencyKey ?? `run:${randomToken(16)}`,
          ...(input.trigger === undefined ? {} : { trigger: input.trigger }),
          ...(target.subject === undefined ? {} : { subject: target.subject }),
          ...(typeof node === "string" ? { triggerNode: node } : {}),
        });
      },
    );
  };

  const grant = (input: GrantInput, granted: boolean) =>
    call(
      "set_workflow_definition_grant",
      {
        definition: input.definition,
        principal_kind: input.principalKind,
        principal_id: input.principalId,
        action: input.action,
        granted,
      },
      (value) => value === true,
    );

  const credentialRow = (id: string) =>
    serviceCall("workflow_credential_get", { credential: id }, (value) =>
      isRecord(value) ? credentialOf(value) : undefined,
    );

  const builder: WorkflowBuilder<F> = {
    definitions: {
      save: (input) =>
        fields.args(input.fields).andThen((checked) =>
          call(
            "save_workflow_definition",
            {
              tenant: input.tenant,
              slug: input.slug,
              name: input.name,
              description: input.description,
              subject_types: input.subjectTypes,
              scope: input.scope,
              restricted: input.restricted,
              fields: checked,
            },
            (value) =>
              definitionOf(recordOf(value, "save_workflow_definition")),
          ).andThen(fields.row),
        ),
      list: (tenant, filter = {}) =>
        call(
          "workflow_definitions_list",
          { tenant, subject_type: filter.subjectType },
          (value) =>
            recordsOf(value, "workflow_definitions_list").map(definitionOf),
        ).andThen(fields.rows),
      get: (id) =>
        call(
          "workflow_definition_get",
          { definition: id },
          optionalOf(definitionOf),
        ).andThen((definition) =>
          definition === undefined
            ? AsyncResult.ok(undefined)
            : fields.row(definition),
        ),
      remove: (id) =>
        call(
          "remove_workflow_definition",
          { definition: id },
          (value) => value === true,
        ),
      fork: (input) =>
        call(
          "fork_workflow_definition",
          { source: input.source, tenant: input.tenant, slug: input.slug },
          (value) => definitionOf(recordOf(value, "fork_workflow_definition")),
        ).andThen(fields.row),
      optOut: (input) =>
        call(
          "set_workflow_opt_out",
          {
            tenant: input.tenant,
            definition: input.definition,
            opted_out: input.optedOut ?? true,
          },
          (value) => value === true,
        ),
      grants: {
        add: (input) => grant(input, true),
        remove: (input) => grant(input, false).map(() => true),
        list: (definition) =>
          call("workflow_definition_grants_list", { definition }, (value) =>
            recordsOf(value, "workflow_definition_grants_list").map(grantOf),
          ),
      },
    },
    versions: {
      save: (definition, graph, saveOptions = {}) =>
        call(
          "save_workflow_draft",
          {
            definition,
            graph,
            ...(saveOptions.inputSchema === undefined
              ? {}
              : { input_schema: saveOptions.inputSchema }),
          },
          (value) => versionOf(recordOf(value, "save_workflow_draft")),
        ),
      publish: (version, publishOptions = {}) =>
        getVersion(version).andThen(async (found) => {
          if (found === undefined) {
            return err(dbError("not_found", "No such workflow version"));
          }
          const mayPublish = options.authorization?.automation?.mayPublish;
          if (mayPublish !== undefined && found.status !== "published") {
            const refusal = await mayPublishRefusal(
              call,
              mayPublish,
              found,
              publishOptions.claims,
            );
            if (!refusal.ok) return refusal;
            if (refusal.data !== undefined) return err(refusal.data);
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
      runAs: (version, tenant) =>
        runAsPublisher(
          serviceCall,
          options.authorization?.automation?.runAs,
          version,
          tenant,
        ),
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
    test: (input) => {
      const start = starterOf();
      if (start === undefined) return AsyncResult.err(missingStarter());
      return call(
        "start_test_run",
        {
          definition: input.definition,
          version: input.version,
          trigger_node: input.triggerNode,
          input: input.input ?? {},
          stubs: input.stubs ?? {},
        },
        (value) => recordOf(value, "start_test_run"),
      ).andThen(async (row) => {
        const target = startTargetOf(row);
        const subject = input.subject;
        if (
          subject !== undefined &&
          !target.definition.subjectTypes.includes(subject.type)
        ) {
          return err(
            dbError(
              "invalid_input",
              "This workflow doesn't run on that subject type",
              { hint: "WORKFLOW_SUBJECT_TYPE" },
            ),
          );
        }
        const node = row["triggerNode"];
        return ok(
          await start({
            definition: target.definition,
            version: target.version,
            input: row["input"] ?? {},
            tenant: target.tenant,
            actor: undefined,
            idempotencyKey: `test:${randomToken(16)}`,
            mode: "test",
            stubs: {
              ...exampleStubs(target.version, options.steps ?? []),
              ...(isRecord(row["stubs"]) ? row["stubs"] : {}),
            },
            ...(typeof node === "string" ? { triggerNode: node } : {}),
            ...(subject === undefined ? {} : { subject }),
          }),
        );
      });
    },
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
            const subject = eventSubject(event, stringsOf(row["subjectTypes"]));
            const tenant = optionalText(row["tenant"]);
            const started = await runWith(serviceCall, {
              definition: trigger.definition,
              input: event.payload ?? {},
              idempotencyKey: `event:${trigger.id}:${event.id}`,
              trigger,
              ...(event.actorId == null ? {} : { actor: event.actorId }),
              ...(tenant === undefined ? {} : { tenant }),
              ...(subject === undefined ? {} : { subject }),
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
        const workflows = options.workflows;
        if (workflows === undefined) {
          return AsyncResult.err(
            dbError(
              "invalid_request",
              "createWorkflowBuilder needs the workflows block to sync a schedule",
              { hint: "WORKFLOW_BUILDER_WORKFLOWS_CLIENT" },
            ),
          );
        }
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
        const started = await runWith(serviceCall, {
          definition: scheduled.workflow.slice(BUILDER_PREFIX.length),
          input: scheduled.input,
          idempotencyKey: scheduled.idempotencyKey,
          ...(scheduled.actor === undefined ? {} : { actor: scheduled.actor }),
          ...(scheduled.tenant === undefined
            ? {}
            : { tenant: scheduled.tenant }),
          ...(scheduled.subject === undefined
            ? {}
            : { subject: scheduled.subject }),
        });
        if (!started.ok && started.error.hint === "WORKFLOW_OPTED_OUT") {
          return "";
        }
        return AsyncResult.from(() => Promise.resolve(started)).orThrow();
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
                  operation: step.operation,
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
  return hooked(builder, options);
}

/** The builder with `options.hooks` around `run`, `test` and each group's methods. */
function hooked<F extends object>(
  builder: WorkflowBuilder<F>,
  options: Pick<BuilderOptions<StandardSchemaV1 | undefined>, "logger"> & {
    readonly hooks?: WorkflowBuilderHooks<F>;
  },
): WorkflowBuilder<F> {
  const hooks = options.hooks;
  if (hooks === undefined) return builder;
  const logger = options.logger ? { logger: options.logger } : {};
  const block = (group: string) => ({
    block: `workflow-builder.${group}`,
    ...logger,
  });
  const top = withBlockHooks(
    {
      run: (input: RunInput) => builder.run(input),
      test: (input: TestRunInput) => builder.test(input),
    },
    {
      ...(hooks.run === undefined ? {} : { run: hooks.run }),
      ...(hooks.test === undefined ? {} : { test: hooks.test }),
    },
    { block: "workflow-builder", ...logger },
  );
  return {
    ...builder,
    run: top.run,
    test: top.test,
    definitions: withBlockHooks(
      builder.definitions,
      hooks.definitions,
      block("definitions"),
    ),
    versions: withBlockHooks(
      builder.versions,
      hooks.versions,
      block("versions"),
    ),
    triggers: withBlockHooks(
      builder.triggers,
      hooks.triggers,
      block("triggers"),
    ),
    credentials: withBlockHooks(
      builder.credentials,
      hooks.credentials,
      block("credentials"),
    ),
    steps: withBlockHooks(builder.steps, hooks.steps, block("steps")),
    nodeRuns: withBlockHooks(
      builder.nodeRuns,
      hooks.nodeRuns,
      block("nodeRuns"),
    ),
    alerts: withBlockHooks(builder.alerts, hooks.alerts, block("alerts")),
  };
}

/**
 * A test run's default stubs: each step node's library `outputSchema`
 * example (its first `examples` entry, else its `default`).
 */
function exampleStubs(
  version: WorkflowVersion,
  steps: readonly WorkflowStepInfo[],
): Record<string, unknown> {
  const schemas = new Map(steps.map((step) => [step.name, step.outputSchema]));
  const stubs: Record<string, unknown> = {};
  for (const node of version.graph?.nodes ?? []) {
    if (node.kind !== "step" || node.step === undefined) continue;
    const schema = schemas.get(node.step);
    if (schema === undefined) continue;
    const examples = schema["examples"];
    if (Array.isArray(examples) && examples.length > 0) {
      stubs[node.id] = examples[0];
    } else if (Object.hasOwn(schema, "default")) {
      stubs[node.id] = schema["default"];
    }
  }
  return stubs;
}

interface StartTarget {
  readonly definition: WorkflowDefinition;
  readonly version: WorkflowVersion;
  readonly tenant: string | undefined;
  readonly subject: WorkflowSubject | undefined;
}

function startTargetOf(row: Record<string, unknown>): StartTarget {
  const definition = definitionOf(recordOf(row["definition"], "definition"));
  const subject = isRecord(row["subject"]) ? row["subject"] : undefined;
  return {
    definition,
    version: versionOf(recordOf(row["version"], "version")),
    tenant: "tenant" in row ? optionalText(row["tenant"]) : definition.tenant,
    subject:
      subject === undefined
        ? undefined
        : { type: textOf(subject["type"]), id: textOf(subject["id"]) },
  };
}

/**
 * A subject event's record (the event's `subjectType` and `subjectId`, else
 * its payload's), when the definition runs on its type.
 */
function eventSubject(
  event: {
    readonly subjectType?: unknown;
    readonly subjectId?: unknown;
    readonly payload?: unknown;
  },
  subjectTypes: readonly string[],
): WorkflowSubject | undefined {
  const payload = isRecord(event.payload) ? event.payload : {};
  const type = event.subjectType ?? payload["subjectType"];
  const id = event.subjectId ?? payload["subjectId"];
  return typeof type === "string" &&
    typeof id === "string" &&
    subjectTypes.includes(type)
    ? { type, id }
    : undefined;
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
