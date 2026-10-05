import type { ResolvedConfig } from "../../config/index.ts";
import type { AnyCommand } from "../command.ts";

import { defineCliCommand } from "../command.ts";
import { display } from "../io.ts";

/** A connection string with its password replaced, so the printed config is safe to share. */
function redactUrl(url: string): string {
  try {
    const parsed = new URL(url);
    if (parsed.password === "") return url;
    parsed.password = "redacted";
    return parsed.toString();
  } catch {
    return "<redacted>";
  }
}

/** The resolved config as JSON: generators by name and version, the database password redacted. */
export function printableConfig(config: ResolvedConfig): unknown {
  return {
    ...config,
    source: {
      ...config.source,
      ...(config.source.dbUrl ? { dbUrl: redactUrl(config.source.dbUrl) } : {}),
    },
    generators: config.generators.map((generator) => ({
      name: generator.name,
      apiVersion: generator.apiVersion ?? null,
    })),
  };
}

export const configCommand: AnyCommand = defineCliCommand({
  meta: {
    name: "config",
    description:
      "Prints the resolved config: the file it came from and every option with its default",
  },
  args: {},
  run: (_args, context) => {
    const config = printableConfig(context.config);
    const file = context.configFile
      ? display(context.cwd, context.configFile)
      : null;
    return Promise.resolve({
      code: 0,
      output: `${file ? `# ${file}` : "# no config file, defaults only"}\n${JSON.stringify(config, null, 2)}`,
      data: { file, config },
    });
  },
});
