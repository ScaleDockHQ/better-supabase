import type { WiringProvider } from "../wiring.ts";
import type { Rule, TextFile } from "./rules.ts";

import { configInstances, wiringFor } from "../wiring.ts";

/** The view the housekeeping module creates. */
const MAINTENANCE_JOBS = /\bmaintenance_jobs\b/u;

/** A call that registers pg_cron, not the function definition. */
const MAINTENANCE_SCHEDULED =
  /\bmaintenance_schedule\s*\(\s*(?:\)|')|cron\.schedule\s*\(\s*'[^'%][^;]*\bmaintenance\s*\(/u;

/** The tick handler, or an app call of the dispatcher. */
const MAINTENANCE_SOURCE =
  /\bmaintenanceTick\b|["']maintenance(?:_schedule)?["']/u;

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

const USE_CLIENT =
  /^(?:\s*(?:\/\/[^\n]*|\/\*[\s\S]*?\*\/))*\s*["']use client["']/u;

/**
 * A static import of the server wiring: the generated block modules or
 * `providers.ts`.
 */
const SERVER_WIRING_IMPORT =
  /\bfrom\s+["'][^"']*\/(?:blocks\.generated|providers)(?:\.ts)?["']/gu;

const DEFINE_BLOCKS_CALL = /(?:^|[^.\w])defineBlocks\s*\(/mu;

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
  {
    code: "BS507",
    severity: "warning",
    title: "Block actions are not registered",
    description:
      "An installed block ships automation actions (the conversions, for example), but no app source builds a registry from them with `blockActions(...)` or `createActionRegistry(...)`. A default automation that is turned on then names an action the rules consumer can't run, and its event fails. Pass `...blockActions(blocks, { clients })` to `createActionRegistry` in the outbox route.",
    check: (context) => {
      const plan = wiringFor(configInstances(context.config));

      if (plan.actions.length === 0) {
        return [];
      }

      const registered = context.sources.some((file) =>
        file.text.split("\n").some((line) => {
          const code = line.trim();

          return (
            !code.startsWith("//") &&
            !code.startsWith("*") &&
            (code.includes("blockActions(") ||
              code.includes("createActionRegistry("))
          );
        }),
      );

      return registered
        ? []
        : [
            {
              message: `${plan.actions.map((entry) => entry.kind).join(", ")} ${plan.actions.length === 1 ? "is" : "are"} shipped by installed blocks, but no source builds an action registry. Call \`createActionRegistry([...blockActions(blocks, { clients })])\` from \`better-supabase/blocks/automations\` where the outbox consumer runs.`,
              target: "actions",
            },
          ];
    },
  },
  {
    code: "BS508",
    severity: "warning",
    title: "Block timers have no handler",
    description:
      "An installed block declares timers (a schedule that runs `check()` or a sweep), but no app source calls `blockTickHandler(...)` or `blockSchedules(...)`. The timers never fire, so SLA checks and sweeps stay idle. Call `jobs.ensureSchedules(blockSchedules(blocks), { prefix: BLOCK_SCHEDULE_PREFIX })` once and drain the `block_ticks` queue with `blockTickHandler`.",
    check: (context) => {
      const plan = wiringFor(configInstances(context.config));

      if (plan.schedules.length === 0) {
        return [];
      }

      const handled = context.sources.some((file) =>
        file.text.split("\n").some((line) => {
          const code = line.trim();

          return (
            !code.startsWith("//") &&
            !code.startsWith("*") &&
            code.includes("blockTickHandler")
          );
        }),
      );

      return handled
        ? []
        : plan.schedules.map((entry) => ({
            message: `${entry.block} schedules ${entry.runs} at \`${entry.cron}\`, but no source calls \`blockTickHandler\`. Drain the \`block_ticks\` queue with it.`,
            target: `${entry.block}.${entry.runs}`,
          }));
    },
  },
  {
    code: "BS510",
    severity: "warning",
    title: "Maintenance jobs have no scheduler",
    description:
      "The schema files install the housekeeping module (maintenance_jobs), but nothing schedules maintenance(): no `maintenance_schedule()` call for pg_cron, no cron.schedule line for it and no `maintenanceTick` handler on the block_ticks queue. The purges and expiries it dispatches never run. Run `select better_supabase.maintenance_schedule()`, or register `maintenanceTick` with `blockTickHandler` when pg_cron is not available.",
    check: (context) => {
      const sql = context.sqlFiles;

      if (
        sql === undefined ||
        !sql.some((file) => MAINTENANCE_JOBS.test(file.text))
      ) {
        return [];
      }

      const scheduled =
        sql.some((file) => MAINTENANCE_SCHEDULED.test(file.text)) ||
        context.sources.some((file) => MAINTENANCE_SOURCE.test(file.text));

      return scheduled
        ? []
        : [
            {
              message:
                "The housekeeping module is installed, but nothing runs maintenance(). Call `select better_supabase.maintenance_schedule()` once (it registers pg_cron, or returns 'none'), or drain the block_ticks queue with `maintenanceTick`.",
              target: "housekeeping",
            },
          ];
    },
  },
  {
    code: "BS511",
    severity: "warning",
    title: "Client component reaches the server block wiring",
    description:
      "A `use client` module imports `blocks.generated` or `providers.ts`, or calls `defineBlocks`, so every installed block client lands in the browser bundle. Import `blockConfig` from `blocks.config.ts` instead, and list the blocks the browser needs in `gen.clientBlocks` (they come from `blocks.client.ts`).",
    check: (context) =>
      context.sources.flatMap((file) => {
        if (!USE_CLIENT.test(file.text)) {
          return [];
        }

        const imports = [...file.text.matchAll(SERVER_WIRING_IMPORT)];

        if (imports.length === 0 && !DEFINE_BLOCKS_CALL.test(file.text)) {
          return [];
        }

        return [
          {
            message: `${file.path} is a client component that ${imports.length > 0 ? "imports blocks.generated or providers.ts" : "calls defineBlocks"}, which bundles every installed block client for the browser. Import \`blockConfig\` from blocks.config.ts and the browser blocks from blocks.client.ts (\`gen.clientBlocks\`).`,
            target: file.path,
          },
        ];
      }),
  },
];
