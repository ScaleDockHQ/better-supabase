import type { BlockHooks } from "../../core/block-hooks.ts";
import type { Logger } from "../../core/logger.ts";
import type { AsyncResult } from "../../core/result.ts";
import type { RecordRef } from "../../schema/types.ts";
import type { CourseLearner } from "../courses/index.ts";
import type { BlockContext } from "../create-blocks.ts";
import type { CompositeOptions } from "../define-block.ts";
import type { Enrollment, EnrollmentDates } from "../enrollments/index.ts";
import type { LearningParts } from "./manifest.ts";

import { withBlockHooks } from "../../core/block-hooks.ts";
import { AsyncResult as Async, ok } from "../../core/result.ts";

/** What `learning.assign` returns. */
export interface AssignedTraining {
  readonly learner: CourseLearner;
  /** The program enrollment, when `program` was given. */
  readonly enrollment: Enrollment | null;
}

/** The helpers `learning` adds over its parts. */
export interface Learning {
  /**
   * Enrolls the learner in the course (`courses.enroll`) and, with `program`
   * and `subject`, in the enrollment program that tracks it
   * (`enrollments.enroll`). A failed program enrollment returns its error and
   * leaves the learner in the course, so retry it with `enrollments.enroll`.
   */
  assign(input: {
    courseId: string;
    userId?: string | undefined;
    program?: string | undefined;
    subject?: RecordRef | undefined;
    dates?: EnrollmentDates | undefined;
  }): AsyncResult<AssignedTraining>;
}

/** What the `learning` creator receives. */
export type LearningOptions = BlockContext &
  CompositeOptions<LearningParts> & {
    /** `before` and `after` hooks per method (ADR 0015). */
    readonly hooks?: NoInfer<BlockHooks<Learning>>;
    /** Receives the errors `after` hooks throw. Default: `console`. */
    readonly logger?: Logger;
  };

/** Creates the `learning` helpers over the clients of its parts. */
export function createLearning(options: LearningOptions): Learning {
  const { courses, enrollments } = options.parts;

  const client: Learning = {
    assign: ({ courseId, userId, program, subject, dates }) =>
      Async.from<AssignedTraining>(async () => {
        const learner = await courses.enroll({
          courseId,
          ...(userId === undefined ? {} : { userId }),
        });

        if (!learner.ok) {
          return learner;
        }

        if (program === undefined || subject === undefined) {
          return ok({ learner: learner.data, enrollment: null });
        }

        const enrollment = await enrollments.enroll({
          program,
          subject,
          ...(dates === undefined ? {} : { dates }),
        });

        return enrollment.ok
          ? ok({ learner: learner.data, enrollment: enrollment.data })
          : enrollment;
      }),
  };

  return withBlockHooks(client, options.hooks, {
    block: "learning",
    ...(options.logger ? { logger: options.logger } : {}),
  });
}
