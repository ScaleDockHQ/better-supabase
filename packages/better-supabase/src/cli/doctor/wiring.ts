import type { WiringProvider } from "../wiring.ts";
import type { Rule, TextFile } from "./rules.ts";

import { configInstances, wiringFor } from "../wiring.ts";

const ENV_KEY = /^\s*(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*=/;

function listedKeys(files: readonly TextFile[]): Set<string> {
  return new Set(
    files.flatMap((file) =>
      file.text.split("\n").flatMap((line) => {
        const match = ENV_KEY.exec(line);

        return match ? [match[1]!] : [];
      }),
    ),
  );
}

const camel = (name: string): string =>
  name.replaceAll(/-([a-z0-9])/g, (_, letter: string) => letter.toUpperCase());

const escape = (text: string): string =>
  text.replaceAll(/[.*+?^${}()|[\]\\]/g, "\\$&");

/**
 * Whether a source line outside a comment passes the instance a provider:
 * `enrichment: blocks.enrichment.with({ provider })` or `.using(...)`.
 */
function wired(sources: readonly TextFile[], entry: WiringProvider): boolean {
  const keys = [...new Set([entry.instance, camel(entry.instance)])].map(
    escape,
  );

  const pattern = new RegExp(
    `(?:^|[\\s{,])["']?(?:${keys.join("|")})["']?\\s*:\\s*[\\w$.\\[\\]"'-]*\\.(?:with|using)\\(`,
  );

  return sources.some((file) =>
    file.text.split("\n").some((line) => {
      const code = line.trim();

      return (
        !code.startsWith("//") && !code.startsWith("*") && pattern.test(code)
      );
    }),
  );
}

/** The env keys and providers the installed blocks need (BS504, BS505). */
export const WIRING_RULES: readonly Rule[] = [
  {
    code: "BS504",
    severity: "error",
    title: "Env key a block needs is missing",
    description:
      "An installed block reads a key that no env file lists and the shell doesn't set, so its route or worker fails at runtime. `better-supabase add` appends the keys to .env.example; set them in .env.local and every deployed environment.",
    check: (context) => {
      const plan = wiringFor(configInstances(context.config));
      const listed = listedKeys(context.envFiles);
      const shell = context.shellEnv ?? {};

      return plan.env
        .filter(
          (entry) =>
            entry.required !== false &&
            !listed.has(entry.key) &&
            (shell[entry.key] ?? "") === "",
        )
        .map((entry) => ({
          message: `${entry.blocks.join(", ")} ${entry.blocks.length === 1 ? "reads" : "read"} ${entry.key} (${entry.description}) but no env file lists it. Add it to .env.example and set it in .env.local and every deployed environment.`,
          target: entry.key,
        }));
    },
  },
  {
    code: "BS505",
    severity: "error",
    title: "Required provider is not wired",
    description:
      "A block that can't run without an implementation (an enrichment provider, the mail providers) is installed, but no app source passes it one with `.with(...)` or `.using(...)`. Fill in its stub in providers.ts and spread `...providers` into `defineBlocks`.",
    check: (context) => {
      const plan = wiringFor(configInstances(context.config));

      return plan.providers
        .filter(
          (entry) => entry.provider.required && !wired(context.sources, entry),
        )
        .map((entry) => ({
          message: `${entry.instance} needs \`${entry.provider.option}\` (an implementation of ${entry.provider.type} from ${entry.provider.from}). Fill in its stub in providers.ts, next to blocks.generated.ts (for example \`${entry.provider.option}: ${entry.provider.example}\`), and spread \`...providers\` into \`defineBlocks\`.`,
          target: `${entry.instance}.${entry.provider.option}`,
        }));
    },
  },
];
