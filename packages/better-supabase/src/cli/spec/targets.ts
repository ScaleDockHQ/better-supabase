import type { ResolvedConfig } from "../../config/index.ts";
import type { AnyDocumentFormat, SpecUi } from "../../spec/index.ts";
import type { SpecSerialization } from "./text.ts";

import { serializationOf } from "./text.ts";

type SpecOutputConfig = ResolvedConfig["specs"]["outputs"][number];

/** One document to render: a format, a version and where it goes. */
export interface SpecTarget {
  readonly format: AnyDocumentFormat;
  readonly version: string;
  /** Relative to the project root. */
  readonly output: string;
  readonly serialization: SpecSerialization;
  readonly overlays: readonly string[];
  readonly ui?: SpecUi;
}

/** What the command line narrows or overrides. */
export interface TargetFilter {
  readonly format?: string;
  readonly version?: string;
  readonly out?: string;
  readonly yaml?: boolean;
  readonly ui?: SpecUi;
}

export class TargetError extends Error {
  readonly code: "format-unknown" | "version-unknown" | "usage";
  constructor(code: TargetError["code"], message: string) {
    super(message);
    this.code = code;
  }
}

function defaultOutput(
  format: AnyDocumentFormat,
  version: string,
  serialization: SpecSerialization,
): string {
  const name = format.fileName(version);

  return serialization === "yaml" ? name.replace(/\.json$/i, ".yaml") : name;
}

function hasVersion(format: AnyDocumentFormat, version: string): boolean {
  return Object.hasOwn(format.versions, version);
}

function resolveOne(
  output: SpecOutputConfig,
  registry: ReadonlyMap<string, AnyDocumentFormat>,
  filter: TargetFilter,
): SpecTarget {
  const format = registry.get(output.format);

  if (!format) {
    throw new TargetError(
      "format-unknown",
      `Unknown document format "${output.format}". Known formats: ${[...registry.keys()].join(", ")}.`,
    );
  }

  const fallback: unknown = format.defaultVersion;

  const version =
    filter.version ??
    output.version ??
    (typeof fallback === "string" ? fallback : "");

  if (!hasVersion(format, version)) {
    throw new TargetError(
      "version-unknown",
      `${format.id} has no version "${version}". Versions: ${Object.keys(format.versions).join(", ")}.`,
    );
  }

  const path = filter.out ?? output.output;

  const serialization: SpecSerialization =
    filter.yaml === true
      ? "yaml"
      : (output.serialize ?? (path ? serializationOf(path) : "json"));

  const ui = filter.ui ?? output.ui;

  return {
    format,
    version,
    output: path ?? defaultOutput(format, version, serialization),
    serialization,
    overlays: output.overlays ?? [],
    ...(ui === undefined ? {} : { ui }),
  };
}

/**
 * The configured outputs, narrowed by the command line. A format argument keeps
 * that format's outputs, or renders it on its own when none is configured;
 * `--spec-version` keeps the outputs at that version, or renders it on its own;
 * `--out` needs exactly one target.
 */
export function resolveTargets(
  outputs: readonly SpecOutputConfig[],
  registry: ReadonlyMap<string, AnyDocumentFormat>,
  filter: TargetFilter,
): SpecTarget[] {
  let selected = filter.format
    ? outputs.filter((output) => output.format === filter.format)
    : [...outputs];

  if (filter.format && selected.length === 0) {
    selected = [{ format: filter.format }];
  }

  if (filter.version) {
    const atVersion = selected.filter(
      (output) =>
        (output.version ?? registry.get(output.format)?.defaultVersion) ===
        filter.version,
    );

    if (atVersion.length > 0) {
      selected = atVersion;
    } else {
      const formats = [...new Set(selected.map((output) => output.format))];

      if (formats.length !== 1) {
        throw new TargetError(
          "usage",
          "Name a format with --spec-version when more than one format is configured.",
        );
      }

      const id = formats[0] ?? "";
      const format = registry.get(id);
      // A version nobody configured gets its own file, so it never
      // overwrites the configured output for the default version.
      selected = [
        format && !filter.out && hasVersion(format, filter.version)
          ? {
              format: id,
              output: defaultOutput(
                format,
                filter.version,
                filter.yaml === true ? "yaml" : "json",
              ).replace(/(\.[a-z]+)$/i, `-${filter.version}$1`),
            }
          : { format: id },
      ];
    }
  }

  if (filter.out && selected.length !== 1) {
    throw new TargetError(
      "usage",
      `--out needs exactly one output, and ${selected.length} match. Name a format or a version.`,
    );
  }

  const targets = selected.map((output) =>
    resolveOne(output, registry, filter),
  );

  const seen = new Set<string>();

  for (const target of targets) {
    if (seen.has(target.output)) {
      throw new TargetError(
        "usage",
        `Two outputs write ${target.output}. Give each one an \`output\` in api.specs.outputs.`,
      );
    }

    seen.add(target.output);
  }

  return targets;
}
