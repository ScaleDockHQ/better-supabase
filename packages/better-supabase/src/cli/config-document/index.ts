export type { EditResult, Located, PathSegment, Style } from "./document.ts";

export { ConfigDocument } from "./document.ts";

export { propertyName } from "./nodes.ts";

export { parsePath } from "./path.ts";

export { lineColumn, parseModule } from "./parse.ts";

export type { SourceContext } from "./source.ts";

export { rewriteSource } from "./source.ts";

export type { FollowedDocument, ImportedValue } from "./follow.ts";

export { followImports, importedValues } from "./follow.ts";
