import type { DriveNode } from "./drive.ts";

export type DriveFileType =
  | "folder"
  | "image"
  | "video"
  | "audio"
  | "pdf"
  | "document"
  | "spreadsheet"
  | "presentation"
  | "archive"
  | "code"
  | "text"
  | "other";

const BY_EXTENSION: Readonly<Record<string, DriveFileType>> = {
  pdf: "pdf",
  doc: "document",
  docx: "document",
  odt: "document",
  rtf: "document",
  pages: "document",
  xls: "spreadsheet",
  xlsx: "spreadsheet",
  ods: "spreadsheet",
  csv: "spreadsheet",
  numbers: "spreadsheet",
  ppt: "presentation",
  pptx: "presentation",
  odp: "presentation",
  key: "presentation",
  zip: "archive",
  gz: "archive",
  tar: "archive",
  tgz: "archive",
  rar: "archive",
  "7z": "archive",
  js: "code",
  jsx: "code",
  ts: "code",
  tsx: "code",
  json: "code",
  sql: "code",
  py: "code",
  rb: "code",
  go: "code",
  rs: "code",
  java: "code",
  html: "code",
  css: "code",
  yaml: "code",
  yml: "code",
  sh: "code",
  txt: "text",
  md: "text",
  log: "text",
};

const BY_MIME: readonly (readonly [RegExp, DriveFileType])[] = [
  [/^image\//, "image"],
  [/^video\//, "video"],
  [/^audio\//, "audio"],
  [/^application\/pdf$/, "pdf"],
  [/(spreadsheet|excel|csv)/, "spreadsheet"],
  [/(presentation|powerpoint)/, "presentation"],
  [/(wordprocessing|msword|opendocument\.text|rtf)/, "document"],
  [/(zip|gzip|x-tar|x-7z|x-rar|compressed)/, "archive"],
  [/(javascript|typescript|json|xml|x-sh|sql|yaml)/, "code"],
  [/^text\//, "text"],
];

/**
 * A category for an icon or a filter, from the MIME type and then the
 * extension. Folders are `folder`; anything unknown is `other`.
 */
export function fileTypeCategory(
  mimeType: string | undefined,
  name = "",
): DriveFileType {
  const mime = (mimeType ?? "").toLowerCase().split(";")[0]?.trim() ?? "";
  if (mime === "inode/directory") return "folder";
  const extension = /\.([a-z0-9]+)$/i.exec(name)?.[1]?.toLowerCase();
  const known = extension === undefined ? undefined : BY_EXTENSION[extension];
  if (mime === "" || mime === "application/octet-stream") {
    return known ?? "other";
  }
  for (const [pattern, type] of BY_MIME) {
    if (pattern.test(mime)) {
      return type === "text" && known !== undefined ? known : type;
    }
  }
  return known ?? "other";
}

/** The category of a node: `folder`, or its file's type. */
export function nodeType(node: DriveNode): DriveFileType {
  return node.kind === "folder"
    ? "folder"
    : fileTypeCategory(node.file?.mimeType, node.name);
}

/** The root of a `driveTree`: the drive's top level. */
export const DRIVE_ROOT = "root";

/**
 * Loaded nodes as tree data, in the `dataLoader` shape tree components
 * built on headless-tree (such as ReUI's tree) take: `getItem`,
 * `getChildren`, plus `isFolder` and `name` for `isItemFolder` and
 * `getItemName`. Children keep the order the nodes came in.
 */
export interface DriveTreeData {
  readonly rootItemId: string;
  getItem(id: string): DriveNode | undefined;
  getChildren(id: string): string[];
  isFolder(id: string): boolean;
  name(id: string): string;
}

export function driveTree(
  nodes: readonly DriveNode[],
  rootId: string | null = null,
): DriveTreeData {
  const byId = new Map(nodes.map((node) => [node.id, node]));
  const children = new Map<string, string[]>();
  const root = rootId ?? DRIVE_ROOT;
  for (const node of nodes) {
    const parent = node.parentId ?? DRIVE_ROOT;
    const list = children.get(parent);
    if (list === undefined) children.set(parent, [node.id]);
    else list.push(node.id);
  }
  return {
    rootItemId: root,
    getItem: (id) => byId.get(id),
    getChildren: (id) => [...(children.get(id) ?? [])],
    isFolder: (id) => id === root || byId.get(id)?.kind === "folder",
    name: (id) => byId.get(id)?.name ?? "",
  };
}
