import type { BlockOptionsSchema } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/** `blocks.enrollments.options`. */
export type EnrollmentsSqlOptions = {
  /** The most steps one program may hold. */
  readonly maxSteps?: number;
};

export const enrollmentsSqlOptions: BlockOptionsSchema<EnrollmentsSqlOptions> =
  blockOptions<EnrollmentsSqlOptions>({
    maxSteps: option.number({ default: 100 }),
  });
