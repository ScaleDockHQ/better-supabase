import type { WiringProvider } from "../wiring.ts";
import type { DoctorContext, FindingInput, Rule, TextFile } from "./rules.ts";

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

const PG_NET = /\bcreate\s+extension\s+(?:if\s+not\s+exists\s+)?"?pg_net\b/iu;

/** Vault writes of the tick URL and token, not the lookups in `http_tick()`. */
const TICK_SECRETS = [
  /\bcreate_secret\s*\([^;]*'jobs_tick_url'/iu,
  /\bcreate_secret\s*\([^;]*'jobs_tick_token'/iu,
];

const SCHEDULE_TRIGGER = "schedule/v1beta";

const isRecord = (value: unknown): value is Readonly<Record<string, unknown>> =>
  typeof value === "object" && value !== null && !Array.isArray(value);

const stringAt = (value: unknown, key: string): string | undefined => {
  const field = isRecord(value) ? value[key] : undefined;

  return typeof field === "string" ? field : undefined;
};

function parsedJson(file: TextFile): unknown {
  try {
    return JSON.parse(file.text);
  } catch {
    return undefined;
  }
}

/** Whether `functions[source]` has a `schedule/v1beta` trigger. */
function hasScheduleTrigger(functions: unknown, source: string): boolean {
  const entry = isRecord(functions) ? functions[source] : undefined;
  const triggers = isRecord(entry) ? entry["experimentalTriggers"] : undefined;

  return (
    Array.isArray(triggers) &&
    triggers.some((trigger) => stringAt(trigger, "type") === SCHEDULE_TRIGGER)
  );
}

/** The `crons` and `schedules` of `vercel.json` that would misfire (BS512). */
function vercelScheduleFindings(file: TextFile): FindingInput[] {
  const json = parsedJson(file);

  if (!isRecord(json)) {
    return [];
  }

  const crons = Array.isArray(json["crons"]) ? json["crons"] : [];

  const schedules = isRecord(json["schedules"])
    ? Object.entries(json["schedules"])
    : [];

  const scheduledPaths = new Set(
    schedules.flatMap(([, entry]) => stringAt(entry, "path") ?? []),
  );

  const fromCrons = crons.flatMap((entry): FindingInput[] => {
    const path = stringAt(entry, "path");

    if (path === undefined) {
      return [];
    }

    return [
      scheduledPaths.has(path)
        ? {
            message: `vercel.json calls ${path} from both \`crons\` and \`schedules\`, so it runs twice on each tick. Remove its \`crons\` entry.`,
            target: `crons:${path}`,
          }
        : {
            message: `vercel.json calls ${path} from \`crons\`. Move it to \`schedules\` as a path target (\`{ "schedule": "...", "path": "${path}", "requestMethod": "GET" }\`), which sends the same CRON_SECRET bearer.`,
            target: `crons:${path}`,
          },
    ];
  });

  const fromSchedules = schedules.flatMap(([name, entry]): FindingInput[] => {
    const source = stringAt(entry, "function");

    return source === undefined || hasScheduleTrigger(json["functions"], source)
      ? []
      : [
          {
            message: `The schedule ${name} targets the function ${source}, but functions["${source}"] has no \`${SCHEDULE_TRIGGER}\` trigger, so Vercel never calls it. Add \`experimentalTriggers: [{ "type": "${SCHEDULE_TRIGGER}" }]\` to it.`,
            target: `schedules:${name}`,
          },
        ];
  });

  return [...fromCrons, ...fromSchedules];
}

/** `blocks.queue.options.httpTick` without pg_net or the Vault secrets (BS512). */
function httpTickFindings(context: DoctorContext): FindingInput[] {
  const queue = context.config.blocks["queue"];

  if (queue?.options?.["httpTick"] !== true) {
    return [];
  }

  const sql = context.sqlFiles ?? [];
  const findings: FindingInput[] = [];

  if (!sql.some((file) => PG_NET.test(file.text))) {
    findings.push({
      message:
        "blocks.queue.options.httpTick is on, but no schema file creates pg_net, so better_supabase.http_tick() raises on every tick. Add `create extension if not exists pg_net with schema extensions;` to a schema file.",
      target: "blocks.queue.options.httpTick:pg_net",
    });
  }

  const files = [
    ...sql,
    ...(context.seedFiles ?? []),
    ...(context.dataFiles ?? []),
  ];

  const written = TICK_SECRETS.every((secret) =>
    files.some((file) => secret.test(file.text)),
  );

  if (!written) {
    findings.push({
      message:
        "blocks.queue.options.httpTick is on, but no SQL file stores the jobs_tick_url and jobs_tick_token Vault secrets, so http_tick() skips every tick with a warning. Run `select vault.create_secret('<drain URL>', 'jobs_tick_url')` and `select vault.create_secret('<CRON_SECRET>', 'jobs_tick_token')` in each database, or ignore this when you set them from the dashboard.",
      target: "blocks.queue.options.httpTick:vault",
    });
  }

  return findings;
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
  {
    code: "BS512",
    severity: "warning",
    title: "Queue schedule wiring misfires",
    description:
      "The clock that drives the queue is wired so it misses or doubles runs: `vercel.json` still calls a path from `crons` (Vercel Schedules replaces them, and a path in both runs twice), a schedule targets a private function without a `schedule/v1beta` trigger, or `blocks.queue.options.httpTick` is on without pg_net or the `jobs_tick_url` and `jobs_tick_token` Vault secrets.",
    check: (context) => [
      ...(context.vercelConfig === undefined
        ? []
        : vercelScheduleFindings(context.vercelConfig)),
      ...httpTickFindings(context),
    ],
  },
];
