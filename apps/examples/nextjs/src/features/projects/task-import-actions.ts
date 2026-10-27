"use server";

import type {
  ImportPreview,
  ImportRowError,
} from "better-supabase/blocks/imports";

import { DbException, err, ok } from "better-supabase";
import {
  appTableImport,
  previewImport,
  runImport,
} from "better-supabase/blocks/imports";
import * as v from "valibot";

import { importRunHooks } from "@/features/imports/import-run";
import { getPermissions } from "@/features/user/permission-snapshot";
import { can } from "@/features/user/user-permissions";
import { refreshCaller } from "@/lib/refresh-caller";
import { bsb } from "@/lib/supabase/server";

import type { TaskStatus } from "./project-types";

import { TASK_IMPORT_FIELDS, TaskStatusSchema } from "./project-types";

const PREVIEW_ROWS = 20;

/** An empty cell is a left-out value, so the column default applies. */
const optionalCell = <const T extends v.GenericSchema<string, string>>(
  schema: T,
) =>
  v.pipe(
    v.optional(v.string(), ""),
    v.trim(),
    v.transform((cell) => (cell === "" ? undefined : cell)),
    v.optional(schema),
  );

/** A task the import writes; a left-out field keeps its column default. */
interface TaskInsert {
  title: string;
  projectId: string;
  organizationId: string;
  status?: TaskStatus;
  dueOn?: string;
}

/** A CSV row as a task of the project the import runs in. */
function taskRow(projectId: string, organizationId: string) {
  return v.pipe(
    v.object({
      title: v.pipe(v.string(), v.trim(), v.minLength(1), v.maxLength(200)),
      status: optionalCell(TaskStatusSchema),
      dueOn: optionalCell(v.pipe(v.string(), v.isoDate())),
    }),
    v.transform(({ title, status, dueOn }) => {
      const task: TaskInsert = { title, projectId, organizationId };

      if (status !== undefined) {
        task.status = status;
      }

      if (dueOn !== undefined) {
        task.dueOn = dueOn;
      }

      return task;
    }),
  );
}

type TaskImportRow = v.InferOutput<ReturnType<typeof taskRow>>;

const Input = v.object({
  projectId: v.pipe(v.string(), v.uuid()),
  csv: v.pipe(v.string(), v.minLength(1), v.maxLength(500_000)),
  mapping: v.record(v.string(), v.picklist(TASK_IMPORT_FIELDS)),
});

export interface TaskImportPreview extends ImportPreview {
  readonly rows: readonly TaskImportRow[];
  readonly errors: readonly ImportRowError[];
}

export interface TaskImportOutcome {
  readonly status: "completed" | "failed";
  readonly imported: number;
  readonly errors: readonly ImportRowError[];
}

/**
 * Validates the file and counts the tasks it creates, changes and leaves. A
 * task with the same title in the project is the same task (the `(project_id,
 * title)` unique set). Nothing is written.
 */
export const previewTaskImport = bsb.action(
  {
    input: Input,
    requireTenant: true,
    authorize: async () => can(await getPermissions(), "imports.manage"),
  },
  async ({ projectId, csv, mapping }, { tenant, db }) => {
    const definition = appTableImport({
      table: "tasks",
      columns: taskRow(projectId, tenant),
      repository: db.tasks,
      key: ["projectId", "title"],
    });

    const result = await previewImport(definition, csv, mapping);

    return ok<TaskImportPreview>({
      ...result.preview,
      rows: result.rows.slice(0, PREVIEW_ROWS),
      errors: result.errors,
    });
  },
);

/**
 * Upserts the file's tasks into the project. An existing task keeps the fields
 * it already has and gains the ones that were empty (`fill`).
 */
export const runTaskImport = bsb.action(
  {
    input: Input,
    requireTenant: true,
    authorize: async () => can(await getPermissions(), "imports.manage"),
  },
  async ({ projectId, csv, mapping }, { tenant, db, auth }) => {
    const definition = appTableImport({
      table: "tasks",
      columns: taskRow(projectId, tenant),
      repository: db.tasks,
      key: ["projectId", "title"],
    });

    const hooks = importRunHooks(db, tenant, "tasks", mapping);

    try {
      const result = await runImport(definition, csv, mapping, hooks);

      refreshCaller(auth);

      return ok<TaskImportOutcome>({
        status: result.status,
        imported: result.imported,
        errors: result.errors,
      });
    } catch (error) {
      if (!(error instanceof DbException)) {
        throw error;
      }

      await hooks.fail(error.message);

      return err(error.error);
    }
  },
);
