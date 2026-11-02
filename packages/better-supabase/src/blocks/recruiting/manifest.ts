import type { BlockOf } from "../define-block.ts";

import { calendarBlock } from "../calendar/manifest.ts";
import { defineBlock } from "../define-block.ts";
import { employeesBlock } from "../employees/manifest.ts";
import { hiringBlock } from "../hiring/manifest.ts";
import { createRecruiting } from "./recruiting.ts";

/** The blocks `recruiting` is made of, by block name. */
export const recruitingParts: {
  readonly hiring: typeof hiringBlock;
  readonly employees: typeof employeesBlock;
  readonly calendar: typeof calendarBlock;
} = { hiring: hiringBlock, employees: employeesBlock, calendar: calendarBlock };

export type RecruitingParts = typeof recruitingParts;

/**
 * The `recruiting` composite (ADR 0196): hiring and interviews on the calendar,
 * with hires becoming employees. It installs its parts and sets their defaults;
 * the parts stay ordinary blocks in the config.
 */
export const recruitingBlock: BlockOf<"recruiting", typeof createRecruiting> =
  defineBlock({
    name: "recruiting",
    composes: recruitingParts,
    create: createRecruiting,
    category: "people",
  });
