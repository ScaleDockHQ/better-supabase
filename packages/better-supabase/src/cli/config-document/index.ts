export type { EditResult, Located, PathSegment, Style } from "./document.ts";

export { ConfigDocument } from "./document.ts";

export { propertyName } from "./nodes.ts";

export { parsePath } from "./path.ts";

export { lineColumn, parseModule } from "./parse.ts";

export type { SourceContext } from "./source.ts";

export { rewriteSource } from "./source.ts";

export type {
  FollowedDocument,
  FollowedImports,
  ImportedValue,
  ImportFollow,
} from "./follow.ts";

export {
  changedFiles,
  followedReview,
  followImports,
  importedValues,
  openImports,
  ownerOf,
} from "./follow.ts";
