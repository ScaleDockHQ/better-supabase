import type { TemplatesEvents } from "../../blocks/templates/events.ts";
import type { BlockSqlEvents, BlockSqlNames } from "../context.ts";

const EVENTS: BlockSqlEvents<TemplatesEvents> = {
  "template.published": {
    subject: "templates",
    payload: ["organizationId", "id", "versionId", "version", "type"],
  },
  "template.applied": {
    subject: "template-applications",
    payload: [
      "organizationId",
      "subjectType",
      "subjectId",
      "id",
      "templateId",
      "versionId",
    ],
  },
};

export const NAMES: BlockSqlNames = {
  entities: {
    template: { table: "templates", singular: "template", primary: true },
  },
  events: EVENTS,
  hooks: [
    "before_template_save",
    "after_template_save",
    "before_template_apply",
    "after_template_apply",
  ],
  options: ["extraColumns", "brand"],
  tables: {
    templates: {
      name: "templates",
      app: {},
      lifecycle: { tenant: "tenant", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        scope: "scope",
        brand: "brand",
        key: "key",
        type: "type",
        name: "name",
        language: "language",
        isDefault: "is_default",
        settings: "settings",
        forkedFrom: "forked_from",
        forkedFromVersion: "forked_from_version",
        createdBy: "created_by",
        createdAt: "created_at",
        updatedAt: "updated_at",
      },
      optional: [
        "scope",
        "brand",
        "key",
        "isDefault",
        "settings",
        "forkedFrom",
        "forkedFromVersion",
        "createdBy",
      ],
      typed: ["scope"],
    },
    versions: {
      name: "template_versions",
      app: {},
      columns: {
        id: "id",
        template: "template_id",
        version: "version",
        body: "body",
        hash: "hash",
        publishedAt: "published_at",
        createdBy: "created_by",
        createdAt: "created_at",
      },
      optional: ["createdBy"],
    },
    applications: {
      name: "template_applications",
      app: {},
      lifecycle: { tenant: "tenant", export: true },
      columns: {
        id: "id",
        template: "template_id",
        version: "version_id",
        tenant: "tenant_id",
        subjectType: "subject_type",
        subjectId: "subject_id",
        appliedBy: "applied_by",
        appliedAt: "applied_at",
      },
      optional: ["appliedBy"],
    },
    workflows: {
      name: "template_workflows",
      app: {},
      optional: ["enabled", "createdBy", "createdAt"],
      columns: {
        id: "id",
        template: "template_id",
        definition: "definition_id",
        inputs: "inputs",
        enabled: "enabled",
        createdBy: "created_by",
        createdAt: "created_at",
      },
    },
    schedules: {
      name: "template_schedules",
      optionalTable: true,
      app: {},
      lifecycle: { tenant: "tenant", user: "createdBy", export: true },
      optional: ["createdBy"],
      columns: {
        id: "id",
        template: "template_id",
        tenant: "tenant_id",
        input: "input",
        enabled: "enabled",
        createdBy: "created_by",
        createdAt: "created_at",
        updatedAt: "updated_at",
      },
    },
    runs: {
      name: "template_schedule_runs",
      optionalTable: true,
      app: {},
      lifecycle: { tenant: "tenant", export: true },
      columns: {
        schedule: "schedule_id",
        tenant: "tenant_id",
        occurrence: "occurrence_at",
        application: "application_id",
        createdAt: "created_at",
      },
    },
  },
};

/** The keys the template reads return next to the extra columns. */
export const RESERVED = ["fields"] as const;

export const TYPE_PATTERN = "'^[a-z][a-z0-9_.-]{0,63}$'";
export const KEY_PATTERN = "'^[a-z0-9][a-z0-9_.-]{0,99}$'";
export const LANGUAGE_PATTERN = "'^[a-z]{2,3}(-[A-Za-z0-9]{1,8})*$'";
export const MAX_BODY_BYTES = 1_048_576;
export const MAX_SETTINGS_BYTES = 65_536;
