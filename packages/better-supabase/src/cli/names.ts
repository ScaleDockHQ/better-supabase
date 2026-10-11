import type { GenTask, IntegrationName } from "../config/index.ts";

import { GEN_TASKS, INTEGRATION_NAMES } from "../config/index.ts";

export { GEN_TASKS };

export const INTEGRATIONS: readonly [IntegrationName, ...IntegrationName[]] =
  INTEGRATION_NAMES;

export const isGenTask = (value: string): value is GenTask =>
  GEN_TASKS.some((task) => task === value);
