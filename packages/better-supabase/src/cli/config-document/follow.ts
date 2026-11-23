import type { ObjectExpression } from "oxc-parser";

import { readFileSync } from "node:fs";

import type { ProjectSymbols } from "../typescript-symbols/index.ts";
import type { ConfigDocument, PathSegment } from "./document.ts";

import { ConfigDocument as Document } from "./document.ts";
import { propertyName, unwrap } from "./nodes.ts";

/** A name the config imports and uses as a value or spread. */
export interface ImportedValue {
  readonly name: string;
  /** Where the identifier is used, in the text. */
  readonly offset: number;
  /** The config path the value sits at; empty for a spread at the root. */
  readonly path: readonly string[];
}

/** A part of the config that another file declares, as an editable document. */
export interface FollowedDocument {
  readonly file: string;
  readonly document: ConfigDocument;
  /** The config path the value sits at in the file that imports it. */
  readonly prefix: readonly string[];
}

/**
 * The imported names the config object uses as a value or a spread, with the
 * path each sits at. A value written in this file is not listed.
 */
export function importedValues(
  document: ConfigDocument,
): readonly ImportedValue[] {
  const imported = new Set<string>();

  for (const statement of document.program.body) {
    if (statement.type === "ImportDeclaration") {
      for (const specifier of statement.specifiers) {
        imported.add(specifier.local.name);
      }
    }
  }

  const found: ImportedValue[] = [];

  const visit = (
    object: ObjectExpression,
    prefix: readonly string[],
    depth: number,
  ): void => {
    for (const property of object.properties) {
      const value =
        property.type === "SpreadElement"
          ? unwrap(property.argument)
          : unwrap(property.value);

      const key =
        property.type === "SpreadElement" ? undefined : propertyName(property);

      const path =
        property.type === "SpreadElement"
          ? prefix
          : key === undefined
            ? undefined
            : [...prefix, key];

      if (path === undefined) {
        continue;
      }

      if (value.type === "Identifier" && imported.has(value.name)) {
        found.push({ name: value.name, offset: value.start, path });
      } else if (value.type === "ObjectExpression" && depth < 4) {
        visit(value, path, depth + 1);
      }
    }
  };

  const config = document.configObject();

  if (config !== undefined) {
    visit(config, [], 0);
  }

  return found;
}

/**
 * The files that declare the values `document` imports. With the symbol tier,
 * each imported value resolves to its declaration, which becomes a document of
 * its own. Without the tier, or when a value does not resolve, `review` says
 * why, so the caller can tell the person which file to change by hand.
 */
export function followImports(
  symbols: ProjectSymbols | undefined,
  configFile: string,
  document: ConfigDocument,
): { followed: FollowedDocument[]; review: string[] } {
  const imported = importedValues(document);
  const followed: FollowedDocument[] = [];
  const review: string[] = [];

  if (imported.length === 0) {
    return { followed, review };
  }

  if (symbols === undefined || "skipped" in symbols) {
    const reason =
      symbols === undefined
        ? "the TypeScript symbol tier is off"
        : symbols.skipped;

    return {
      followed,
      review: [
        `${configFile}: ${imported.map((value) => value.name).join(", ")} come from other files, which the codemod did not read (${reason}); change them by hand, or install typescript 7.1 or later.`,
      ],
    };
  }

  for (const value of imported) {
    const at = symbols.tier.declaration(configFile, value.offset);

    if (at === undefined) {
      review.push(
        `${configFile}: TypeScript does not resolve the imported ${value.name}; change its file by hand.`,
      );
      continue;
    }

    try {
      const { file } = at;

      followed.push({
        file,
        document: Document.parseDeclared(readFileSync(file, "utf-8"), file, at),
        prefix: value.path,
      });
    } catch (cause) {
      review.push(
        `${at.file}: ${cause instanceof Error ? cause.message : String(cause)}; change ${value.name} by hand.`,
      );
    }
  }

  return { followed, review };
}

/** What lets an edit follow a value the config imports from another file. */
export interface ImportFollow {
  readonly symbols: ProjectSymbols | undefined;
  readonly configFile: string;
}

/** The imports an edit followed, and why it could not follow the others. */
export interface FollowedImports {
  readonly followed: readonly FollowedDocument[];
  readonly review: readonly string[];
}

/**
 * The followed document that holds the config entry at `path`, with the path
 * inside it, or `undefined` when no followed value sits above the entry.
 */
export function ownerOf(
  imports: FollowedImports | undefined,
  path: readonly PathSegment[],
): { owner: FollowedDocument; inner: PathSegment[] } | undefined {
  const owner = imports?.followed.find(
    ({ prefix }) =>
      prefix.length <= path.length &&
      prefix.every((segment, index) => segment === path[index]),
  );

  return owner === undefined
    ? undefined
    : { owner, inner: path.slice(owner.prefix.length) };
}

/** The followed files whose text an edit changed, with the new text. */
export function changedFiles(
  imports: FollowedImports | undefined,
): { readonly file: string; readonly text: string }[] {
  return (imports?.followed ?? [])
    .filter(
      ({ document, file }) => document.text !== readFileSync(file, "utf-8"),
    )
    .map(({ file, document }) => ({ file, text: document.text }));
}

/** The review lines of the followed documents' own edits. */
export const followedReview = (
  imports: FollowedImports | undefined,
): string[] => [
  ...(imports?.review ?? []),
  ...(imports?.followed.flatMap(({ document }) => document.review) ?? []),
];

/**
 * Opens `follow`'s imports of `document`, or nothing when the edit does not
 * follow imports.
 */
export const openImports = (
  follow: ImportFollow | undefined,
  document: ConfigDocument,
): FollowedImports | undefined =>
  follow === undefined
    ? undefined
    : followImports(follow.symbols, follow.configFile, document);
