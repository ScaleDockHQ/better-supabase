export type { TagsOptimisticAction } from "./section.ts";

export { createTags, type Tag, type Tags, type TagsOptions } from "./tags.ts";

export {
  createTagInputController,
  type TagChange,
  type TagInputActions,
  type TagInputController,
  type TagInputControllerOptions,
  type TagInputSnapshot,
} from "./client.ts";

export { tagsBlock } from "./manifest.ts";

export { tagsOptimistic, tagsSection } from "./section.ts";

export { tagsEvents } from "./events.ts";

export type { TagsEvents } from "./events.ts";
