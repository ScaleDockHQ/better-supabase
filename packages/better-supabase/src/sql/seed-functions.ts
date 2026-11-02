import type { ResolvedConfig } from "../config/index.ts";

import { moduleLayout } from "./layout.ts";
import { moduleContext } from "./module-context.ts";
import { SQL_MODULES } from "./registry.ts";
import { seedFunctionName } from "./seeds.ts";

/** An installed module that declares tenant defaults, and its seed function. */
export interface SeedDefaultsFunction {
  readonly module: string;
  /** The schema-qualified function, as SQL. */
  readonly fn: string;
  readonly variants: readonly string[];
}

/**
 * The `seed_<module>_defaults` functions of the installed modules, in install
 * order.
 */
export function seedDefaultsFunctions(
  config: ResolvedConfig,
): readonly SeedDefaultsFunction[] {
  const layout = moduleLayout(config);

  return config.blockNames.flatMap((name) => {
    const module = SQL_MODULES[name];

    if (module?.seeds?.defaults === undefined) {
      return [];
    }

    return [
      {
        module: name,
        fn: moduleContext(name, layout, config.blockNames).fn(
          seedFunctionName(name),
        ),
        variants: module.seeds.variants ?? [],
      },
    ];
  });
}
