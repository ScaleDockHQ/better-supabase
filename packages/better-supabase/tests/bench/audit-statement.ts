// Times `update` on N audited rows with the restricted table on, in row mode
// and in statement mode, on in-process Postgres (PGlite).
//   node tests/bench/audit-statement.ts
import { loadLite, migrateLite, seedLite } from "../../src/lite/runtime.ts";
import { renderBlocks } from "../../src/sql/render.ts";

const SIZES = [48, 5000];
const RUNS = 5;

const ROLES = `
do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'supabase_auth_admin') then
    create role supabase_auth_admin;
  end if;
end;
$$;
create table public.customers (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  name text,
  api_key text,
  updated_at timestamptz not null default now()
);
`;

const ORG = "11111111-1111-4111-8111-111111111111";

const median = (values: readonly number[]): number =>
  [...values].toSorted((a, b) => a - b)[Math.floor(values.length / 2)]!;

const lite = await loadLite();

if (!lite) {
  throw new Error("Install @supabase/lite to run this benchmark.");
}

const files = renderBlocks(["audit"], {
  modules: { audit: { options: { restricted: true } } },
});

const connection = await lite.createPgliteConnection();
const target = { driver: "pglite", connection } as const;

await migrateLite(connection, [
  ROLES,
  ...files.filter((f) => f.kind === "schema").map((f) => f.contents),
]);

for (const file of files.filter((f) => f.kind === "data")) {
  await seedLite(target, file.contents);
}

const { driver } = connection;

const trigger = async (sql: string): Promise<string> => {
  const { rows } = await driver.query(`explain (analyze, buffers) ${sql}`);

  return rows
    .map((row) => String(Object.values(row as object)[0]))
    .filter((line) => line.startsWith("Trigger"))
    .join("; ");
};

const results: string[] = [];

for (const size of SIZES) {
  for (const mode of ["row", "statement"] as const) {
    await driver.exec(`
      select better_supabase.unaudit('public.customers'::regclass);
      truncate public.customers;
      insert into public.customers (organization_id, name, api_key)
        select '${ORG}', 'c' || i, 'secret' from generate_series(1, ${size}) i;
      select better_supabase.audit('public.customers', ignore => '{updated_at}', redact => '{api_key}', statement => ${mode === "statement"});
    `);

    const times: number[] = [];

    for (let run = 0; run < RUNS; run += 1) {
      const start = performance.now();
      await driver.exec(`update public.customers set name = name || 'x'`);
      times.push(performance.now() - start);
    }

    const detail = await trigger(
      `update public.customers set name = name || 'y'`,
    );

    results.push(
      `${String(size).padStart(5)} rows  ${mode.padEnd(9)} median ${median(times).toFixed(1)} ms  (runs: ${times.map((t) => t.toFixed(0)).join(", ")})  ${detail}`,
    );
  }
}

console.log(results.join("\n"));

await connection.close();
