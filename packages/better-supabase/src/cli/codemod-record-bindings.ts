/** Blocks whose record section export became `<block>Binding` in 0.15. */
const BLOCK_BINDINGS = [
  "comments",
  "attachments",
  "tags",
  "shareLinks",
  "ledger",
  "assets",
  "scores",
  "moderation",
  "enrollments",
  "relations",
  "versions",
  "workItemChecklist",
  "sla",
  "guests",
  "passes",
  "billableTime",
  "courseLearners",
  "contracts",
  "dispatch",
  "shipments",
  "leases",
  "giving",
] as const;

/** Section types that became record binding types in 0.15. */
const BINDING_TYPES = [
  "Data",
  "Definition",
  "Options",
  "Permissions",
  "Result",
  "Write",
  "WriteInput",
  "WriteName",
  "WriteOutput",
  "Writes",
] as const;

/** The 0.14 record section and feature exports, with their 0.15 names. */
export const RECORD_BINDING_RENAMES: Readonly<Record<string, string>> = {
  ...Object.fromEntries(
    BLOCK_BINDINGS.map((block) => [`${block}Section`, `${block}Binding`]),
  ),
  ...Object.fromEntries(
    BINDING_TYPES.map((suffix) => [
      `Section${suffix}`,
      `RecordBinding${suffix}`,
    ]),
  ),
  Section: "RecordBinding",
  AnySection: "AnyRecordBinding",
  AnySectionWrite: "AnyRecordBindingWrite",
  SectionBlocks: "BindingBlocks",
  SectionCheck: "BindingCheck",
  SectionName: "BindingName",
  SectionSource: "BindingSource",
  SectionWritesOf: "BindingWritesOf",
  SectionRowInput: "RecordRowInput",
  LoadedSections: "LoadedBindings",
  LoadSectionsOptions: "LoadBindingsOptions",
  PlainSection: "PlainBinding",
  PlainSections: "PlainBindings",
  RecordFeature: "RecordType",
  RecordFeatureSpec: "RecordTypeSpec",
  FeatureBlocks: "RecordTypeBlocks",
  FeaturePermissions: "RecordTypePermissions",
  FeatureWriteInput: "RecordTypeWriteInput",
  FeatureWriteOutput: "RecordTypeWriteOutput",
  RecordSectionQueries: "RecordBindingQueries",
  TestSectionOptions: "TestRecordBindingOptions",
  countSection: "countBinding",
  defineRecordFeature: "defineRecordType",
  defineSection: "defineRecordBinding",
  findSectionWrite: "findBindingWrite",
  loadSections: "loadBindings",
  sectionCan: "bindingCan",
  sectionEventMatches: "recordEventMatches",
  sectionRowInput: "recordRowInput",
  sectionWrite: "recordBindingWrite",
  timelineSections: "timelineBindings",
  sectionTag: "bindingTag",
  invalidateSection: "invalidateBinding",
  testSection: "testRecordBinding",
};

/** `generateFeatures`, flat or under `gen`, renamed to `recordTypes`. */
export function withRecordTypes(source: string): string {
  return source.replaceAll(
    /(["']?)\bgenerateFeatures\1(\s*:)/g,
    "$1recordTypes$1$2",
  );
}
