import { existsSync } from "node:fs";
import { readFile } from "node:fs/promises";
import { basename, dirname, join, resolve } from "node:path";

import type { ResolvedConfig } from "../../config/index.ts";
import type { SpecDiagnostic, SpecUi } from "../../spec/index.ts";
import type { AnyCommand, CliArgs, CliContext } from "../core/command.ts";
import type { CommandResult } from "../core/io.ts";
import type {
  FailOn,
  ManifestOutput,
  OutputStatus,
} from "../spec/diagnostics.ts";
import type { RenderedTarget } from "../spec/render.ts";
import type { SpecTarget, TargetFilter } from "../spec/targets.ts";

import { SPEC_UIS, specReferenceHtml } from "../../spec/index.ts";
import { defineCliCommand } from "../core/command.ts";
import { errorText, failedResult, CliError } from "../core/errors.ts";
import { display, sameText, writeIfChanged } from "../core/io.ts";
import { commandMeta } from "../core/manifest.ts";
import { fileDiff } from "../diff.ts";
import { writeAtomic } from "../introspect/cache.ts";
import { SPEC_CACHE_DIR, sha256 } from "../spec/cache.ts";
import {
  FAIL_ON,
  buildManifest,
  fails,
  formatDiagnostics,
  isFailOn,
} from "../spec/diagnostics.ts";
import { loadSpecEntry } from "../spec/entry.ts";
import { formatRegistry } from "../spec/formats.ts";
import { renderTarget } from "../spec/render.ts";
import { TargetError, resolveTargets } from "../spec/targets.ts";
import { fieldOf, parseAs } from "../spec/text.ts";
import { undocumentedTopics } from "../spec/topics.ts";
import { loadTopics } from "../topics.ts";
import { parseInterval, stampFiles, watchLoop } from "../watch.ts";

const ACTIONS = ["emit", "check", "validate"] as const;

type SpecAction = (typeof ACTIONS)[number];

const isAction = (value: unknown): value is SpecAction =>
  ACTIONS.some((action) => action === value);

const isUi = (value: unknown): value is SpecUi =>
  SPEC_UIS.some((ui) => ui === value);

const ARGS = {
  action: {
    type: "positional",
    required: false,
    description: "emit, check or validate",
  },
  format: {
    type: "positional",
    required: false,
    description:
      "Only this format (openapi, asyncapi, arazzo, or one the entry adds)",
  },
  "spec-version": {
    type: "string",
    description:
      "Render this version of the format instead of the configured one",
    valueHint: "version",
  },
  out: {
    type: "string",
    description: "Write the one selected output to this file",
    valueHint: "file",
  },
  entry: {
    type: "string",
    description:
      "Defaults to specs.entry. Exports `api` (defineApi) or a document",
    valueHint: "file",
  },
  yaml: {
    type: "boolean",
    description: "Write YAML instead of JSON",
  },
  ui: {
    type: "string",
    description:
      "Also write a reference page next to OpenAPI outputs: scalar, swagger, redoc, elements or rapidoc",
    valueHint: "name",
  },
  "fail-on": {
    type: "string",
    description:
      "Exit 1 on findings at this level: error (default), warning or never",
    valueHint: "level",
  },
  manifest: {
    type: "string",
    description:
      "Also write the diagnostics manifest (JSON) to this file. Defaults to specs.manifest",
    valueHint: "file",
  },
  cache: {
    type: "boolean",
    default: true,
    description: "Reuse renders whose inputs did not change",
    negativeDescription: "Render every output again",
  },
  watch: {
    type: "boolean",
    description:
      "With emit, render again whenever the entry, the config, an overlay or a topic module changes",
  },
  interval: {
    type: "string",
    description:
      "Milliseconds between checks in --watch. Defaults to gen.watchInterval, then 2000",
    valueHint: "ms",
  },
} as const;

export type SpecArgs = CliArgs<typeof ARGS>;

export interface SpecRunOptions {
  readonly config: ResolvedConfig;
  readonly action: SpecAction;
  readonly filter: TargetFilter;
  readonly entry?: string;
  readonly failOn: FailOn;
  readonly cache: boolean;
  readonly manifest?: string;
}

/** The options for running the spec step from the config alone, as `gen` does (no filter, the config's `failOn`, cache on). */
export function specOptionsFromConfig(
  config: ResolvedConfig,
  action: SpecAction,
  overrides: Partial<
    Pick<SpecRunOptions, "filter" | "entry" | "failOn" | "cache" | "manifest">
  > = {},
): SpecRunOptions {
  const manifest = overrides.manifest ?? config.specs.manifest;

  return {
    config,
    action,
    filter: overrides.filter ?? {},
    failOn: overrides.failOn ?? config.specs.failOn,
    cache: overrides.cache ?? true,
    ...(overrides.entry === undefined ? {} : { entry: overrides.entry }),
    ...(manifest === undefined ? {} : { manifest }),
  };
}

/** The reference page for an OpenAPI output: `openapi.html` next to `openapi.json`. */
export function uiPath(output: string): string {
  return join(
    dirname(output),
    `${basename(output).replace(/\.[^.]+$/, "")}.html`,
  );
}

function uiHtml(rendered: RenderedTarget, ui: SpecUi): string {
  const document = parseAs(rendered.target.serialization, rendered.text);
  const title = fieldOf(fieldOf(document, "info"), "title");

  return `${specReferenceHtml({
    specUrl: `./${basename(rendered.target.output)}`,
    ui,
    ...(typeof title === "string" ? { title } : {}),
  })}\n`;
}

interface Settled {
  readonly status: OutputStatus;
  readonly lines: readonly string[];
  readonly diagnostics: readonly SpecDiagnostic[];
  readonly stale: boolean;
}

async function onDisk(path: string): Promise<string | undefined> {
  return existsSync(path) ? readFile(path, "utf-8") : undefined;
}

async function settle(
  action: SpecAction,
  root: string,
  rendered: RenderedTarget,
): Promise<Settled> {
  const { target } = rendered;
  const shown = display(root, target.output);

  const files: { path: string; text: string }[] = [
    { path: target.output, text: rendered.text },
  ];

  const diagnostics: SpecDiagnostic[] = [...rendered.diagnostics];

  if (target.ui) {
    if (target.format.id === "openapi") {
      files.push({
        path: uiPath(target.output),
        text: uiHtml(rendered, target.ui),
      });
    } else {
      diagnostics.push({
        code: "ui-unsupported",
        severity: "info",
        message: `--ui renders OpenAPI documents only; ${target.format.id} has no reference page.`,
      });
    }
  }

  const label = `(${target.format.id} ${target.version}${rendered.cached ? ", cached" : ""})`;

  switch (action) {
    case "emit": {
      const lines: string[] = [];
      let wrote = false;

      for (const file of files) {
        const changed = await writeIfChanged(
          resolve(root, file.path),
          file.text,
        );

        wrote ||= changed;
        lines.push(
          `${changed ? "Wrote" : "Unchanged"} ${display(root, file.path)}${file.path === target.output ? ` ${label}` : ""}`,
        );
      }

      return {
        status: wrote ? "written" : "unchanged",
        lines,
        diagnostics,
        stale: false,
      };
    }

    case "check": {
      const lines: string[] = [];
      let stale = false;

      for (const file of files) {
        const path = resolve(root, file.path);
        const name = display(root, file.path);
        const current = await onDisk(path);

        if (sameText(current, file.text)) {
          lines.push(`${name} is up to date.`);
          continue;
        }

        stale = true;
        lines.push(fileDiff(name, current, file.text));
        const missing = current === undefined;
        diagnostics.push({
          code: missing ? "output-missing" : "output-stale",
          severity: "error",
          message: `${name} ${missing ? "does not exist" : "is out of date"}. Run \`better-supabase spec emit\`.`,
        });
      }

      return {
        status: stale ? "stale" : "up-to-date",
        lines,
        diagnostics,
        stale,
      };
    }

    case "validate": {
      return {
        status: "validated",
        lines: [`Checked ${shown} ${label}`],
        diagnostics,
        stale: false,
      };
    }

    default: {
      const unknown: never = action;
      throw new Error(`Unknown spec action: ${String(unknown)}`);
    }
  }
}

/** Renders every selected output, then writes, compares or validates it. */
export async function runSpec(options: SpecRunOptions): Promise<CommandResult> {
  const { config } = options;
  const root = config.root;
  const entryPath = options.entry ?? config.specs.entry;
  let entry;

  try {
    entry = await loadSpecEntry(resolve(root, entryPath));
  } catch (cause) {
    return {
      code: 1,
      error: `Could not load ${display(root, entryPath)}: ${errorText(cause)}`,
    };
  }

  const registry = formatRegistry(entry.formats);
  let targets: SpecTarget[];

  try {
    targets = resolveTargets(config.specs.outputs, registry, options.filter);
  } catch (cause) {
    if (cause instanceof TargetError) {
      return { code: cause.code === "usage" ? 2 : 1, error: cause.message };
    }

    throw cause;
  }

  const missing = targets.find(
    (target) => !entry.api && !entry.documents.has(target.format.id),
  );

  if (missing) {
    return {
      code: 1,
      error: `${display(root, entryPath)} must export \`api\` (defineApi(...)) or a ${missing.format.id} document as \`${missing.format.id}\` or default.`,
    };
  }

  const context = {
    root,
    entry,
    cache: options.cache,
    validate: options.action === "validate",
  };

  const policies = config.realtime.policies;
  let topicFindings: readonly SpecDiagnostic[] = [];

  if (
    policies !== undefined &&
    entry.api !== undefined &&
    targets.some((target) => target.format.id === "asyncapi")
  ) {
    try {
      topicFindings = undocumentedTopics(
        entry.api.model,
        await loadTopics(root, policies.from),
      );
    } catch (cause) {
      return {
        code: 1,
        error: `Could not load the topics of realtime.policies.from: ${errorText(cause)}`,
      };
    }
  }

  const rendered = (
    await Promise.all(targets.map((target) => renderTarget(target, context)))
  ).map((result) =>
    result.target.format.id === "asyncapi" && topicFindings.length > 0
      ? { ...result, diagnostics: [...result.diagnostics, ...topicFindings] }
      : result,
  );

  const outputs: ManifestOutput[] = [];
  const lines: string[] = [];
  let stale = false;

  for (const result of rendered) {
    const settled = await settle(options.action, root, result);
    stale ||= settled.stale;
    lines.push(...settled.lines);
    outputs.push({
      format: result.target.format.id,
      version: result.target.version,
      pin: result.pin,
      path: display(root, result.target.output),
      sha256: sha256(result.text),
      status: settled.status,
      cached: result.cached,
      diagnostics: settled.diagnostics,
    });
  }

  const failing = outputs.flatMap((output) =>
    output.diagnostics.filter(
      (diagnostic) =>
        fails(diagnostic, options.failOn) ||
        diagnostic.code === "output-stale" ||
        diagnostic.code === "output-missing",
    ),
  );

  const ok = failing.length === 0 && !stale;
  const manifest = buildManifest(outputs, options.failOn, ok);
  const manifestText = `${JSON.stringify(manifest, null, 2)}\n`;
  await writeAtomic(
    resolve(root, SPEC_CACHE_DIR, "diagnostics.json"),
    manifestText,
  ).catch(() => undefined);

  if (options.manifest) {
    await writeIfChanged(resolve(root, options.manifest), manifestText);
  }

  const findings = formatDiagnostics(outputs);
  const output = [...lines, ...(findings ? ["", findings] : [])].join("\n");

  if (ok) {
    return { code: 0, output, data: manifest };
  }

  const count = failing.length;

  return {
    code: 1,
    output,
    data: manifest,
    errorCode: stale ? "check_failed" : "findings",
    error: stale
      ? "The spec files are out of date. Run `better-supabase spec emit`."
      : `${count} ${count === 1 ? "finding fails" : "findings fail"} --fail-on ${options.failOn}.`,
  };
}

/** The files a render reads: the config, the entry, its overlays, the generated module and the topic modules. */
function watchedFiles(
  options: SpecRunOptions,
  configFile: string | undefined,
): string[] {
  const { config } = options;

  return [
    ...(configFile ? [configFile] : []),
    resolve(config.root, options.entry ?? config.specs.entry),
    resolve(config.root, config.output),
    ...config.specs.outputs.flatMap((output) =>
      (output.overlays ?? []).map((path) => resolve(config.root, path)),
    ),
    ...(config.realtime.policies?.from ?? []).map((path) =>
      resolve(config.root, path),
    ),
  ];
}

/**
 * Emits whenever a watched file changes. A changed config file is loaded
 * again first. A failed run is retried on the next change.
 */
function watch(
  initial: SpecRunOptions,
  interval: number,
  context: CliContext,
): Promise<CommandResult> {
  let options = initial;
  let last = "";

  return watchLoop({
    interval,
    context,
    reload: (config) => {
      options = { ...options, config };
    },
    tick: async () => {
      const current = await stampFiles(
        watchedFiles(options, context.configFile),
      );

      if (current === last) {
        return;
      }

      last = current;

      return runSpec(options).catch(failedResult);
    },
  });
}

export const specCommand: AnyCommand = defineCliCommand({
  meta: commandMeta("spec"),
  args: ARGS,
  run: (args, context) => {
    const [action, format] = args._;

    if (!isAction(action)) {
      throw new CliError(
        "usage",
        `${action ? `Unknown spec action "${action}"` : "Name an action"}. Run \`better-supabase spec emit\`, \`check\` or \`validate\`.`,
      );
    }

    const failOn = args["fail-on"] ?? context.config.specs.failOn;

    if (!isFailOn(failOn)) {
      throw new CliError(
        "usage",
        `--fail-on takes ${FAIL_ON.join(", ")}, got "${failOn}".`,
      );
    }

    if (args.ui !== undefined && !isUi(args.ui)) {
      throw new CliError(
        "usage",
        `--ui takes ${SPEC_UIS.join(", ")}, got "${args.ui}".`,
      );
    }

    const interval = parseInterval(
      args.interval,
      context.config.gen.watchInterval,
    );

    if (
      args.watch === true &&
      (action !== "emit" || typeof interval === "string")
    ) {
      throw new CliError(
        "usage",
        action === "emit" && typeof interval === "string"
          ? interval
          : "--watch only applies to `spec emit`.",
      );
    }

    const options = specOptionsFromConfig(context.config, action, {
      failOn,
      cache: args.cache,
      ...(args.manifest === undefined ? {} : { manifest: args.manifest }),
      ...(args.entry === undefined ? {} : { entry: args.entry }),
      filter: {
        ...(typeof format === "string" ? { format } : {}),
        ...(args["spec-version"] === undefined
          ? {}
          : { version: args["spec-version"] }),
        ...(args.out === undefined ? {} : { out: args.out }),
        ...(args.yaml === true ? { yaml: true } : {}),
        ...(isUi(args.ui) ? { ui: args.ui } : {}),
      },
    });

    return args.watch === true && typeof interval === "number"
      ? watch(options, interval, context)
      : runSpec(options);
  },
});
