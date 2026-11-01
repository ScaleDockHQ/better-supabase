import type { BlockContext } from "../create-blocks.ts";
import type { BlockOf, CompositeOptions } from "../define-block.ts";

import { coursesBlock } from "../courses/manifest.ts";
import { defineBlock } from "../define-block.ts";
import { enrollmentsBlock } from "../enrollments/manifest.ts";

/** The blocks `learning` is made of, by block name. */
export const learningParts: {
  readonly courses: typeof coursesBlock;
  readonly enrollments: typeof enrollmentsBlock;
} = { courses: coursesBlock, enrollments: enrollmentsBlock };

export type LearningParts = typeof learningParts;

/**
 * The `learning` composite (ADR 0177): courses and the enrollments that track
 * learners through them. It installs its parts and sets their defaults; the
 * parts stay ordinary blocks in the config.
 */
export const learningBlock: BlockOf<
  "learning",
  (options: BlockContext & CompositeOptions<LearningParts>) => undefined
> = defineBlock({
  name: "learning",
  composes: learningParts,
  category: "people",
});
