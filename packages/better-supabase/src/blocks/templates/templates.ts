import type {
  BlockFields,
  ExtraFields,
  FieldsOf,
} from "../../core/block-fields.ts";
import type { BlockHooks } from "../../core/block-hooks.ts";
import type { BlockTransport } from "../../core/block-transport.ts";
import type { DbError, ErrorMapper } from "../../core/errors.ts";
import type { Logger } from "../../core/logger.ts";
import type { Result } from "../../core/result.ts";
import type { StandardSchemaV1 } from "../../core/standard.ts";
import type { BlockTemporalOptions } from "../shared.ts";
import type { WorkflowBuilder } from "../workflow-builder/types.ts";
import type { MergeFieldCatalog } from "./merge-fields.ts";

import { blockFields } from "../../core/block-fields.ts";
import { withBlockHooks } from "../../core/block-hooks.ts";
import { dbError } from "../../core/errors.ts";
import { AsyncResult, err, ok } from "../../core/result.ts";
import { validate } from "../../core/standard.ts";
import {
  applyTemporal,
  asDbError,
  blockCall,
  enumOrThrow,
  isRecord,
  optionalInstant,
  optionalText,
  recordOf,
  recordOrEmpty,
  recordsOf,
  requiredInstant,
  textOf,
} from "../shared.ts";

/** Where a template lives: one organization, or every one as a system starter. */
export type TemplateScope = "tenant" | "system";

const SCOPES: readonly TemplateScope[] = ["tenant", "system"];

/**
 * A template type, such as `invoice` or `project`: Standard Schemas for its
 * settings and body (checked on every write and parsed on apply), the merge
 * fields it offers, and `apply`, which creates the record.
 */
export interface TemplateType<Settings = unknown, Body = unknown> {
  readonly settings?: StandardSchemaV1<unknown, Settings>;
  readonly body?: StandardSchemaV1<unknown, Body>;
  readonly mergeFields?: MergeFieldCatalog;
  /**
   * Creates the record from the published snapshot and names it. A method, so a
   * type with typed settings is still a `TemplateType` in `types`.
   */
  apply?(
    call: TemplateApplyCall<Settings, Body>,
  ): TemplateApplied | Promise<TemplateApplied>;
}

export interface TemplateApplyCall<Settings = unknown, Body = unknown> {
  readonly template: Template;
  readonly version: TemplateVersion;
  readonly settings: Settings;
  readonly body: Body;
  /** The organization the record is created in. */
  readonly organizationId: string;
  /** The values `apply` was called with, such as merge field values. */
  readonly values: Readonly<Record<string, unknown>>;
  /**
   * The caller's idempotency key, when it has one (the `templates.apply` step
   * passes `<runKey>:<node>`), so a retried apply can find the record it
   * created.
   */
  readonly key?: string;
}

/** The record `apply` created. */
export interface TemplateApplied {
  readonly subject: TemplateSubject;
}

export interface TemplateSubject {
  readonly type: string;
  readonly id: string;
}

/** Declares a template type with its schemas typed. */
export function defineTemplateType<Settings = unknown, Body = unknown>(
  type: TemplateType<Settings, Body>,
): TemplateType<Settings, Body> {
  return type;
}

/** A template. `F` types the extra columns the `fields` schema describes. */
export interface Template<F extends object = Record<never, never>> {
  readonly id: string;
  /** `undefined` for a system template. */
  readonly organizationId: string | undefined;
  readonly scope: TemplateScope;
  /** The key `sync` keeps a system template by. */
  readonly key: string | undefined;
  readonly type: string;
  readonly name: string;
  readonly language: string;
  /** The default for its organization, type and language. */
  readonly isDefault: boolean;
  readonly settings: Readonly<Record<string, unknown>>;
  /** The template a fork copied, and the version it copied. */
  readonly forkedFrom: string | undefined;
  readonly forkedFromVersion: number | undefined;
  /** The newest published version; `undefined` before the first publish. */
  readonly publishedVersion: number | undefined;
  /** For a fork: the source's newest published version. */
  readonly upstreamVersion: number | undefined;
  /** For a fork: whether the source published a version after the one it copied. */
  readonly behind: boolean;
  readonly createdBy: string | undefined;
  readonly createdAt: Temporal.Instant;
  readonly updatedAt: Temporal.Instant;
  /** The extra columns, keyed by database name. */
  readonly fields: ExtraFields<F>;
}

export interface TemplateVersion {
  readonly id: string;
  readonly template: string;
  readonly version: number;
  /** The SHA-256 of the body. */
  readonly hash: string;
  /** `undefined` for the draft. */
  readonly publishedAt: Temporal.Instant | undefined;
  readonly createdBy: string | undefined;
  readonly createdAt: Temporal.Instant;
  /** Set by `get`, `versions.save` and `versions.publish`; lists leave it out. */
  readonly body?: unknown;
}

export interface TemplateDetail<
  F extends object = Record<never, never>,
> extends Template<F> {
  readonly published: TemplateVersion | undefined;
  readonly draft: TemplateVersion | undefined;
}

export interface TemplateApplication {
  readonly id: string;
  readonly template: string;
  readonly version: string;
  readonly organizationId: string;
  readonly subject: TemplateSubject;
  readonly appliedBy: string | undefined;
  readonly appliedAt: Temporal.Instant;
}

/** A workflow a template starts on each record it creates. */
export interface TemplateWorkflow {
  readonly id: string;
  readonly template: string;
  readonly definition: string;
  /** The run's input, checked against the definition's `inputSchema`. */
  readonly inputs: Readonly<Record<string, unknown>>;
  readonly enabled: boolean;
  readonly createdBy: string | undefined;
  readonly createdAt: Temporal.Instant;
}

export interface TemplateInput<F extends object = Record<never, never>> {
  /** Leave it out to create a template. */
  readonly id?: string;
  /** `null` for a system template, which only the service role saves. */
  readonly organizationId: string | null;
  /** Fixed once the template exists. */
  readonly type: string;
  readonly name?: string;
  /** Default `en`. */
  readonly language?: string;
  readonly settings?: Readonly<Record<string, unknown>>;
  /** The extra columns to set. */
  readonly fields?: Partial<F>;
}

/** A system template `sync` keeps, by key. */
export interface TemplateStarter {
  readonly key: string;
  readonly type: string;
  readonly name: string;
  readonly language?: string;
  readonly settings?: Readonly<Record<string, unknown>>;
  readonly body: unknown;
}

export interface TemplateWorkflowInput {
  readonly template: string;
  readonly definition: string;
  readonly inputs?: Readonly<Record<string, unknown>>;
  /** Default `true`. */
  readonly enabled?: boolean;
}

export interface ApplyOptions {
  /** The organization to create the record in. */
  readonly into: string;
  readonly values?: Readonly<Record<string, unknown>>;
  /** Passed to the type's `apply` as `key`. */
  readonly key?: string;
}

/** A workflow `apply` started on the new record, or why it didn't. */
export type TemplateRunStart =
  | { readonly definition: string; readonly runId: string }
  | { readonly definition: string; readonly error: DbError };

export interface TemplateApplyResult {
  readonly application: TemplateApplication;
  readonly subject: TemplateSubject;
  readonly runs: readonly TemplateRunStart[];
}

export interface Templates<F extends object = Record<never, never>> {
  save(input: TemplateInput<F>): AsyncResult<Template<F>>;
  /**
   * The organization's templates and the system ones (only those with `null`),
   * defaults first.
   */
  list(
    organizationId: string | null,
    filter?: { readonly type?: string; readonly language?: string },
  ): AsyncResult<readonly Template<F>[]>;
  /**
   * With its newest published version and its draft; `undefined` when the
   * caller can't read it.
   */
  get(id: string): AsyncResult<TemplateDetail<F> | undefined>;
  remove(id: string): AsyncResult<boolean>;
  /**
   * Makes it the default for its organization, type and language (or stops it
   * being one).
   */
  setDefault(id: string, isDefault?: boolean): AsyncResult<boolean>;
  /**
   * Copies the newest published version of a system template (or one of the
   * organization's) into a new template there, published as version 1, with its
   * workflow attachments.
   */
  fork(source: string, organizationId: string): AsyncResult<Template<F>>;
  /**
   * Upserts the system templates by key and publishes a new version of each
   * whose body changed. Service role. Returns how many it published.
   */
  sync(starters: readonly TemplateStarter[]): AsyncResult<number>;
  readonly versions: {
    /** Saves the draft: updates the open one, or opens the next version. */
    save(template: string, body: unknown): AsyncResult<TemplateVersion>;
    publish(template: string): AsyncResult<TemplateVersion>;
    /** Newest first, without bodies. */
    list(template: string): AsyncResult<readonly TemplateVersion[]>;
  };
  /** Needs the workflow-builder module. */
  readonly workflows: {
    attach(input: TemplateWorkflowInput): AsyncResult<TemplateWorkflow>;
    detach(template: string, definition: string): AsyncResult<boolean>;
    list(template: string): AsyncResult<readonly TemplateWorkflow[]>;
  };
  /**
   * Creates a record from the template's newest published version through its
   * type's `apply`, records the application and starts the attached workflows
   * on the new record. `templates.apply` in `into`.
   */
  apply(
    template: string,
    options: ApplyOptions,
  ): AsyncResult<TemplateApplyResult>;
  readonly applications: {
    /** Newest first, at most 200. */
    list(
      organizationId: string,
      filter?: {
        readonly template?: string;
        readonly subject?: TemplateSubject;
      },
    ): AsyncResult<readonly TemplateApplication[]>;
  };
}

export interface TemplatesOptions<
  S extends StandardSchemaV1 | undefined = undefined,
> extends BlockTemporalOptions {
  readonly transport: BlockTransport;
  /**
   * The module schema, or its API schema: `defineBlocks` passes it from
   * `blocks.generated.ts`.
   */
  readonly schema?: string;
  /**
   * A Standard Schema for the template's extra columns
   * (`blocks.templates.options.extraColumns`), keyed by database name. It types
   * and parses them on reads, and validates them on `save`.
   */
  readonly fields?: S;
  /** The template types, by name. A type without `apply` can't be applied. */
  readonly types?: Readonly<Record<string, TemplateType>>;
  /** Starts the attached workflows; `createWorkflowBuilder` as the caller. */
  readonly workflows?: Pick<WorkflowBuilder, "run">;
  /** `withBlockHooks` hooks around the client's methods. */
  readonly hooks?: NoInfer<BlockHooks<Templates<FieldsOf<S>>>>;
  /** Receives the errors `after` hooks throw. Default: `console`. */
  readonly logger?: Logger;
  readonly mappers?: readonly ErrorMapper[];
}

function optionalNumber(value: unknown): number | undefined {
  return typeof value === "number" ? value : undefined;
}

function templateOf(row: Record<string, unknown>): Template {
  const forkedFromVersion = optionalNumber(row["forkedFromVersion"]);
  const upstreamVersion = optionalNumber(row["upstreamVersion"]);

  return {
    id: textOf(row["id"]),
    organizationId: optionalText(row["tenant"]),
    scope: enumOrThrow(row["scope"], SCOPES, "template scope"),
    key: optionalText(row["key"]),
    type: textOf(row["type"]),
    name: textOf(row["name"]),
    language: textOf(row["language"]),
    isDefault: row["isDefault"] === true,
    settings: recordOrEmpty(row["settings"]),
    forkedFrom: optionalText(row["forkedFrom"]),
    forkedFromVersion,
    publishedVersion: optionalNumber(row["publishedVersion"]),
    upstreamVersion,
    behind:
      forkedFromVersion !== undefined &&
      upstreamVersion !== undefined &&
      upstreamVersion > forkedFromVersion,
    createdBy: optionalText(row["createdBy"]),
    createdAt: requiredInstant(row["createdAt"], "createdAt"),
    updatedAt: requiredInstant(row["updatedAt"], "updatedAt"),
    fields: recordOrEmpty(row["fields"]),
  };
}

function versionOf(row: Record<string, unknown>): TemplateVersion {
  return {
    id: textOf(row["id"]),
    template: textOf(row["template"]),
    version: Number(row["version"]),
    hash: textOf(row["hash"]),
    publishedAt: optionalInstant(row["publishedAt"]),
    createdBy: optionalText(row["createdBy"]),
    createdAt: requiredInstant(row["createdAt"], "createdAt"),
    ...("body" in row ? { body: row["body"] } : {}),
  };
}

function optionalVersion(value: unknown): TemplateVersion | undefined {
  return isRecord(value) ? versionOf(value) : undefined;
}

function applicationOf(row: Record<string, unknown>): TemplateApplication {
  return {
    id: textOf(row["id"]),
    template: textOf(row["template"]),
    version: textOf(row["version"]),
    organizationId: textOf(row["tenant"]),
    subject: { type: textOf(row["subjectType"]), id: textOf(row["subjectId"]) },
    appliedBy: optionalText(row["appliedBy"]),
    appliedAt: requiredInstant(row["appliedAt"], "appliedAt"),
  };
}

function workflowOf(row: Record<string, unknown>): TemplateWorkflow {
  return {
    id: textOf(row["id"]),
    template: textOf(row["template"]),
    definition: textOf(row["definition"]),
    inputs: recordOrEmpty(row["inputs"]),
    enabled: row["enabled"] !== false,
    createdBy: optionalText(row["createdBy"]),
    createdAt: requiredInstant(row["createdAt"], "createdAt"),
  };
}

interface ApplyTarget {
  readonly template: Template;
  readonly version: TemplateVersion;
  readonly workflows: readonly {
    readonly definition: string;
    readonly inputs: Readonly<Record<string, unknown>>;
  }[];
}

function targetOf(value: unknown): ApplyTarget {
  const row = recordOf(value, "template_apply_target");

  return {
    template: templateOf(recordOf(row["template"], "template_apply_target")),
    version: versionOf(recordOf(row["version"], "template_apply_target")),
    workflows: recordsOf(row["workflows"], "template_apply_target").map(
      (item) => ({
        definition: textOf(item["definition"]),
        inputs: recordOrEmpty(item["inputs"]),
      }),
    ),
  };
}

async function checked(
  schema: StandardSchemaV1 | undefined,
  value: unknown,
  label: string,
): Promise<Result<unknown>> {
  return schema === undefined ? ok(value) : validate(schema, value, label);
}

/**
 * The `templates` SQL module as typed calls: typed, versioned templates that
 * create records, system starters and forks, and the workflows each record
 * starts.
 */
export function createTemplates<
  S extends StandardSchemaV1 | undefined = undefined,
>(options: TemplatesOptions<S>): Templates<FieldsOf<S>> {
  type F = FieldsOf<S>;

  applyTemporal(options);
  const call = blockCall(options.transport, options.schema, options.mappers);
  const fields: BlockFields<F> = blockFields(options.fields, "template fields");
  const types: Readonly<Record<string, TemplateType>> = options.types ?? {};

  const typeOf = (name: string): TemplateType | undefined =>
    Object.hasOwn(types, name) ? types[name] : undefined;

  const get = (id: string): AsyncResult<TemplateDetail<F> | undefined> =>
    call("template_get", { template_id: id }, (value) =>
      isRecord(value)
        ? {
            ...templateOf(value),
            published: optionalVersion(value["published"]),
            draft: optionalVersion(value["draft"]),
          }
        : undefined,
    ).andThen((detail) =>
      detail === undefined ? AsyncResult.ok(undefined) : fields.row(detail),
    );

  const saveVersion = (template: string, body: unknown) =>
    call("save_template_draft", { template_id: template, body }, (value) =>
      versionOf(recordOf(value, "save_template_draft")),
    );

  const startRuns = async (
    target: ApplyTarget,
    application: TemplateApplication,
    subject: TemplateSubject,
    into: string,
  ): Promise<TemplateRunStart[]> => {
    const runs: TemplateRunStart[] = [];

    for (const workflow of target.workflows) {
      const started = await options.workflows!.run({
        definition: workflow.definition,
        input: workflow.inputs,
        subject,
        tenant: into,
        idempotencyKey: `template-application:${application.id}:${workflow.definition}`,
      });

      runs.push(
        started.ok
          ? { definition: workflow.definition, runId: started.data }
          : { definition: workflow.definition, error: started.error },
      );
    }

    return runs;
  };

  const client: Templates<F> = {
    save: (input) =>
      AsyncResult.from(async () => {
        const extra = await fields.args(input.fields);

        if (!extra.ok) {
          return extra;
        }

        const type = typeOf(input.type);
        let settings: unknown = input.settings;

        if (settings !== undefined) {
          const parsed = await checked(
            type?.settings,
            settings,
            "template settings",
          );

          if (!parsed.ok) {
            return parsed;
          }

          settings = parsed.data;
        }

        return call(
          "save_template",
          {
            template_id: input.id ?? null,
            tenant: input.organizationId,
            type: input.type,
            name: input.name ?? null,
            language: input.language ?? null,
            settings: settings ?? null,
            fields: extra.data,
          },
          (value) => templateOf(recordOf(value, "save_template")),
        ).andThen(fields.row);
      }),
    list: (organizationId, filter = {}) =>
      call(
        "templates_list",
        {
          tenant: organizationId,
          type: filter.type ?? null,
          language: filter.language ?? null,
        },
        (value) => recordsOf(value, "templates_list").map(templateOf),
      ).andThen(fields.rows),
    get,
    remove: (id) =>
      call("remove_template", { template_id: id }, (value) => value === true),
    setDefault: (id, isDefault = true) =>
      call(
        "set_default_template",
        { template_id: id, on_default: isDefault },
        (value) => value === true,
      ),
    fork: (source, organizationId) =>
      call("fork_template", { source, tenant: organizationId }, (value) =>
        templateOf(recordOf(value, "fork_template")),
      ).andThen(fields.row),
    sync: (starters) =>
      AsyncResult.from(async () => {
        const rows: Record<string, unknown>[] = [];

        for (const starter of starters) {
          const type = typeOf(starter.type);

          const settings = await checked(
            type?.settings,
            starter.settings ?? {},
            `settings of starter "${starter.key}"`,
          );

          if (!settings.ok) {
            return settings;
          }

          const body = await checked(
            type?.body,
            starter.body,
            `body of starter "${starter.key}"`,
          );

          if (!body.ok) {
            return body;
          }

          rows.push({
            key: starter.key,
            type: starter.type,
            name: starter.name,
            ...(starter.language === undefined
              ? {}
              : { language: starter.language }),
            settings: settings.data,
            body: body.data,
          });
        }

        return call("sync_templates", { starters: rows }, Number);
      }),
    versions: {
      save: (template, body) =>
        AsyncResult.from(async () => {
          const hasBodySchemas = Object.values(types).some(
            (type) => type.body !== undefined,
          );

          if (!hasBodySchemas) {
            return saveVersion(template, body);
          }

          const found = await get(template);

          if (!found.ok) {
            return found;
          }

          if (found.data === undefined) {
            return err(dbError("not_found", "No such template"));
          }

          const parsed = await checked(
            typeOf(found.data.type)?.body,
            body,
            "template body",
          );

          if (!parsed.ok) {
            return parsed;
          }

          return saveVersion(template, parsed.data);
        }),
      publish: (template) =>
        call("publish_template_version", { template_id: template }, (value) =>
          versionOf(recordOf(value, "publish_template_version")),
        ),
      list: (template) =>
        call("template_versions_list", { template_id: template }, (value) =>
          recordsOf(value, "template_versions_list").map(versionOf),
        ),
    },
    workflows: {
      attach: (input) =>
        call(
          "attach_template_workflow",
          {
            template_id: input.template,
            definition: input.definition,
            inputs: input.inputs ?? {},
            enabled: input.enabled ?? true,
          },
          (value) => workflowOf(recordOf(value, "attach_template_workflow")),
        ),
      detach: (template, definition) =>
        call(
          "detach_template_workflow",
          { template_id: template, definition },
          (value) => value === true,
        ),
      list: (template) =>
        call("template_workflows_list", { template_id: template }, (value) =>
          recordsOf(value, "template_workflows_list").map(workflowOf),
        ),
    },
    apply: (template, applyOptions) =>
      call(
        "template_apply_target",
        { template_id: template, tenant: applyOptions.into },
        targetOf,
      ).andThen(async (target) => {
        const type = typeOf(target.template.type);

        if (type?.apply === undefined) {
          return err(
            dbError(
              "invalid_request",
              `No apply handler for template type "${target.template.type}"`,
            ),
          );
        }

        if (target.workflows.length > 0 && options.workflows === undefined) {
          return err(
            dbError(
              "invalid_request",
              "This template starts workflows: pass createTemplates({ workflows })",
            ),
          );
        }

        const settings = await checked(
          type.settings,
          target.template.settings,
          "template settings",
        );

        if (!settings.ok) {
          return settings;
        }

        const body = await checked(
          type.body,
          target.version.body,
          "template body",
        );

        if (!body.ok) {
          return body;
        }

        let applied: TemplateApplied;

        try {
          applied = await type.apply({
            template: target.template,
            version: target.version,
            settings: settings.data,
            body: body.data,
            organizationId: applyOptions.into,
            values: applyOptions.values ?? {},
            ...(applyOptions.key === undefined
              ? {}
              : { key: applyOptions.key }),
          });
        } catch (cause) {
          return err(asDbError(cause));
        }

        const { subject } = applied;

        const recorded = await call(
          "record_template_application",
          {
            template_id: target.template.id,
            version_id: target.version.id,
            tenant: applyOptions.into,
            subject_type: subject.type,
            subject_id: subject.id,
          },
          (value) =>
            applicationOf(recordOf(value, "record_template_application")),
        );

        if (!recorded.ok) {
          return recorded;
        }

        const runs = await startRuns(
          target,
          recorded.data,
          subject,
          applyOptions.into,
        );

        return ok({ application: recorded.data, subject, runs });
      }),
    applications: {
      list: (organizationId, filter = {}) =>
        call(
          "template_applications_list",
          {
            tenant: organizationId,
            template_id: filter.template ?? null,
            subject_type: filter.subject?.type ?? null,
            subject_id: filter.subject?.id ?? null,
          },
          (value) =>
            recordsOf(value, "template_applications_list").map(applicationOf),
        ),
    },
  };

  return withBlockHooks(client, options.hooks, {
    block: "templates",
    ...(options.logger ? { logger: options.logger } : {}),
  });
}
