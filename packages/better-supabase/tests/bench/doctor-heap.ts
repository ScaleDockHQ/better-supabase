// The heap doctor keeps after reading a long migration history: 1,200
// migrations of about 16 kB each (19 MB, a large app's history). Fails when
// the live heap the SQL reader holds grows past CEILING_MB, as it did in 0.85.0
// when every migration body stayed in memory as code tokens.
//   node --expose-gc tests/bench/doctor-heap.ts
import type { DoctorContext } from "../../src/cli/doctor/rules.ts";

import { parseSnapshot } from "../../src/cli/commands/snapshot.ts";
import { RULES, runRules } from "../../src/cli/doctor/rules.ts";
import { resolveConfig } from "../../src/config/index.ts";
import { moduleSnapshotFixture } from "../cli/fixtures/library.ts";

const MIGRATIONS = 1200;
const CEILING_MB = 300;

// SAFETY: `--expose-gc` puts `gc` on globalThis; without it the check below throws.
const gc = (globalThis as { gc?: () => void }).gc;

if (gc === undefined) {
  throw new Error("Run this benchmark with node --expose-gc.");
}

const migration = (index: number): string => {
  const branches = Array.from(
    { length: 120 },
    (_, arm) =>
      `    when 'entity_${String(arm)}' then\n      perform public.apply_${String(arm)}(run, ${String(index)});\n      raise notice 'applied %', run using hint = 'bsb_applied';`,
  ).join("\n");

  return `-- migration ${String(index)}
create or replace function public.import_step_${String(index)}(run uuid, entity text)
returns void language plpgsql as $$
begin
  case entity
${branches}
    else null;
  end case;
end $$;
`;
};

const sqlFiles = Array.from({ length: MIGRATIONS }, (_, index) => ({
  path: `supabase/migrations/${String(20_260_000_000_000 + index)}_step.sql`,
  text: migration(index),
}));

const context: DoctorContext = {
  config: resolveConfig({}, "/project"),
  snapshot: await parseSnapshot(moduleSnapshotFixture),
  configToml: undefined,
  envFiles: [],
  gitignore: "",
  sources: [],
  sqlFiles,
};

const live = (): number => {
  gc();

  return process.memoryUsage().heapUsed / 1e6;
};

const megabytes = sqlFiles.reduce((sum, file) => sum + file.text.length, 0);
const before = live();
const start = performance.now();

await runRules(
  context,
  RULES.filter((rule) => rule.code === "BS627" || rule.code === "BS629"),
);

const held = live() - before;
const seconds = (performance.now() - start) / 1000;

console.log(
  `doctor over ${String(MIGRATIONS)} migrations (${(megabytes / 1e6).toFixed(0)} MB): ${held.toFixed(0)} MB held, ${seconds.toFixed(1)} s`,
);

if (held > CEILING_MB) {
  throw new Error(
    `The SQL reader holds ${held.toFixed(0)} MB, past the ${String(CEILING_MB)} MB ceiling.`,
  );
}
