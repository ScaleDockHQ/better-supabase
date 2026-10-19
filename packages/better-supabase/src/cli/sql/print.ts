import type { ResolvedConfig } from "../../config/index.ts";
import type { CommandResult } from "../core/io.ts";
import type { SqlFlags } from "./args.ts";

import {
  contractSignature,
  customContracts,
  moduleBody,
  SQL_MODULES,
} from "../../sql/index.ts";
import { CliError } from "../core/errors.ts";
import { layout } from "./providers.ts";

export async function printModule(
  config: ResolvedConfig,
  args: SqlFlags,
  names: readonly string[],
): Promise<CommandResult> {
  const [name] = names;

  if (name === undefined) {
    throw new CliError("input_required", "Name one module.", {
      missing: ["<module>"],
      choices: { "<module>": Object.keys(SQL_MODULES) },
    });
  }

  const module = SQL_MODULES[name];

  if (!module) {
    throw new CliError(
      "usage",
      `Name one module: ${Object.keys(SQL_MODULES).join(", ")}`,
    );
  }

  const body = moduleBody(
    module.name,
    await layout(config, args, [module.name]),
  );

  if (body === undefined) {
    return {
      code: 0,
      data: { module: module.name, custom: true },
      output: `-- blocks.${module.name} is in custom mode: the app writes these functions.\n${customContracts(
        [module.name],
        await layout(config, args, [module.name]),
      )
        .flatMap((contract) =>
          contract.functions.map(
            (fn) =>
              `-- ${contract.schema}.${fn.name}(${contractSignature(fn, contract.idType)}) returns ${fn.returns.replaceAll("{id}", contract.idType)}`,
          ),
        )
        .join("\n")}`,
    };
  }

  return {
    code: 0,
    output: body,
    data: { module: module.name, custom: false, sql: body },
  };
}
