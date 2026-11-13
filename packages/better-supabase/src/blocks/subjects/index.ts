export {
  createSubjects,
  labelsOf,
  MY_WORK_LIMIT,
  type MyTask,
  type MyWorkOptions,
  type ResolvedSubject,
  type SubjectLabel,
  SUBJECT_TITLES_LIMIT,
  type Subjects,
  type SubjectsOptions,
} from "./subjects.ts";

export { MY_WORK_KINDS, type MyWorkKind } from "./my-work-kinds.ts";

export {
  type EndSubjectMemberOptions,
  MY_SUBJECTS_LIMIT,
  type MySubject,
  type MySubjectsOptions,
  type MySubjectsPage,
  type SubjectMember,
  type SubjectMemberInput,
  type SubjectMembers,
} from "./members.ts";

export {
  SUBJECT_ACCESS_LOG_LIMIT,
  type SubjectAccessLogOptions,
  type SubjectRead,
  type SubjectReadOptions,
  type SubjectReads,
} from "./reads.ts";

export { subjectsEvents } from "./events.ts";

export type { SubjectsEvents } from "./events.ts";

export type {
  SubjectAccessedEventData,
  SubjectMemberEventData,
} from "../../core/block-events.ts";

export { subjectsBlock } from "./manifest.ts";

export { subjectKey } from "../../core/block-subjects.ts";

export {
  createPartyResolver,
  initialsOf,
  type Party,
  type PartyLabel,
  type PartyLabeler,
  type PartyProfile,
  type PartyReader,
  type PartyResolver,
  type PartyResolverOptions,
} from "../../core/party.ts";

export type { RecordRef } from "../../schema/types.ts";

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
