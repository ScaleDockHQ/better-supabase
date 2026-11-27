import type { BlockOptionsSchema } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/** `blocks.projects.options`. */
export type ProjectsSqlOptions = {
  /**
   * How often a project with a stale health is reminded, as a Postgres
   * interval. An empty string sends no reminder.
   */
  readonly updateEvery?: string;
};

export const projectsSqlOptions: BlockOptionsSchema<ProjectsSqlOptions> =
  blockOptions<ProjectsSqlOptions>({
    updateEvery: option.string({ default: "" }),
  });
