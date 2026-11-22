import { readFileSync } from "node:fs";
import { createRequire } from "node:module";
import { join } from "node:path";
import { pathToFileURL } from "node:url";

/** A range in a file, as UTF-16 offsets. */
export interface SymbolLocation {
  readonly file: string;
  readonly start: number;
  readonly end: number;
}

/** What the optional TypeScript 7.1 tier answers. */
export interface SymbolTier {
  /** The installed TypeScript version. */
  readonly version: string;
  /**
   * Every place the identifier at `offset` in `file` is used, across the
   * project's files, including its declaration. Empty when TypeScript does not
   * resolve a symbol there.
   */
  references(file: string, offset: number): readonly SymbolLocation[];
  /**
   * The declaration node (with leading trivia) of the symbol at `offset`,
   * possibly in another file.
   */
  declaration(file: string, offset: number): SymbolLocation | undefined;
  /** Stops the TypeScript process. */
  close(): void;
}

export type SymbolTierResult =
  | { readonly ok: true; readonly tier: SymbolTier }
  | { readonly ok: false; readonly reason: string };

/**
 * The part of `typescript/sync` and `typescript/ast` the tier calls, typed here
 * because the package is the app's own optional peer and the published types
 * never import it.
 */
interface TsNode {
  readonly pos: number;
  readonly end: number;
}

interface TsHandle {
  readonly path: string;
  resolve(): TsNode | undefined;
}

interface TsSymbol {
  readonly declarations: readonly TsHandle[];
}

interface TsProject {
  readonly program: {
    getSourceFile(file: string): { readonly text: string } | undefined;
  };
  readonly checker: { getSymbolAtLocation(node: TsNode): TsSymbol | undefined };
  readonly languageService: {
    getReferencedSymbolsForNode(
      node: TsNode,
      position: number,
    ): readonly { readonly references: readonly TsHandle[] }[];
  };
}

interface TsSnapshot {
  getDefaultProjectForFile(file: string): TsProject | undefined;
  dispose(): void;
}

interface TsApi {
  createSnapshot(params: { openFiles: readonly string[] }): TsSnapshot;
  close(): void;
}

interface TsSyncModule {
  readonly API: new (options: { cwd: string }) => TsApi;
}

interface TsAstModule {
  getTouchingPropertyName(
    sourceFile: { readonly text: string },
    position: number,
  ): TsNode;
}

/**
 * The first TypeScript release that has `typescript/sync` with a language
 * service.
 */
const MINIMUM = [7, 1] as const;

const isSyncModule = (value: unknown): value is TsSyncModule =>
  typeof value === "object" && value !== null && "API" in value;

const isAstModule = (value: unknown): value is TsAstModule =>
  typeof value === "object" &&
  value !== null &&
  "getTouchingPropertyName" in value;

/** True when `version` is at least `MINIMUM`. */
function supported(version: string): boolean {
  const [major = 0, minor = 0] = version.split(".").map(Number);

  return major > MINIMUM[0] || (major === MINIMUM[0] && minor >= MINIMUM[1]);
}

/**
 * Opens the symbol tier from the TypeScript the project at `root` has
 * installed. It never throws: a project without TypeScript 7.1 or newer gets a
 * reason, and every codemod then runs per file and reports where a symbol
 * leaves the file.
 */
export async function openSymbolTier(root: string): Promise<SymbolTierResult> {
  const require = createRequire(join(root, "package.json"));
  let version: string;

  try {
    const manifest: unknown = JSON.parse(
      readFileSync(require.resolve("typescript/package.json"), "utf-8"),
    );

    version =
      typeof manifest === "object" &&
      manifest !== null &&
      "version" in manifest &&
      typeof manifest.version === "string"
        ? manifest.version
        : "";
  } catch {
    return {
      ok: false,
      reason:
        "typescript is not installed here; install typescript 7.1 or newer for edits that follow a symbol across files",
    };
  }

  if (!supported(version)) {
    return {
      ok: false,
      reason: `typescript ${version} has no symbol API; typescript 7.1 or newer follows a symbol across files`,
    };
  }

  try {
    // The tier is optional: the specifier is a variable so a bundler leaves
    // it out, and a failure falls back to the per-file path above.
    const [sync, ast] = await Promise.all(
      ["typescript/sync", "typescript/ast"].map(
        (specifier): Promise<unknown> =>
          import(
            /* webpackIgnore: true */
            /* @vite-ignore */
            pathToFileURL(require.resolve(specifier)).href
          ),
      ),
    );

    if (!isSyncModule(sync) || !isAstModule(ast)) {
      return {
        ok: false,
        reason: `typescript ${version} does not export the symbol API the tier uses`,
      };
    }

    return {
      ok: true,
      tier: createTier(version, new sync.API({ cwd: root }), ast),
    };
  } catch (error) {
    return {
      ok: false,
      reason: `typescript ${version} did not start: ${error instanceof Error ? error.message : String(error)}`,
    };
  }
}

function createTier(version: string, api: TsApi, ast: TsAstModule): SymbolTier {
  const open = (file: string): TsProject | undefined =>
    api.createSnapshot({ openFiles: [file] }).getDefaultProjectForFile(file);

  const identifierAt = (
    file: string,
    offset: number,
  ): { project: TsProject; node: TsNode; name: string } | undefined => {
    const project = open(file);
    const sourceFile = project?.program.getSourceFile(file);

    if (project === undefined || sourceFile === undefined) {
      return undefined;
    }

    const node = ast.getTouchingPropertyName(sourceFile, offset);
    const name = sourceFile.text.slice(node.pos, node.end).trim();

    return /^[\w$]+$/.test(name) ? { project, node, name } : undefined;
  };

  // A reference node is an identifier whose range starts with trivia, so its
  // start is the end minus the name.
  const identifierRange = (
    handle: TsHandle,
    name: string,
  ): SymbolLocation | undefined => {
    const node = handle.resolve();

    return node === undefined
      ? undefined
      : { file: handle.path, start: node.end - name.length, end: node.end };
  };

  return {
    version,
    references(file, offset) {
      const found = identifierAt(file, offset);

      if (found === undefined) {
        return [];
      }

      return found.project.languageService
        .getReferencedSymbolsForNode(found.node, found.node.end - 1)
        .flatMap((entry) => entry.references)
        .flatMap((handle) => identifierRange(handle, found.name) ?? []);
    },
    declaration(file, offset) {
      const found = identifierAt(file, offset);

      const [first] =
        found?.project.checker.getSymbolAtLocation(found.node)?.declarations ??
        [];

      const node = first?.resolve();

      return node === undefined || first === undefined
        ? undefined
        : { file: first.path, start: node.pos, end: node.end };
    },
    close() {
      api.close();
    },
  };
}
