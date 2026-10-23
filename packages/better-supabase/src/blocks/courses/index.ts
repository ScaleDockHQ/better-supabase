export {
  createCourses,
  type Course,
  type CourseCertificate,
  type CourseCertificateCheck,
  type CourseInput,
  type CourseLearner,
  type CourseLearnersFilter,
  type CourseLearnerStatus,
  type CourseLesson,
  type CourseLessonInput,
  type CourseLessonKind,
  type CourseLessonView,
  type CourseModule,
  type CourseModuleInput,
  type CourseOutline,
  type CourseOutlineLesson,
  type CourseOutlineModule,
  type CourseQuiz,
  type CourseQuizResult,
  type Courses,
  type CoursesOptions,
  type CourseStatus,
  type LessonProgress,
} from "./courses.ts";

export {
  extendBlock,
  withBlockHooks,
  wrapTransport,
} from "../../core/block-hooks.ts";

export type {
  BlockHooks,
  BlockTransportMiddleware,
} from "../../core/block-hooks.ts";

export {
  dbTransport,
  rpcTransport,
  sqlTransport,
} from "../../core/block-transport.ts";

export type { BlockTransport, RpcClient } from "../../core/block-transport.ts";

export { coursesBlock } from "./manifest.ts";

export { coursesSqlOptions, type CoursesSqlOptions } from "./options.ts";

export {
  courseLearnersBinding,
  type CourseLearnersWrites,
} from "./record-binding.ts";

export {
  courseInputSchema,
  courseLearnerSectionInputSchema,
  courseLessonInputSchema,
  type CourseLearnerSectionInput,
} from "./schemas.ts";

export { coursesEvents } from "./events.ts";

export type {
  CourseCertificateEventData,
  CourseEventData,
  CourseLearnerEventData,
  CourseLessonCompletedEventData,
  CoursesEvents,
} from "./events.ts";
