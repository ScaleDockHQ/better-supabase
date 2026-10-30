import type {
  BlockFields,
  ExtraFields,
  FieldsOf,
} from "../../core/block-fields.ts";
import type { BlockHooks } from "../../core/block-hooks.ts";
import type { BlockTransport } from "../../core/block-transport.ts";
import type { ErrorMapper } from "../../core/errors.ts";
import type { Logger } from "../../core/logger.ts";
import type { StandardSchemaV1 } from "../../core/standard.ts";
import type { BlockTemporalOptions } from "../shared.ts";

import { blockFields } from "../../core/block-fields.ts";
import { withBlockHooks } from "../../core/block-hooks.ts";
import { AsyncResult } from "../../core/result.ts";
import { temporal } from "../../core/temporal-required.ts";
import {
  applyTemporal,
  blockCall,
  enumOrThrow,
  instantArg,
  isRecord,
  optionalInstant,
  optionalText,
  recordOf,
  recordsOf,
  requiredInstant,
  textOf,
} from "../shared.ts";

export interface IncidentsOptions<
  S extends StandardSchemaV1 | undefined = undefined,
> extends BlockTemporalOptions {
  readonly transport: BlockTransport;
  /**
   * The module schema, or its API schema: `defineBlocks` passes it from
   * `blocks.generated.ts`.
   */
  readonly schema?: string;
  /**
   * A Standard Schema for the incident's extra columns
   * (`blocks.incidents.options.extraColumns`), keyed by database name. It types
   * and parses them on reads, and validates them on `open` and `update`.
   */
  readonly fields?: S;
  /** `withBlockHooks` hooks around the client's methods. */
  readonly hooks?: NoInfer<BlockHooks<Incidents<FieldsOf<S>>>>;
  /** Receives the errors `after` hooks throw. Default: `console`. */
  readonly logger?: Logger;
  readonly mappers?: readonly ErrorMapper[];
}

/** `sev1` is the most severe. */
export type IncidentSeverity = "sev1" | "sev2" | "sev3" | "sev4";

export type IncidentStatus =
  | "investigating"
  | "identified"
  | "monitoring"
  | "resolved";

/** From best to worst. */
export type ComponentStatus =
  | "operational"
  | "maintenance"
  | "degraded"
  | "partial_outage"
  | "major_outage";

/** What an incident does to a component: any status but `operational`. */
export type ComponentImpact = Exclude<ComponentStatus, "operational">;

/** A component or service a status page shows. */
export interface StatusComponent {
  readonly id: string;
  readonly organizationId: string;
  readonly name: string;
  readonly description?: string;
  readonly group?: string;
  /** Shown on the public status page. */
  readonly public: boolean;
  /** The worst impact of the open incidents on it, else `operational`. */
  readonly status: ComponentStatus;
  readonly position: number;
  readonly createdAt: Temporal.Instant;
  readonly updatedAt: Temporal.Instant;
}

export interface StatusComponentInput {
  readonly name: string;
  readonly description?: string;
  readonly group?: string;
  /** Default `true`. */
  readonly public?: boolean;
  /** Default `0`; lower comes first. */
  readonly position?: number;
  /** Changes this component instead of adding one. */
  readonly componentId?: string;
}

export interface IncidentImpactInput {
  readonly componentId: string;
  readonly impact: ComponentImpact;
}

export interface IncidentImpact extends IncidentImpactInput {
  readonly name: string;
}

/** An incident. `F` types the extra columns the `fields` schema describes. */
export interface Incident<F extends object = Record<never, never>> {
  readonly id: string;
  readonly organizationId: string;
  readonly title: string;
  /** Internal; the status page never shows it. */
  readonly description?: string;
  readonly severity: IncidentSeverity;
  readonly status: IncidentStatus;
  /** Shown on the public status page. */
  readonly public: boolean;
  readonly commanderId?: string;
  readonly startedAt: Temporal.Instant;
  readonly resolvedAt?: Temporal.Instant;
  readonly createdBy?: string;
  readonly createdAt: Temporal.Instant;
  readonly updatedAt: Temporal.Instant;
  readonly impacts: readonly IncidentImpact[];
  /** The extra columns, keyed by database name. */
  readonly fields: ExtraFields<F>;
}

/** An entry on an incident's timeline. */
export interface IncidentUpdate {
  readonly id: string;
  readonly incidentId: string;
  readonly status: IncidentStatus;
  readonly body: string;
  readonly public: boolean;
  readonly authorId?: string;
  readonly createdAt: Temporal.Instant;
}

export type PostmortemStatus = "draft" | "published";

export interface Postmortem {
  readonly id: string;
  readonly incidentId: string;
  readonly summary?: string;
  readonly impact?: string;
  readonly rootCause?: string;
  readonly resolution?: string;
  /**
   * @deprecated With the tasks block, action items are tasks: read `actions`
   * and write them with `addPostmortemAction`. This JSON list stays readable
   * until 0.48 and is no longer written once tasks is installed.
   */
  readonly actionItems: readonly unknown[];
  /** The action items, a task each; empty without the tasks block. */
  readonly actions: readonly PostmortemAction[];
  readonly status: PostmortemStatus;
  readonly publishedAt?: Temporal.Instant;
  readonly authorId?: string;
  readonly createdAt: Temporal.Instant;
  readonly updatedAt: Temporal.Instant;
}

/** A postmortem action item: a task in the tasks block. */
export interface PostmortemAction {
  readonly id: string;
  readonly postmortemId: string;
  readonly taskId: string;
  readonly title: string;
  /** The task's state, as the tasks block names it. */
  readonly state: string;
  readonly dueAt?: Temporal.Instant;
  readonly closedAt?: Temporal.Instant;
  readonly createdAt?: Temporal.Instant;
}

export interface PostmortemActionInput {
  readonly title: string;
  readonly assigneeId?: string;
  readonly dueAt?: Temporal.Instant;
}

/** An incident with its timeline, oldest first, and its postmortem. */
export interface IncidentDetail<
  F extends object = Record<never, never>,
> extends Incident<F> {
  readonly updates: readonly IncidentUpdate[];
  readonly postmortem?: Postmortem;
}

export interface IncidentInput<F extends object = Record<never, never>> {
  readonly title: string;
  readonly description?: string;
  /** Default `sev3`. */
  readonly severity?: IncidentSeverity;
  /** Default `false`: only members see it. */
  readonly public?: boolean;
  readonly commanderId?: string;
  /** The first timeline entry, with the incident's visibility. */
  readonly message?: string;
  readonly impacts?: readonly IncidentImpactInput[];
  /** The extra columns to set. */
  readonly fields?: Partial<F>;
}

export type IncidentChanges<F extends object = Record<never, never>> = Partial<
  Omit<IncidentInput<F>, "message" | "impacts">
>;

export interface IncidentUpdateInput {
  readonly status: IncidentStatus;
  readonly body: string;
  /** Default: the incident's visibility. */
  readonly public?: boolean;
}

export interface IncidentListOptions {
  readonly status?: "open" | "resolved";
  readonly severity?: IncidentSeverity;
  readonly componentId?: string;
  /** The `startedAt` of the last row of the previous page. */
  readonly before?: Temporal.Instant;
  /** Default 50, at most 200. */
  readonly pageSize?: number;
}

export interface PostmortemInput {
  readonly summary?: string;
  readonly impact?: string;
  readonly rootCause?: string;
  readonly resolution?: string;
  /**
   * @deprecated With the tasks block, `savePostmortem` refuses this key: use
   * `addPostmortemAction`. Removed in 0.48.
   */
  readonly actionItems?: readonly unknown[];
}

/** The organization's status page settings. */
export interface StatusPage {
  readonly id: string;
  readonly organizationId: string;
  readonly slug: string;
  readonly title: string;
  readonly description?: string;
  readonly published: boolean;
  readonly createdAt: Temporal.Instant;
  readonly updatedAt: Temporal.Instant;
}

export interface StatusPageInput {
  /** Lowercase letters, digits and dashes; unique across organizations. */
  readonly slug: string;
  readonly title: string;
  readonly description?: string;
  /** Default `false`: the public page returns nothing. */
  readonly published?: boolean;
}

/** One UTC day of a component's uptime history. */
export interface PublicUptimeDay {
  readonly date: Temporal.PlainDate;
  /** The worst status the component had that day. */
  readonly status: ComponentStatus;
  /** Minutes in a partial or major outage. */
  readonly downMinutes: number;
}

export interface PublicStatusComponent {
  readonly id: string;
  readonly name: string;
  readonly description?: string;
  readonly group?: string;
  readonly status: ComponentStatus;
  /** Time outside a partial or major outage over the window, in percent. */
  readonly uptimePercent: number;
  /** The oldest day first. */
  readonly uptime: readonly PublicUptimeDay[];
}

export interface PublicIncident {
  readonly id: string;
  readonly title: string;
  readonly severity: IncidentSeverity;
  readonly status: IncidentStatus;
  readonly startedAt: Temporal.Instant;
  readonly resolvedAt?: Temporal.Instant;
  /** Only the public components it affects. */
  readonly components: readonly {
    readonly id: string;
    readonly name: string;
    readonly impact: ComponentImpact;
  }[];
  /** Only the public updates, newest first. */
  readonly updates: readonly {
    readonly status: IncidentStatus;
    readonly body: string;
    readonly createdAt: Temporal.Instant;
  }[];
  readonly postmortem?: {
    readonly summary?: string;
    readonly publishedAt: Temporal.Instant;
  };
}

/** What anyone, signed in or not, reads from a published status page. */
export interface PublicStatusPage {
  readonly slug: string;
  readonly title: string;
  readonly description?: string;
  readonly days: number;
  /** The worst status of the public components. */
  readonly status: ComponentStatus;
  readonly components: readonly PublicStatusComponent[];
  /** Open public incidents, and those resolved in the window. */
  readonly incidents: readonly PublicIncident[];
}

export interface Incidents<F extends object = Record<never, never>> {
  /** Needs `incidents.manage`. */
  saveComponent(
    organizationId: string,
    input: StatusComponentInput,
  ): AsyncResult<StatusComponent>;
  /** Needs `incidents.manage`. */
  deleteComponent(componentId: string): AsyncResult<{ readonly id: string }>;
  components(organizationId: string): AsyncResult<readonly StatusComponent[]>;
  /** Needs `incidents.write`. */
  open(
    organizationId: string,
    input: IncidentInput<F>,
  ): AsyncResult<Incident<F>>;
  /** Needs `incidents.write`. */
  update(
    incidentId: string,
    changes: IncidentChanges<F>,
  ): AsyncResult<Incident<F>>;
  /**
   * Adds a timeline entry and moves the incident to its status; `resolved`
   * closes the incident and restores its components. Needs `incidents.write`.
   */
  postUpdate(
    incidentId: string,
    input: IncidentUpdateInput,
  ): AsyncResult<IncidentUpdate>;
  /** Replaces the affected components. Needs `incidents.write`. */
  setImpacts(
    incidentId: string,
    impacts: readonly IncidentImpactInput[],
  ): AsyncResult<Incident<F>>;
  get(incidentId: string): AsyncResult<IncidentDetail<F> | undefined>;
  /** Newest first. */
  list(
    organizationId: string,
    options?: IncidentListOptions,
  ): AsyncResult<readonly Incident<F>[]>;
  /** Creates or changes the draft. Needs `incidents.write`. */
  savePostmortem(
    incidentId: string,
    input: PostmortemInput,
  ): AsyncResult<Postmortem>;
  /** Needs `incidents.manage` and a resolved incident. */
  publishPostmortem(incidentId: string): AsyncResult<Postmortem>;
  /**
   * Adds an action item to a postmortem as a task, created through the tasks
   * block. Needs `incidents.write` and the tasks block's create permission.
   */
  addPostmortemAction(
    postmortemId: string,
    input: PostmortemActionInput,
  ): AsyncResult<PostmortemAction>;
  /**
   * Unlinks an action item and returns the postmortem; the task stays. Needs
   * `incidents.write`.
   */
  removePostmortemAction(actionId: string): AsyncResult<Postmortem>;
  /** Needs `incidents.manage`. */
  saveStatusPage(
    organizationId: string,
    input: StatusPageInput,
  ): AsyncResult<StatusPage>;
  statusPage(organizationId: string): AsyncResult<StatusPage | undefined>;
  /**
   * The published status page behind a slug, readable without signing in:
   * public components, their uptime over `days` (1 to 90, default 90) and
   * public incidents. `undefined` when no published page has the slug.
   */
  publicStatusPage(
    slug: string,
    days?: number,
  ): AsyncResult<PublicStatusPage | undefined>;
}

const SEVERITIES: readonly IncidentSeverity[] = [
  "sev1",
  "sev2",
  "sev3",
  "sev4",
];

const STATUSES: readonly IncidentStatus[] = [
  "investigating",
  "identified",
  "monitoring",
  "resolved",
];

const COMPONENT_STATUSES: readonly ComponentStatus[] = [
  "operational",
  "maintenance",
  "degraded",
  "partial_outage",
  "major_outage",
];

const IMPACTS: readonly ComponentImpact[] = [
  "maintenance",
  "degraded",
  "partial_outage",
  "major_outage",
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

const numberOf = (value: unknown): number =>
  typeof value === "number" ? value : Number(value ?? 0);

function componentOf(value: unknown, fn: string): StatusComponent {
  const row = recordOf(value, fn);

  return {
    id: textOf(row["id"]),
    organizationId: textOf(row["organizationId"]),
    name: textOf(row["name"]),
    public: row["public"] === true,
    status: enumOrThrow(row["status"], COMPONENT_STATUSES, "component status"),
    position: numberOf(row["position"]),
    createdAt: requiredInstant(row["createdAt"], "createdAt"),
    updatedAt: requiredInstant(row["updatedAt"], "updatedAt"),
    ...optional("description", optionalText(row["description"])),
    ...optional("group", optionalText(row["group"])),
  };
}

function incidentOf(value: unknown, fn: string): Incident {
  const row = recordOf(value, fn);

  return {
    id: textOf(row["id"]),
    organizationId: textOf(row["organizationId"]),
    title: textOf(row["title"]),
    severity: enumOrThrow(row["severity"], SEVERITIES, "incident severity"),
    status: enumOrThrow(row["status"], STATUSES, "incident status"),
    public: row["public"] === true,
    startedAt: requiredInstant(row["startedAt"], "startedAt"),
    createdAt: requiredInstant(row["createdAt"], "createdAt"),
    updatedAt: requiredInstant(row["updatedAt"], "updatedAt"),
    impacts: recordsOf(row["impacts"] ?? [], fn).map((impact) => ({
      componentId: textOf(impact["componentId"]),
      name: textOf(impact["name"]),
      impact: enumOrThrow(impact["impact"], IMPACTS, "component impact"),
    })),
    ...optional("description", optionalText(row["description"])),
    ...optional("commanderId", optionalText(row["commanderId"])),
    ...optional("resolvedAt", optionalInstant(row["resolvedAt"])),
    ...optional("createdBy", optionalText(row["createdBy"])),
    fields: isRecord(row["fields"]) ? row["fields"] : {},
  };
}

function updateOf(value: unknown, fn: string): IncidentUpdate {
  const row = recordOf(value, fn);

  return {
    id: textOf(row["id"]),
    incidentId: textOf(row["incidentId"]),
    status: enumOrThrow(row["status"], STATUSES, "incident status"),
    body: textOf(row["body"]),
    public: row["public"] === true,
    createdAt: requiredInstant(row["createdAt"], "createdAt"),
    ...optional("authorId", optionalText(row["authorId"])),
  };
}

function actionOf(value: unknown, fn: string): PostmortemAction {
  const row = recordOf(value, fn);

  return {
    id: textOf(row["id"]),
    postmortemId: textOf(row["postmortemId"]),
    taskId: textOf(row["taskId"]),
    title: textOf(row["title"]),
    state: textOf(row["state"]),
    ...optional("dueAt", optionalInstant(row["dueAt"])),
    ...optional("closedAt", optionalInstant(row["closedAt"])),
    ...optional("createdAt", optionalInstant(row["createdAt"])),
  };
}

function postmortemOf(value: unknown, fn: string): Postmortem {
  const row = recordOf(value, fn);
  const items = row["actionItems"];

  return {
    id: textOf(row["id"]),
    incidentId: textOf(row["incidentId"]),
    // oxlint-disable-next-line typescript/no-deprecated -- the deprecated list stays readable until 0.48.
    actionItems: Array.isArray(items) ? items : [],
    actions: recordsOf(row["actions"] ?? [], fn).map((action) =>
      actionOf(action, fn),
    ),
    status: enumOrThrow(
      row["status"],
      ["draft", "published"] as const,
      "postmortem status",
    ),
    createdAt: requiredInstant(row["createdAt"], "createdAt"),
    updatedAt: requiredInstant(row["updatedAt"], "updatedAt"),
    ...optional("summary", optionalText(row["summary"])),
    ...optional("impact", optionalText(row["impact"])),
    ...optional("rootCause", optionalText(row["rootCause"])),
    ...optional("resolution", optionalText(row["resolution"])),
    ...optional("publishedAt", optionalInstant(row["publishedAt"])),
    ...optional("authorId", optionalText(row["authorId"])),
  };
}

function detailOf(value: unknown, fn: string): IncidentDetail | undefined {
  if (value === null || value === undefined) {
    return undefined;
  }

  const row = recordOf(value, fn);
  const postmortem = row["postmortem"];

  return {
    ...incidentOf(row, fn),
    updates: recordsOf(row["updates"] ?? [], fn).map((item) =>
      updateOf(item, fn),
    ),
    ...optional(
      "postmortem",
      isRecord(postmortem) ? postmortemOf(postmortem, fn) : undefined,
    ),
  };
}

function pageOf(value: unknown, fn: string): StatusPage {
  const row = recordOf(value, fn);

  return {
    id: textOf(row["id"]),
    organizationId: textOf(row["organizationId"]),
    slug: textOf(row["slug"]),
    title: textOf(row["title"]),
    published: row["published"] === true,
    createdAt: requiredInstant(row["createdAt"], "createdAt"),
    updatedAt: requiredInstant(row["updatedAt"], "updatedAt"),
    ...optional("description", optionalText(row["description"])),
  };
}

function publicIncidentOf(
  row: Record<string, unknown>,
  fn: string,
): PublicIncident {
  const postmortem = row["postmortem"];

  return {
    id: textOf(row["id"]),
    title: textOf(row["title"]),
    severity: enumOrThrow(row["severity"], SEVERITIES, "incident severity"),
    status: enumOrThrow(row["status"], STATUSES, "incident status"),
    startedAt: requiredInstant(row["startedAt"], "startedAt"),
    components: recordsOf(row["components"] ?? [], fn).map((component) => ({
      id: textOf(component["id"]),
      name: textOf(component["name"]),
      impact: enumOrThrow(component["impact"], IMPACTS, "component impact"),
    })),
    updates: recordsOf(row["updates"] ?? [], fn).map((update) => ({
      status: enumOrThrow(update["status"], STATUSES, "incident status"),
      body: textOf(update["body"]),
      createdAt: requiredInstant(update["createdAt"], "createdAt"),
    })),
    ...optional("resolvedAt", optionalInstant(row["resolvedAt"])),
    ...optional(
      "postmortem",
      isRecord(postmortem)
        ? {
            publishedAt: requiredInstant(
              postmortem["publishedAt"],
              "publishedAt",
            ),
            ...optional("summary", optionalText(postmortem["summary"])),
          }
        : undefined,
    ),
  };
}

function publicComponentOf(
  row: Record<string, unknown>,
  fn: string,
): PublicStatusComponent {
  return {
    id: textOf(row["id"]),
    name: textOf(row["name"]),
    status: enumOrThrow(row["status"], COMPONENT_STATUSES, "component status"),
    uptimePercent: numberOf(row["uptimePercent"] ?? 100),
    uptime: recordsOf(row["uptime"] ?? [], fn).map((day) => ({
      date: temporal().PlainDate.from(textOf(day["date"])),
      status: enumOrThrow(
        day["status"],
        COMPONENT_STATUSES,
        "component status",
      ),
      downMinutes: numberOf(day["downMinutes"]),
    })),
    ...optional("description", optionalText(row["description"])),
    ...optional("group", optionalText(row["group"])),
  };
}

function publicPageOf(
  value: unknown,
  fn: string,
): PublicStatusPage | undefined {
  if (value === null || value === undefined) {
    return undefined;
  }

  const row = recordOf(value, fn);

  return {
    slug: textOf(row["slug"]),
    title: textOf(row["title"]),
    days: numberOf(row["days"]),
    status: enumOrThrow(row["status"], COMPONENT_STATUSES, "component status"),
    components: recordsOf(row["components"] ?? [], fn).map((component) =>
      publicComponentOf(component, fn),
    ),
    incidents: recordsOf(row["incidents"] ?? [], fn).map((incident) =>
      publicIncidentOf(incident, fn),
    ),
    ...optional("description", optionalText(row["description"])),
  };
}

const attrsOf = (
  input: Partial<IncidentInput<object>>,
): Record<string, unknown> => ({
  ...optional("title", input.title),
  ...optional("description", input.description),
  ...optional("severity", input.severity),
  ...optional("public", input.public),
  ...optional("commanderId", input.commanderId),
  ...optional("message", input.message),
  ...optional("impacts", input.impacts),
});

/** The `incidents` SQL module as typed calls. */
export function createIncidents<
  S extends StandardSchemaV1 | undefined = undefined,
>(options: IncidentsOptions<S>): Incidents<FieldsOf<S>> {
  type F = FieldsOf<S>;

  applyTemporal(options);
  const call = blockCall(options.transport, options.schema, options.mappers);

  const fields: BlockFields<F> = blockFields(options.fields, "incident fields");

  const incident = (fn: string) => (value: unknown) => incidentOf(value, fn);

  const postmortem = (fn: string) => (value: unknown) =>
    postmortemOf(value, fn);

  const client: Incidents<F> = {
    saveComponent: (organizationId, input) =>
      call(
        "save_status_component",
        {
          tenant: organizationId,
          name: input.name,
          description: input.description ?? null,
          group_name: input.group ?? null,
          is_public: input.public ?? true,
          sort_position: input.position ?? 0,
          component_id: input.componentId ?? null,
        },
        (value) => componentOf(value, "save_status_component"),
      ),
    deleteComponent: (componentId) =>
      call(
        "delete_status_component",
        { component_id: componentId },
        (value) => ({
          id: textOf(recordOf(value, "delete_status_component")["id"]),
        }),
      ),
    components: (organizationId) =>
      call("list_status_components", { tenant: organizationId }, (value) =>
        recordsOf(value, "list_status_components").map((row) =>
          componentOf(row, "list_status_components"),
        ),
      ),
    open: (organizationId, input) =>
      fields
        .args(input.fields)
        .andThen((checked) =>
          call(
            "open_incident",
            {
              tenant: organizationId,
              attrs: attrsOf(input),
              ...(checked === undefined ? {} : { fields: checked }),
            },
            incident("open_incident"),
          ).andThen(fields.row),
        ),
    update: (incidentId, changes) =>
      fields
        .args(changes.fields)
        .andThen((checked) =>
          call(
            "update_incident",
            {
              incident_id: incidentId,
              attrs: attrsOf(changes),
              ...(checked === undefined ? {} : { fields: checked }),
            },
            incident("update_incident"),
          ).andThen(fields.row),
        ),
    postUpdate: (incidentId, input) =>
      call(
        "post_incident_update",
        {
          incident_id: incidentId,
          status: input.status,
          body: input.body,
          is_public: input.public ?? null,
        },
        (value) => updateOf(value, "post_incident_update"),
      ),
    setImpacts: (incidentId, impacts) =>
      call(
        "set_incident_impacts",
        { incident_id: incidentId, impacts },
        incident("set_incident_impacts"),
      ).andThen(fields.row),
    get: (incidentId) =>
      call("get_incident", { incident_id: incidentId }, (value) =>
        detailOf(value, "get_incident"),
      ).andThen((row) =>
        row === undefined ? AsyncResult.ok(undefined) : fields.row(row),
      ),
    list: (organizationId, list = {}) =>
      call(
        "list_incidents",
        {
          tenant: organizationId,
          status: list.status ?? null,
          severity: list.severity ?? null,
          component_id: list.componentId ?? null,
          before: list.before === undefined ? null : instantArg(list.before),
          page_size: list.pageSize ?? null,
        },
        (value) =>
          recordsOf(value, "list_incidents").map((row) =>
            incidentOf(row, "list_incidents"),
          ),
      ).andThen(fields.rows),
    savePostmortem: (incidentId, input) =>
      call(
        "save_incident_postmortem",
        {
          incident_id: incidentId,
          attrs: {
            ...optional("summary", input.summary),
            ...optional("impact", input.impact),
            ...optional("rootCause", input.rootCause),
            ...optional("resolution", input.resolution),
            // oxlint-disable-next-line typescript/no-deprecated -- the client still sends the deprecated key until 0.48.
            ...optional("actionItems", input.actionItems),
          },
        },
        postmortem("save_incident_postmortem"),
      ),
    publishPostmortem: (incidentId) =>
      call(
        "publish_incident_postmortem",
        { incident_id: incidentId },
        postmortem("publish_incident_postmortem"),
      ),
    addPostmortemAction: (postmortemId, input) =>
      call(
        "add_incident_postmortem_action",
        {
          postmortem_id: postmortemId,
          title: input.title,
          assignee_id: input.assigneeId ?? null,
          due_at: input.dueAt === undefined ? null : instantArg(input.dueAt),
        },
        (value) => actionOf(value, "add_incident_postmortem_action"),
      ),
    removePostmortemAction: (actionId) =>
      call(
        "remove_incident_postmortem_action",
        { action_id: actionId },
        postmortem("remove_incident_postmortem_action"),
      ),
    saveStatusPage: (organizationId, input) =>
      call(
        "save_status_page",
        {
          tenant: organizationId,
          slug: input.slug,
          title: input.title,
          description: input.description ?? null,
          published: input.published ?? false,
        },
        (value) => pageOf(value, "save_status_page"),
      ),
    statusPage: (organizationId) =>
      call("get_status_page", { tenant: organizationId }, (value) =>
        value === null || value === undefined
          ? undefined
          : pageOf(value, "get_status_page"),
      ),
    publicStatusPage: (slug, days) =>
      call("public_status_page", { slug, days: days ?? null }, (value) =>
        publicPageOf(value, "public_status_page"),
      ),
  };

  return withBlockHooks(client, options.hooks, {
    block: "incidents",
    ...(options.logger ? { logger: options.logger } : {}),
  });
}
