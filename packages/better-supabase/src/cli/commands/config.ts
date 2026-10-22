import type { ResolvedConfig } from "../../config/index.ts";
import type { AnyCommand } from "../core/command.ts";

import { defineCliCommand } from "../core/command.ts";
import { display } from "../core/io.ts";
import { commandMeta } from "../core/manifest.ts";
import { redact, redactUrl } from "../core/redact.ts";
import { presetInfo } from "./preset.ts";

/**
 * The resolved config as JSON: generators by name and version, every credential
 * redacted.
 */
export function printableConfig(config: ResolvedConfig): unknown {
  return redact({
    ...config,
    source: {
      ...config.source,
      ...(config.source.dbUrl ? { dbUrl: redactUrl(config.source.dbUrl) } : {}),
    },
    generators: config.generators.map((generator) => ({
      name: generator.name,
      apiVersion: generator.apiVersion ?? null,
    })),
  });
}

export const configCommand: AnyCommand = defineCliCommand({
  meta: commandMeta("config"),
  args: {
    preset: {
      type: "boolean",
      description:
        "The preset the config names, what it resolves to, and how the config differs from it",
    },
  },
  run: (args, context) => {
    if (args.preset === true) {
      return Promise.resolve(presetInfo(context.config));
    }

    const config = printableConfig(context.config);

    const file = context.configFile
      ? display(context.cwd, context.configFile)
      : null;

    const environment = context.config.environment ?? null;
    const header = file ? `# ${file}` : "# no config file, defaults only";

    return Promise.resolve({
      code: 0,
      output: `${header}${environment ? ` (environment: ${environment})` : ""}\n${JSON.stringify(config, null, 2)}`,
      data: { file, environment, config },
    });
  },
});
