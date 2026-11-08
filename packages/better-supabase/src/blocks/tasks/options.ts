import type { BlockOptionsSchema } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/** `blocks.tasks.options`. */
export type TasksSqlOptions = {
  readonly prefix?: string;
  readonly maxAssignees?: number;
  /** Whether an item's author can delete it without the delete key. */
  readonly authorCanDelete?: boolean;
  readonly notify?: boolean;
  readonly actionPath?: string;
  /**
   * Adds a stored `search_tsv` column and a GIN index to work items, so queries
   * match with `search_tsv @@ websearch_to_tsquery('simple', ...)`. Default
   * `false`.
   */
  readonly searchColumn?: boolean;
  /**
   * Rows with `template_id` set are templates: they take no number, no search
   * document, no pipeline history and no domain events. Needs the templates
   * block. ADR 0244.
   */
  readonly templates?: boolean;
};

export const tasksSqlOptions: BlockOptionsSchema<TasksSqlOptions> =
  blockOptions<TasksSqlOptions>({
    prefix: option.string({ default: "TASK-" }),
    maxAssignees: option.number({ default: 0 }),
    authorCanDelete: option.boolean({ default: true }),
    notify: option.boolean({ default: true }),
    actionPath: option.string(),
    searchColumn: option.boolean({ default: false }),
    templates: option.boolean({ default: false }),
  });
