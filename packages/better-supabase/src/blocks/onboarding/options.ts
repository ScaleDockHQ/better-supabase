import type { BlockOptionsSchema } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/** `blocks.onboarding.options`. */
export type OnboardingSqlOptions = { readonly checklists?: unknown };

export const onboardingSqlOptions: BlockOptionsSchema<OnboardingSqlOptions> =
  blockOptions<OnboardingSqlOptions>({ checklists: option.unknown() });
