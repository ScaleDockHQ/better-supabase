export {
  createSubjects,
  type ResolvedSubject,
  SUBJECT_TITLES_LIMIT,
  type Subjects,
  type SubjectsOptions,
} from "./subjects.ts";

export { subjectsBlock } from "./manifest.ts";

export { subjectKey } from "../../core/block-subjects.ts";

export type { SubjectRef } from "../../schema/types.ts";

export {
  dbTransport,
  rpcTransport,
  sqlTransport,
} from "../../core/block-transport.ts";

export type { BlockTransport } from "../../core/block-transport.ts";

export { batchSubjects, createSubjectsController } from "./client.ts";

export type {
  SubjectsActions,
  SubjectsController,
  SubjectsControllerOptions,
  SubjectsSnapshot,
} from "./client.ts";
