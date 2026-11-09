import type { ImportsEvents } from "../../blocks/imports/events.ts";
import type { BlockSqlEvents, BlockSqlNames } from "../context.ts";

import { CHUNK_TABLE } from "./imports-chunks.ts";

const EVENTS: BlockSqlEvents<ImportsEvents> = {
  "import.completed": {
    subject: "imports",
    payload: ["organizationId", "id", "count"],
  },
  "import.failed": {
    subject: "imports",
    payload: ["organizationId", "id", "error"],
  },
  "import.entity_completed": {
    subject: "imports",
    payload: ["organizationId", "id", "entity", "counts"],
  },
};

/** Tables, events and the source-column migration of the imports module. */
export const IMPORT_NAMES: BlockSqlNames = {
  events: EVENTS,
  options: ["targets", "events", "audit"],
  migrations: [
    {
      from: 1,
      description:
        "An import run names its source instead of its kind (ADR 0141).",
      table: "runs",
      columns: { source: "kind" },
    },
  ],
  tables: {
    runs: {
      name: "import_runs",
      app: {},
      lifecycle: { tenant: "tenant", user: "createdBy", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        source: "source",
        status: "status",
        mapping: "mapping",
        counts: "counts",
        errors: "errors",
        diff: "diff",
        dryRun: "dry_run",
        full: "full",
        inputChecksum: "input_checksum",
        correlationId: "correlation_id",
        mapperVersion: "mapper_version",
        scopeAliases: "scope_aliases",
        plan: "plan",
        outcome: "outcome",
        leaseUntil: "lease_until",
        heartbeatAt: "heartbeat_at",
        createdBy: "created_by",
        createdAt: "created_at",
        startedAt: "started_at",
        finishedAt: "finished_at",
      },
      typed: ["status"],
    },
    records: {
      name: "import_records",
      app: {},
      lifecycle: { tenant: "tenant", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        source: "source",
        scope: "scope",
        entity: "entity",
        externalKey: "external_key",
        role: "role",
        subjectType: "subject_type",
        subjectId: "subject_id",
        contentHash: "content_hash",
        firstRun: "first_run_id",
        lastRun: "last_run_id",
        subjectUpdatedAt: "subject_imported_updated_at",
        sourceUpdatedAt: "source_updated_at",
        ownedHash: "owned_hash",
        missingSince: "went_missing_at",
      },
    },
    chunks: CHUNK_TABLE,
    refs: {
      name: "import_refs",
      app: {},
      columns: {
        id: "id",
        tenant: "tenant_id",
        kind: "kind",
        key: "key",
        payload: "payload",
        createdAt: "created_at",
      },
    },
    issues: {
      name: "import_run_issues",
      app: {},
      columns: {
        id: "id",
        run: "run_id",
        tenant: "tenant_id",
        source: "source",
        entity: "entity",
        key: "key",
        kind: "kind",
        code: "code",
        message: "message",
        createdAt: "created_at",
        resolvedAt: "resolved_at",
      },
      optional: ["resolvedAt"],
    },
    sources: {
      name: "import_sources",
      app: {},
      columns: {
        id: "id",
        labelKey: "label_key",
        descriptionKey: "description_key",
        fileTypes: "file_types",
        entities: "entities",
        docsLink: "docs_link",
      },
      optional: ["docsLink"],
    },
  },
};
