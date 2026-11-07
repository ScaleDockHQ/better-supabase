import type { GenTask, IntegrationName } from "../config/index.ts";

import { GEN_TASKS, INTEGRATION_NAMES } from "../config/index.ts";
import { BUILT_IN_FRAMEWORKS } from "../plugins/index.ts";

export { GEN_TASKS };

/** The `gen.hooks` names that need no registration, from the built-in bindings. */
export const HOOK_FRAMEWORKS: readonly string[] = BUILT_IN_FRAMEWORKS.map(
  (binding) => binding.name,
);

export const INTEGRATIONS: readonly [IntegrationName, ...IntegrationName[]] =
  INTEGRATION_NAMES;

export const isGenTask = (value: string): value is GenTask =>
  GEN_TASKS.some((task) => task === value);
