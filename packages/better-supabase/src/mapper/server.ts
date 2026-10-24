import type { FileDiagnostic, LoadedProject } from "./project.ts";
import type { Handlers } from "./rpc.ts";

import {
  EMPTY_MODULE,
  loadProject,
  MAPPER_CODES,
  realPath,
} from "./project.ts";

/** The protocol version this mapper speaks, as `initialize` answers it. */
export const PROTOCOL_VERSION = 1;

type Encoding = "utf-8" | "utf-16";

/** The `mappings` span kind and the feature flags one span carries. */
const ATOM = 1;
const DEFINITION = 8;
const TYPE_DEFINITION = 16;
const IMPLEMENTATION = 32;
const NAVIGATION = DEFINITION + TYPE_DEFINITION + IMPLEMENTATION;

const isRecord = (value: unknown): value is Record<string, unknown> =>
  typeof value === "object" && value !== null && !Array.isArray(value);

const field = (params: unknown, key: string): unknown =>
  isRecord(params) ? params[key] : undefined;

const text = (params: unknown, key: string): string => {
  const value = field(params, key);

  return typeof value === "string" ? value : "";
};

export interface MapperOptions {
  /** The environment the config and the source read. */
  readonly env?: Readonly<Record<string, string | undefined>>;
  /** Loads a project; tests replace it. */
  readonly load?: typeof loadProject;
}

/**
 * The content mapper's methods. `openProject` does the work (the config, the
 * snapshot and the render, all cached), so `transform` only hands back the
 * module for the project.
 */
export function mapperHandlers(options: MapperOptions = {}): Handlers {
  const env = options.env ?? {};
  const load = options.load ?? loadProject;
  const projects = new Map<string, Promise<LoadedProject>>();
  let encoding: Encoding = "utf-16";

  const size = (value: string): number =>
    encoding === "utf-8" ? Buffer.byteLength(value, "utf-8") : value.length;

  /** A diagnostic on the file, kept inside its `content`. */
  const onFile = (content: string, diagnostic: FileDiagnostic) => ({
    ...diagnostic,
    start: 0,
    length: Math.min(1, size(content)),
  });

  const module = (
    source: string,
    content: string,
    diagnostics: readonly FileDiagnostic[],
  ) => ({
    extension: ".ts",
    text: source,
    mappings: [[0, size(source), 0, size(content), ATOM, NAVIGATION]],
    diagnostics: diagnostics.map((diagnostic) => onFile(content, diagnostic)),
  });

  return {
    initialize(params) {
      const offered = field(params, "positionEncodings");
      const version = field(params, "protocolVersion");

      encoding =
        Array.isArray(offered) && !offered.includes("utf-16")
          ? "utf-8"
          : "utf-16";

      return {
        protocolVersion:
          typeof version === "number" ? version : PROTOCOL_VERSION,
        positionEncoding: encoding,
        diagnosticSource: "BS",
      };
    },

    async openProject(params) {
      const handle = text(params, "projectHandle");
      const entry = field(params, "options");

      const loaded = load(
        text(params, "configFileName"),
        isRecord(entry) ? entry : {},
        env,
      );

      projects.set(handle, loaded);
      const project = await loaded;

      return {
        configIdentity: project.configIdentity,
        watchedFiles: project.watchedFiles,
        optionDiagnostics: project.optionDiagnostics,
      };
    },

    async transform(params) {
      const content = text(params, "content");
      const loaded = projects.get(text(params, "projectHandle"));

      if (loaded === undefined) {
        return module(EMPTY_MODULE, content, [
          {
            messageText:
              "The content mapper has no project for this file. Restart the TypeScript server.",
            code: MAPPER_CODES.noTypes,
          },
        ]);
      }

      const project = await loaded;
      const fileName = realPath(text(params, "fileName"));

      if (project.file !== undefined && fileName !== project.file) {
        return module(EMPTY_MODULE, content, [
          {
            messageText: `better-supabase serves the schema types at ${project.file}, the schema.bsb next to gen's output. Import the types from there.`,
            code: MAPPER_CODES.otherFile,
          },
        ]);
      }

      return module(project.text, content, project.diagnostics);
    },

    closeProject(params) {
      projects.delete(text(params, "projectHandle"));

      return null;
    },
  };
}
