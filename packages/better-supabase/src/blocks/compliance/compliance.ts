import type {
  BlockFields,
  ExtraFields,
  FieldsOf,
} from "../../core/block-fields.ts";
import type { BlockHooks } from "../../core/block-hooks.ts";
import type { BlockTransport } from "../../core/block-transport.ts";
import type { ErrorMapper } from "../../core/errors.ts";
import type { Logger } from "../../core/logger.ts";
import type { AsyncResult } from "../../core/result.ts";
import type { StandardSchemaV1 } from "../../core/standard.ts";
import type { BlockTemporalOptions } from "../shared.ts";

import { blockFields } from "../../core/block-fields.ts";
import { withBlockHooks } from "../../core/block-hooks.ts";
import { temporal } from "../../core/temporal-required.ts";
import {
  applyTemporal,
  blockCall,
  enumOrThrow,
  isRecord,
  optionalInstant,
  optionalText,
  recordOf,
  recordsOf,
  requiredInstant,
  textOf,
} from "../shared.ts";

export interface ComplianceOptions<
  S extends StandardSchemaV1 | undefined = undefined,
> extends BlockTemporalOptions {
  readonly transport: BlockTransport;
  /**
   * The module schema, or its API schema: `defineBlocks` passes it from
   * `blocks.generated.ts`.
   */
  readonly schema?: string;
  /**
   * A Standard Schema for the control's extra columns
   * (`blocks.compliance.options.extraColumns`), keyed by database name. It
   * types and parses them on reads, and validates them on `saveControl`.
   */
  readonly fields?: S;
  /** `withBlockHooks` hooks around the client's methods. */
  readonly hooks?: NoInfer<BlockHooks<Compliance<FieldsOf<S>>>>;
  /** Receives the errors `after` hooks throw. Default: `console`. */
  readonly logger?: Logger;
  readonly mappers?: readonly ErrorMapper[];
}

/**
 * What a framework is: a `standard` (SOC 2, ISO 27001), a `legal` register of
 * obligations, an `internal` one or a `contract`.
 */
export type ControlFrameworkKind =
  | "standard"
  | "legal"
  | "internal"
  | "contract";

/** A compliance framework, such as SOC 2 or ISO 27001. */
export interface ControlFramework {
  readonly id: string;
  readonly organizationId: string;
  readonly key: string;
  readonly name: string;
  readonly kind: ControlFrameworkKind;
  readonly version?: string;
  readonly description?: string;
  readonly createdAt: Temporal.Instant;
  readonly updatedAt: Temporal.Instant;
}

export interface ControlFrameworkInput {
  /** Saving a key again updates that framework. */
  readonly key: string;
  readonly name: string;
  /** Default: `standard`. */
  readonly kind?: ControlFrameworkKind;
  readonly version?: string;
  readonly description?: string;
}

/**
 * `passing`: current evidence and no overdue task. `failing`: an overdue task,
 * or only lapsed evidence. `not_started`: no evidence yet. `not_applicable`:
 * out of scope.
 */
export type ControlStatus =
  | "passing"
  | "failing"
  | "not_started"
  | "not_applicable";

/** A control. `F` types the extra columns the `fields` schema describes. */
export interface Control<F extends object = Record<never, never>> {
  readonly id: string;
  readonly organizationId: string;
  readonly frameworkId: string;
  readonly code: string;
  readonly title: string;
  readonly description?: string;
  readonly ownerId?: string;
  readonly applicable: boolean;
  /** Where the obligation comes from, such as a law or a clause. */
  readonly source?: string;
  /** Where the obligation applies, such as a country. */
  readonly jurisdiction?: string;
  readonly status: ControlStatus;
  readonly createdAt: Temporal.Instant;
  readonly updatedAt: Temporal.Instant;
  /** The extra columns, keyed by database name. */
  readonly fields: ExtraFields<F>;
}

/** A control with its evidence (the newest 100) and evidence tasks. */
export interface ControlDetail<
  F extends object = Record<never, never>,
> extends Control<F> {
  readonly evidence: readonly ControlEvidence[];
  readonly tasks: readonly EvidenceTask[];
}

export interface ControlInput<F extends object = Record<never, never>> {
  readonly frameworkId: string;
  /** Saving a code again in the framework updates that control. */
  readonly code: string;
  readonly title: string;
  readonly description?: string;
  readonly ownerId?: string;
  /** Default `true`. */
  readonly applicable?: boolean;
  /** Changes this control, code included. */
  readonly controlId?: string;
  /** Where the obligation comes from, such as a law or a clause. */
  readonly source?: string;
  /** Where the obligation applies, such as a country. */
  readonly jurisdiction?: string;
  /** The extra columns to set. */
  readonly fields?: Partial<F>;
}

export interface ControlListOptions {
  readonly frameworkId?: string;
  readonly status?: ControlStatus;
  readonly ownerId?: string;
  readonly pageSize?: number;
}

/** Evidence for a control: an attachment, a note, or both. */
export interface ControlEvidence {
  readonly id: string;
  readonly organizationId: string;
  readonly controlId: string;
  readonly evidenceTaskId?: string;
  readonly attachmentId?: string;
  readonly note?: string;
  readonly collectedBy?: string;
  readonly collectedAt: Temporal.Instant;
  /** The last day it counts; missing counts until it is removed. */
  readonly validUntil?: Temporal.PlainDate;
  readonly valid: boolean;
}

export interface ControlEvidenceInput {
  /** An attachment on the control (attachments block). */
  readonly attachmentId?: string;
  readonly note?: string;
  /** Default: the task's interval past today, or no end without a task. */
  readonly validUntil?: Temporal.PlainDate;
  /** The recurring task this evidence answers. */
  readonly evidenceTaskId?: string;
}

/** A recurring request for evidence, with an assignee and a due date. */
export interface EvidenceTask {
  readonly id: string;
  readonly organizationId: string;
  readonly controlId: string;
  readonly title: string;
  readonly assigneeId?: string;
  readonly intervalDays: number;
  readonly dueOn: Temporal.PlainDate;
  readonly lastCollectedAt?: Temporal.Instant;
  readonly active: boolean;
  /** Active and past its due date. */
  readonly overdue: boolean;
  /** On `evidenceTasks` rows. */
  readonly controlCode?: string;
  readonly controlTitle?: string;
  readonly createdAt: Temporal.Instant;
  readonly updatedAt: Temporal.Instant;
}

export interface EvidenceTaskInput {
  readonly title: string;
  /** Collecting evidence moves `dueOn` this many days past the collection. */
  readonly intervalDays: number;
  /** Default: today. */
  readonly dueOn?: Temporal.PlainDate;
  readonly assigneeId?: string;
  /** Default `true`. */
  readonly active?: boolean;
  /** Changes this task instead of adding one. */
  readonly evidenceTaskId?: string;
}

export interface EvidenceTaskListOptions {
  readonly controlId?: string;
  readonly assigneeId?: string;
  readonly overdueOnly?: boolean;
}

/** The status rollup of one framework. */
export interface ControlPosture {
  readonly frameworkId: string;
  readonly key: string;
  readonly name: string;
  readonly version?: string;
  readonly total: number;
  readonly passing: number;
  readonly failing: number;
  readonly notStarted: number;
  readonly notApplicable: number;
  readonly overdueTasks: number;
}

/**
 * A policy members acknowledge through the acknowledgements block, published as
 * frozen versions.
 */
export interface Policy {
  readonly id: string;
  readonly organizationId: string;
  readonly key: string;
  readonly title: string;
  readonly ownerId?: string;
  readonly requiresAcknowledgement: boolean;
  /** The published version (versions block). */
  readonly versionId?: string;
  readonly versionNumber?: number;
  readonly publishedAt?: Temporal.Instant;
  readonly archivedAt?: Temporal.Instant;
  /** When the caller acknowledged the published version. */
  readonly acknowledgedAt?: Temporal.Instant;
  /** Members who acknowledged the published version. */
  readonly acknowledgedCount: number;
  /** Members of the organization. */
  readonly memberCount: number;
  readonly createdAt: Temporal.Instant;
  readonly updatedAt: Temporal.Instant;
}

export interface PolicyInput {
  /** Saving a key again updates that policy. */
  readonly key: string;
  readonly title: string;
  readonly ownerId?: string;
  /** Default `true`. */
  readonly requiresAcknowledgement?: boolean;
  /** Changes this policy, key included. */
  readonly policyId?: string;
}

export interface PolicyListOptions {
  readonly includeArchived?: boolean;
}

/** What `importOscalCatalog` made. */
export interface OscalCatalogImport {
  readonly frameworkId: string;
  readonly key: string;
  /** How many controls the catalog held, groups and nested controls included. */
  readonly controls: number;
}

/** What `applyOscalProfile` did to the framework's controls. */
export interface OscalProfileResult {
  readonly frameworkId: string;
  readonly applicable: number;
  readonly notApplicable: number;
  /** Ids the profile names that the framework has no control for. */
  readonly unknownIds: readonly string[];
}

/** An OSCAL document: parsed JSON. */
export type OscalDocument = Readonly<Record<string, unknown>>;

export interface Compliance<F extends object = Record<never, never>> {
  /** Needs `compliance.manage`. */
  saveFramework(input: {
    organizationId: string;
    input: ControlFrameworkInput;
  }): AsyncResult<ControlFramework>;
  frameworks(organizationId: string): AsyncResult<readonly ControlFramework[]>;
  /**
   * Imports an OSCAL catalog (JSON) as a framework with a control per catalog
   * control. The framework key defaults to the catalog uuid. Needs
   * `compliance.manage`.
   */
  importOscalCatalog(
    input: { organizationId: string; catalog: OscalDocument } & {
      readonly key?: string;
    },
  ): AsyncResult<OscalCatalogImport>;
  /**
   * Marks the controls an OSCAL profile includes as applicable and the rest as
   * not applicable. The profile's import href is not followed. Needs
   * `compliance.manage`.
   */
  applyOscalProfile(input: {
    frameworkId: string;
    profile: OscalDocument;
  }): AsyncResult<OscalProfileResult>;
  /**
   * An OSCAL assessment-results document for the framework: a finding per
   * applicable control and an observation per piece of evidence.
   */
  exportOscalAssessmentResults(
    input: { frameworkId: string } & { readonly title?: string },
  ): AsyncResult<OscalDocument>;
  /** Needs `compliance.manage`. */
  saveControl(input: ControlInput<F>): AsyncResult<Control<F>>;
  getControl(controlId: string): AsyncResult<ControlDetail<F>>;
  /** By framework and code. */
  controls(
    input: { organizationId: string } & ControlListOptions,
  ): AsyncResult<readonly Control<F>[]>;
  /** Needs `compliance.collect`, or being the evidence task's assignee. */
  addEvidence(input: {
    controlId: string;
    input: ControlEvidenceInput;
  }): AsyncResult<ControlEvidence>;
  /** Needs `compliance.manage`. */
  removeEvidence(evidenceId: string): AsyncResult<ControlEvidence>;
  /** Needs `compliance.manage`. */
  saveEvidenceTask(input: {
    controlId: string;
    input: EvidenceTaskInput;
  }): AsyncResult<EvidenceTask>;
  /** The earliest due first. */
  evidenceTasks(
    input: { organizationId: string } & EvidenceTaskListOptions,
  ): AsyncResult<readonly EvidenceTask[]>;
  /** The status rollup per framework. */
  posture(input: {
    organizationId: string;
    frameworkId?: string | undefined;
  }): AsyncResult<readonly ControlPosture[]>;
  /**
   * Reports each overdue evidence task once per lapse; returns how many.
   * Service role only; run it daily.
   */
  notifyOverdue(): AsyncResult<number>;
  /** Needs `compliance.manage`. */
  savePolicy(input: {
    organizationId: string;
    input: PolicyInput;
  }): AsyncResult<Policy>;
  /**
   * Publishes the policy's text as a new frozen version. Members acknowledge
   * each published version again. Needs `compliance.manage`.
   */
  publishPolicy(input: {
    policyId: string;
    content: Readonly<Record<string, unknown>>;
    label?: string | undefined;
  }): AsyncResult<Policy>;
  archivePolicy(policyId: string): AsyncResult<Policy>;
  policies(
    input: { organizationId: string } & PolicyListOptions,
  ): AsyncResult<readonly Policy[]>;
}

const KINDS: readonly ControlFrameworkKind[] = [
  "standard",
  "legal",
  "internal",
  "contract",
];

const STATUSES: readonly ControlStatus[] = [
  "passing",
  "failing",
  "not_started",
  "not_applicable",
];

function optional<K extends string, V>(
  key: K,
  value: V | undefined,
): { readonly [P in K]?: V } {
  // SAFETY: a one-key object literal for the key the caller names.
  return (value === undefined ? {} : { [key]: value }) as {
    readonly [P in K]?: V;
  };
}

const optionalDate = (value: unknown): Temporal.PlainDate | undefined =>
  typeof value === "string" && value !== ""
    ? temporal().PlainDate.from(value)
    : undefined;

const dateOf = (value: unknown): Temporal.PlainDate =>
  temporal().PlainDate.from(textOf(value));

const numberOf = (value: unknown): number =>
  typeof value === "number" ? value : Number(value ?? 0);

const optionalNumber = (value: unknown): number | undefined =>
  value === null || value === undefined ? undefined : numberOf(value);

function frameworkOf(value: unknown, fn: string): ControlFramework {
  const row = recordOf(value, fn);

  return {
    id: textOf(row["id"]),
    organizationId: textOf(row["organizationId"]),
    key: textOf(row["key"]),
    name: textOf(row["name"]),
    kind: enumOrThrow(row["kind"] ?? "standard", KINDS, "framework kind"),
    createdAt: requiredInstant(row["createdAt"], "createdAt"),
    updatedAt: requiredInstant(row["updatedAt"], "updatedAt"),
    ...optional("version", optionalText(row["version"])),
    ...optional("description", optionalText(row["description"])),
  };
}

function controlOf(value: unknown, fn: string): Control {
  const row = recordOf(value, fn);

  return {
    id: textOf(row["id"]),
    organizationId: textOf(row["organizationId"]),
    frameworkId: textOf(row["frameworkId"]),
    code: textOf(row["code"]),
    title: textOf(row["title"]),
    applicable: row["applicable"] === true,
    status: enumOrThrow(row["status"], STATUSES, "control status"),
    createdAt: requiredInstant(row["createdAt"], "createdAt"),
    updatedAt: requiredInstant(row["updatedAt"], "updatedAt"),
    ...optional("description", optionalText(row["description"])),
    ...optional("ownerId", optionalText(row["ownerId"])),
    ...optional("source", optionalText(row["source"])),
    ...optional("jurisdiction", optionalText(row["jurisdiction"])),
    fields: isRecord(row["fields"]) ? row["fields"] : {},
  };
}

function evidenceOf(value: unknown, fn: string): ControlEvidence {
  const row = recordOf(value, fn);

  return {
    id: textOf(row["id"]),
    organizationId: textOf(row["organizationId"]),
    controlId: textOf(row["controlId"]),
    collectedAt: requiredInstant(row["collectedAt"], "collectedAt"),
    valid: row["valid"] === true,
    ...optional("evidenceTaskId", optionalText(row["evidenceTaskId"])),
    ...optional("attachmentId", optionalText(row["attachmentId"])),
    ...optional("note", optionalText(row["note"])),
    ...optional("collectedBy", optionalText(row["collectedBy"])),
    ...optional("validUntil", optionalDate(row["validUntil"])),
  };
}

function taskOf(value: unknown, fn: string): EvidenceTask {
  const row = recordOf(value, fn);

  return {
    id: textOf(row["id"]),
    organizationId: textOf(row["organizationId"]),
    controlId: textOf(row["controlId"]),
    title: textOf(row["title"]),
    intervalDays: numberOf(row["intervalDays"]),
    dueOn: dateOf(row["dueOn"]),
    active: row["active"] === true,
    overdue: row["overdue"] === true,
    createdAt: requiredInstant(row["createdAt"], "createdAt"),
    updatedAt: requiredInstant(row["updatedAt"], "updatedAt"),
    ...optional("assigneeId", optionalText(row["assigneeId"])),
    ...optional("lastCollectedAt", optionalInstant(row["lastCollectedAt"])),
    ...optional("controlCode", optionalText(row["controlCode"])),
    ...optional("controlTitle", optionalText(row["controlTitle"])),
  };
}

function detailOf(value: unknown, fn: string): ControlDetail {
  const row = recordOf(value, fn);

  return {
    ...controlOf(row, fn),
    evidence: recordsOf(row["evidence"] ?? [], fn).map((item) =>
      evidenceOf(item, fn),
    ),
    tasks: recordsOf(row["tasks"] ?? [], fn).map((item) => taskOf(item, fn)),
  };
}

function postureOf(value: unknown, fn: string): ControlPosture {
  const row = recordOf(value, fn);

  return {
    frameworkId: textOf(row["frameworkId"]),
    key: textOf(row["key"]),
    name: textOf(row["name"]),
    total: numberOf(row["total"]),
    passing: numberOf(row["passing"]),
    failing: numberOf(row["failing"]),
    notStarted: numberOf(row["notStarted"]),
    notApplicable: numberOf(row["notApplicable"]),
    overdueTasks: numberOf(row["overdueTasks"]),
    ...optional("version", optionalText(row["version"])),
  };
}

function policyOf(value: unknown, fn: string): Policy {
  const row = recordOf(value, fn);

  return {
    id: textOf(row["id"]),
    organizationId: textOf(row["organizationId"]),
    key: textOf(row["key"]),
    title: textOf(row["title"]),
    requiresAcknowledgement: row["requiresAcknowledgement"] === true,
    acknowledgedCount: numberOf(row["acknowledgedCount"]),
    memberCount: numberOf(row["memberCount"]),
    createdAt: requiredInstant(row["createdAt"], "createdAt"),
    updatedAt: requiredInstant(row["updatedAt"], "updatedAt"),
    ...optional("ownerId", optionalText(row["ownerId"])),
    ...optional("versionId", optionalText(row["versionId"])),
    ...optional("versionNumber", optionalNumber(row["versionNumber"])),
    ...optional("publishedAt", optionalInstant(row["publishedAt"])),
    ...optional("archivedAt", optionalInstant(row["archivedAt"])),
    ...optional("acknowledgedAt", optionalInstant(row["acknowledgedAt"])),
  };
}

const many =
  <T>(fn: string, of: (value: unknown, fn: string) => T) =>
  (value: unknown): readonly T[] =>
    recordsOf(value, fn).map((row) => of(row, fn));

/** The `compliance` SQL module as typed calls. */
export function createCompliance<
  S extends StandardSchemaV1 | undefined = undefined,
>(options: ComplianceOptions<S>): Compliance<FieldsOf<S>> {
  type F = FieldsOf<S>;

  applyTemporal(options);
  const call = blockCall(options.transport, options.schema, options.mappers);

  const fields: BlockFields<F> = blockFields(options.fields, "control fields");

  const policy = (fn: string) => (value: unknown) => policyOf(value, fn);

  const listPolicies = (
    organizationId: string,
    includeArchived: boolean,
  ): AsyncResult<readonly Policy[]> =>
    call(
      "list_compliance_policies",
      { tenant: organizationId, include_archived: includeArchived },
      many("list_compliance_policies", policyOf),
    );

  const client: Compliance<F> = {
    saveFramework: ({ organizationId, input }) =>
      call(
        "save_control_framework",
        {
          tenant: organizationId,
          key: input.key,
          name: input.name,
          version: input.version ?? null,
          description: input.description ?? null,
          kind: input.kind ?? "standard",
        },
        (value) => frameworkOf(value, "save_control_framework"),
      ),
    frameworks: (organizationId) =>
      call(
        "list_control_frameworks",
        { tenant: organizationId },
        many("list_control_frameworks", frameworkOf),
      ),
    importOscalCatalog: ({ organizationId, catalog, ...options }) =>
      call(
        "import_oscal_catalog",
        { tenant: organizationId, document: catalog, key: options.key ?? null },
        (value) => {
          const row = recordOf(value, "import_oscal_catalog");

          return {
            frameworkId: textOf(row["frameworkId"]),
            key: textOf(row["key"]),
            controls: numberOf(row["controls"]),
          };
        },
      ),
    applyOscalProfile: ({ frameworkId, profile }) =>
      call(
        "apply_oscal_profile",
        { framework_id: frameworkId, document: profile },
        (value) => {
          const row = recordOf(value, "apply_oscal_profile");

          return {
            frameworkId: textOf(row["frameworkId"]),
            applicable: numberOf(row["applicable"]),
            notApplicable: numberOf(row["notApplicable"]),
            unknownIds: (Array.isArray(row["unknownIds"])
              ? row["unknownIds"]
              : []
            ).map(textOf),
          };
        },
      ),
    exportOscalAssessmentResults: ({ frameworkId, ...options }) =>
      call(
        "export_oscal_assessment_results",
        { framework_id: frameworkId, title: options.title ?? null },
        (value) => recordOf(value, "export_oscal_assessment_results"),
      ),
    saveControl: (input) =>
      fields
        .args(input.fields)
        .andThen((checked) =>
          call(
            "save_control",
            {
              framework_id: input.frameworkId,
              code: input.code,
              title: input.title,
              description: input.description ?? null,
              owner_id: input.ownerId ?? null,
              applicable: input.applicable ?? true,
              control_id: input.controlId ?? null,
              source: input.source ?? null,
              jurisdiction: input.jurisdiction ?? null,
              ...(checked === undefined ? {} : { fields: checked }),
            },
            (value) => controlOf(value, "save_control"),
          ).andThen(fields.row),
        ),
    getControl: (controlId) =>
      call("get_control", { control_id: controlId }, (value) =>
        detailOf(value, "get_control"),
      ).andThen(fields.row),
    controls: ({ organizationId, ...list }) =>
      call(
        "list_controls",
        {
          tenant: organizationId,
          framework_id: list.frameworkId ?? null,
          status: list.status ?? null,
          owner_id: list.ownerId ?? null,
          page_size: list.pageSize ?? null,
        },
        many("list_controls", controlOf),
      ).andThen(fields.rows),
    addEvidence: ({ controlId, input }) =>
      call(
        "add_control_evidence",
        {
          control_id: controlId,
          attachment_id: input.attachmentId ?? null,
          note: input.note ?? null,
          valid_until: input.validUntil?.toString() ?? null,
          task_id: input.evidenceTaskId ?? null,
        },
        (value) => evidenceOf(value, "add_control_evidence"),
      ),
    removeEvidence: (evidenceId) =>
      call("remove_control_evidence", { evidence_id: evidenceId }, (value) =>
        evidenceOf(value, "remove_control_evidence"),
      ),
    saveEvidenceTask: ({ controlId, input }) =>
      call(
        "save_evidence_task",
        {
          control_id: controlId,
          title: input.title,
          interval_days: input.intervalDays,
          due_on: input.dueOn?.toString() ?? null,
          assignee_id: input.assigneeId ?? null,
          active: input.active ?? true,
          task_id: input.evidenceTaskId ?? null,
        },
        (value) => taskOf(value, "save_evidence_task"),
      ),
    evidenceTasks: ({ organizationId, ...list }) =>
      call(
        "list_evidence_tasks",
        {
          tenant: organizationId,
          control_id: list.controlId ?? null,
          assignee_id: list.assigneeId ?? null,
          overdue_only: list.overdueOnly ?? false,
        },
        many("list_evidence_tasks", taskOf),
      ),
    posture: ({ organizationId, frameworkId }) =>
      call(
        "control_posture",
        { tenant: organizationId, framework_id: frameworkId ?? null },
        many("control_posture", postureOf),
      ),
    notifyOverdue: () => call("notify_overdue_evidence_tasks", {}, numberOf),
    savePolicy: ({ organizationId, input }) =>
      call(
        "save_compliance_policy",
        {
          tenant: organizationId,
          key: input.key,
          title: input.title,
          owner_id: input.ownerId ?? null,
          requires_acknowledgement: input.requiresAcknowledgement ?? true,
          policy_id: input.policyId ?? null,
        },
        policy("save_compliance_policy"),
      ),
    publishPolicy: ({ policyId, content, label }) =>
      call(
        "publish_compliance_policy",
        { policy_id: policyId, content, label: label ?? null },
        policy("publish_compliance_policy"),
      ),
    archivePolicy: (policyId) =>
      call(
        "archive_compliance_policy",
        { policy_id: policyId },
        policy("archive_compliance_policy"),
      ),
    policies: ({ organizationId, ...list }) =>
      listPolicies(organizationId, list.includeArchived ?? false),
  };

  return withBlockHooks(client, options.hooks, {
    block: "compliance",
    ...(options.logger ? { logger: options.logger } : {}),
  });
}
