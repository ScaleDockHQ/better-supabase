import type {
  CredentialProvider,
  CredentialRef,
} from "../../credentials/provider.ts";
import type { WorkflowStartCall } from "../workflows/workflows.ts";
import type {
  BuilderOptions,
  BuilderStarter,
  RunInput,
  WorkflowBuilder,
  WorkflowDefinition,
  WorkflowTrigger,
  WorkflowVersion,
} from "./types.ts";

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
  randomToken,
  recordOf,
  recordsOf,
  seconds,
  textOf,
} from "../shared.ts";
import { createWorkflows } from "../workflows/workflows.ts";
import { diffGraphs, graphOf } from "./graph.ts";
import {
  alertOf,
  credentialOf,
  definitionOf,
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
  NodeRunRecord,
  OutboxLikeEvent,
  RunInput,
  TriggerInput,
  WorkflowAlert,
  WorkflowBuilder,
  WorkflowCredential,
  WorkflowDefinition,
  WorkflowNodeRun,
  WorkflowNodeRunStatus,
  WorkflowStepInfo,
  WorkflowTrigger,
  WorkflowTriggerKind,
  WorkflowVersion,
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
