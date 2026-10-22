export type {
  TagRefInput,
  TagsOptimisticAction,
  TagsWrites,
} from "./section.ts";

export {
  createTags,
  type CreateTagInput,
  type ListTagsParams,
  type Tag,
  type Tags,
  type TagsOptions,
  type UpdateTagInput,
} from "./tags.ts";

export {
  createTagInputController,
  type TagChange,
  type TagInputActions,
  type TagInputController,
  type TagInputControllerOptions,
  type TagInputSnapshot,
} from "./client.ts";

export { tagsBlock } from "./manifest.ts";

export { tagRefInput, tagsOptimistic, tagsSection } from "./section.ts";

export { tagsEvents } from "./events.ts";

export type { TagsEvents } from "./events.ts";
