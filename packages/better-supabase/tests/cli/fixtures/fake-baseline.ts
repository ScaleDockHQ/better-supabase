import { mkdir, mkdtemp, readFile, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { basename, join } from "node:path";

import type { BaselineContext } from "../../../src/cli/baseline/stack.ts";
import type { PgConnection, PgQueryable } from "../../../src/cli/db.ts";
import type { CliEnv } from "../../../src/cli/env.ts";
import type { ExecResult } from "../../../src/cli/exec.ts";
import type { PgDelta } from "../../../src/cli/in-stack-diff.ts";

import { PROCESS_ENV, parseEnv } from "../../../src/cli/env.ts";
import { runProcess } from "../../../src/cli/exec.ts";

interface Queue {
  readonly queue_name: string;
  readonly is_partitioned: boolean;
  readonly is_unlogged: boolean;
}

/** What one fake database holds at a point in time. */
export interface DbState {
  readonly catalog: string;
  readonly signatures: Readonly<Record<string, string>>;
  readonly sequences: readonly string[];
  readonly extensionTables: readonly string[];
  /** `undefined` when the pgmq extension is not installed. */
  readonly queues: readonly Queue[] | undefined;
  readonly triggers: readonly string[];
  readonly fingerprint: Readonly<Record<string, string>>;
  readonly migrations: number;
}

const queue = (name: string, unlogged = false): Queue => ({
  queue_name: name,
  is_partitioned: false,
  is_unlogged: unlogged,
});

export const EMPTY: DbState = {
  catalog: "empty",
  signatures: {
    "auth.users": "0:",
    "extensions.lookup": "3:e",
    "cron.job_run_details": "4:n",
  },
  sequences: [],
  extensionTables: ["extensions.lookup"],
  queues: [],
  triggers: [],
  fingerprint: { policies: "p0" },
  migrations: 0,
};

export const MIGRATED: DbState = {
  ...EMPTY,
  catalog: "migrated",
  signatures: {
    ...EMPTY.signatures,
    "public.plans": "2:a",
    "pgmq.q_jobs": "1:q",
  },
  sequences: ["public.plans_id_seq 2"],
  queues: [queue("jobs"), queue("fast", true)],
  triggers: [
    "create trigger notify after insert on pgmq.q_jobs execute function f();",
  ],
  fingerprint: { policies: "p1", functions: "f1" },
  migrations: 2,
};

export const SEEDED: DbState = {
  ...MIGRATED,
  catalog: "seeded",
  signatures: {
    ...MIGRATED.signatures,
    "auth.users": "1:u",
    "public.plans": "3:b",
  },
  queues: [...(MIGRATED.queues ?? []), queue("mail")],
  triggers: [
    ...MIGRATED.triggers,
    "create trigger audit after insert on pgmq.q_mail execute function f();",
  ],
  fingerprint: { policies: "p2", functions: "f1" },
};

function answer(state: DbState, text: string): unknown[] {
  if (text.includes("query_to_xml")) {
    return Object.entries(state.signatures).map(([key, sig]) => {
      const [schema, name] = key.split(".");

      return { schema, name, sig };
    });
  }

  if (text.includes("pg_sequences")) {
    return state.sequences.map((line) => {
      const [qualified = "", value] = line.split(" ");
      const [schemaname, sequencename] = qualified.split(".");

      return { schemaname, sequencename, last_value: value };
    });
  }

  if (text.includes("pg_depend")) {
    return state.extensionTables.map((key) => {
      const [schema, name] = key.split(".");

      return { schema, name };
    });
  }

  if (text.includes("to_regclass('pgmq.meta')")) {
    return [{ found: state.queues === undefined ? null : "pgmq.meta" }];
  }

  if (text.includes("from pgmq.meta")) {
    return [...(state.queues ?? [])];
  }

  if (text.includes("pg_get_triggerdef(t.oid) || ';'")) {
    return state.triggers.map((statement) => ({ statement }));
  }

  if (text.includes("group by kind")) {
    return Object.entries(state.fingerprint).map(([kind, digest]) => ({
      kind,
      digest,
    }));
  }

  if (text.includes("server_version")) {
    return [{ server_version: "17.6" }];
  }

  if (text.includes("to_regclass('supabase_migrations.schema_migrations')")) {
    return [{ found: state.migrations > 0 ? "schema_migrations" : null }];
  }

  if (text.includes("from supabase_migrations.schema_migrations")) {
    return [{ n: String(state.migrations) }];
  }

  throw new Error(`unexpected query: ${text}`);
}

export interface FakeWorld {
  readonly root: string;
  readonly ctx: BaselineContext;
  readonly log: string[];
  /** Every supabase and Postgres tool call, as one line each. */
  readonly calls: string[];
  /** Databases by port. */
  readonly dbs: Map<string, DbState>;
  readonly connect: (url: string) => Promise<PgConnection>;
  readonly openPool: (url: string) => Promise<never>;
  readonly delta: PgDelta;
  /** The local stack's URL, for `apply`. */
  readonly localUrl: string;
  /** Answers the next `supabase start` with this failure. */
  failStart: string | undefined;
  /** Fails every `psql --single-transaction` load. */
  failLoad: boolean;
  /** What a seed file run turns the database into. */
  seeded: DbState;
}

const portOf = (url: string): string => new URL(url).port;

const ok = (stdout = ""): ExecResult => ({ code: 0, stdout, stderr: "" });

/** A project folder with two migrations, seed files and a bucket. */
export async function fakeProject(): Promise<string> {
  const root = await mkdtemp(join(tmpdir(), "bsb-baseline-"));
  const supabase = join(root, "supabase");

  await mkdir(join(supabase, "migrations"), { recursive: true });
  await mkdir(join(supabase, "seeds"), { recursive: true });
  await mkdir(join(supabase, "buckets", "avatars", "nested"), {
    recursive: true,
  });

  await writeFile(
    join(supabase, "config.toml"),
    [
      'project_id = "baseline"',
      "",
      "[db.seed]",
      'sql_paths = ["./seed.sql", "./seeds/*.sql", "./seed.sql"]',
      "",
      "[storage.buckets.avatars]",
      'objects_path = "./buckets/avatars"',
      "",
      "[storage.buckets.empty]",
      "public = true",
      "",
    ].join("\n"),
  );

  await writeFile(
    join(supabase, "migrations", "20240101000000_init.sql"),
    "create table plans ();\n",
  );

  await writeFile(
    join(supabase, "migrations", "20240102000000_queue.sql"),
    "select pgmq.create('jobs');\n",
  );

  await writeFile(
    join(supabase, "seed.sql"),
    "insert into plans default values;\n",
  );
  await writeFile(join(supabase, "seeds", "b.sql"), "select 2;\n");
  await writeFile(join(supabase, "seeds", "a.sql"), "select 1;\n");
  await writeFile(join(supabase, "buckets", "avatars", "me.png"), "png");

  await writeFile(
    join(supabase, "buckets", "avatars", "nested", "read me.txt"),
    "text",
  );

  return root;
}

/**
 * A fake Supabase CLI, Postgres tools, databases and pg-delta for the baseline
 * commands. `supabase start` makes a database, the loads and seed runs move it
 * between the EMPTY, MIGRATED and SEEDED states.
 */
export function fakeWorld(root: string, env: CliEnv = parseEnv({})): FakeWorld {
  const dbs = new Map<string, DbState>();
  const stacks = new Map<string, string>();
  const calls: string[] = [];
  const log: string[] = [];
  let nextPort = 55_000;

  const urlOf = (port: string): string =>
    `postgresql://postgres:postgres@127.0.0.1:${port}/postgres`;

  stacks.set("local", "54322");
  dbs.set("54322", EMPTY);

  const stateOf = (url: string): DbState => {
    const state = dbs.get(portOf(url));

    if (state === undefined) {
      throw new Error(`no database at ${url}`);
    }

    return state;
  };

  const supabase = (
    args: readonly string[],
    _cwd: string,
    cliEnv: CliEnv,
  ): Promise<ExecResult> => {
    calls.push(`supabase ${args.join(" ")}`);

    if (args[0] === "--version") {
      return Promise.resolve(ok("Supabase CLI\n2.40.0\n"));
    }

    if (args[0] === "start") {
      if (world.failStart !== undefined) {
        return Promise.resolve({
          code: 1,
          stdout: "",
          stderr: world.failStart,
        });
      }

      const port = String(nextPort);
      nextPort += 1;
      stacks.set(args[2] ?? "", port);

      dbs.set(
        port,
        cliEnv[PROCESS_ENV]?.["SUPABASE_DB_MIGRATIONS_ENABLED"] === "false"
          ? EMPTY
          : MIGRATED,
      );

      return Promise.resolve(ok());
    }

    if (args[0] === "status") {
      const name = args[1] === "--stack" ? (args[2] ?? "") : "local";
      const port = stacks.get(name);

      if (port === undefined) {
        return Promise.resolve({ code: 1, stdout: "", stderr: "not running" });
      }

      return Promise.resolve(
        ok(
          `Stack status\n${JSON.stringify({
            env: {
              DB_URL: urlOf(port),
              API_URL: `http://127.0.0.1:${port}`,
              SECRET_KEY: `key-${name}`,
            },
            identity: { id: `id-${name}` },
          })}`,
        ),
      );
    }

    if (args[0] === "stack" && args[1] === "destroy") {
      const id = args[3] ?? "";
      stacks.delete(id.replace(/^id-/, ""));

      return Promise.resolve(ok());
    }

    if (args[0] === "migration" && args[1] === "up") {
      dbs.set(stacks.get("local") ?? "", MIGRATED);

      return Promise.resolve(ok());
    }

    return Promise.resolve({ code: 1, stdout: "", stderr: "unknown command" });
  };

  const run = async (
    command: string,
    args: readonly string[],
    cwd: string,
    cliEnv: CliEnv,
  ): Promise<ExecResult> => {
    const tool = basename(command);

    if (tool === "tar") {
      return runProcess(command, args, cwd, cliEnv);
    }

    calls.push(`${tool} ${args.filter((arg) => !arg.includes("/")).join(" ")}`);
    const url = args.at(-1) ?? "";

    if (tool === "pg_dump") {
      const file = args[args.indexOf("-f") + 1] ?? "";
      const tables = args.filter((_, index) => args[index - 1] === "-t");
      await writeFile(file, `-- rows of ${tables.join(", ")}\n`);

      return ok();
    }

    if (args.includes("-c")) {
      return ok("1\t{}\n");
    }

    if (args.includes("--single-transaction")) {
      if (world.failLoad) {
        return { code: 3, stdout: "", stderr: "line 1\nline 2\nERROR: boom" };
      }

      const files = args.filter((_, index) => args[index - 1] === "-f");

      for (const file of files) {
        await readFile(file, "utf-8");
      }

      dbs.set(
        portOf(url),
        files.some((file) => file.endsWith(join("seed", "data.sql")))
          ? SEEDED
          : MIGRATED,
      );

      return ok();
    }

    dbs.set(portOf(url), world.seeded);

    return ok();
  };

  const client = (url: string): PgQueryable => ({
    query: <R>(text: string) =>
      // SAFETY: answer builds rows in the shape each baseline query selects.
      Promise.resolve({ rows: answer(stateOf(url), text) as R[] }),
  });

  const delta = {
    ENGINE_VERSION: "engine-1",
    rawProfile: "raw",
    resolveProfile: (_pool: unknown, profile: unknown) =>
      Promise.resolve({
        planOptions: { profile },
        extract: (pool: { readonly url: string }) =>
          Promise.resolve({
            pgVersion: "170006",
            factBase: {
              catalog: stateOf(pool.url).catalog,
              edges: [
                { kind: "memberOfExtension", from: "table:extensions.lookup" },
                { kind: "dependsOn", from: "table:public.plans" },
              ],
            },
          }),
      }),
    plan: (
      from: { readonly catalog: string },
      to: { readonly catalog: string },
    ) => ({
      actions:
        from.catalog === to.catalog
          ? []
          : [
              {
                sql: `create table ${to.catalog} ()`,
                produces: [`table:public.${to.catalog}`],
                consumes: [],
              },
              {
                sql: "  create index on plans (id);  ",
                produces: ["index:public.plans_id"],
                consumes: ["table:public.plans"],
              },
              {
                sql: "comment on table extensions.lookup is 'x'",
                produces: ["comment:(table:extensions.lookup)"],
                consumes: [],
              },
              {
                sql: "grant select on extensions.lookup to anon",
                produces: ["acl:(table:extensions.lookup).anon"],
                consumes: [],
              },
            ],
    }),
    encodeId: String,
    serializeSnapshot: (facts: unknown, options: { pgVersion: string }) =>
      JSON.stringify({ facts, pgVersion: options.pgVersion }),
    deserializeSnapshot: (text: string) => {
      const parsed = JSON.parse(text) as { facts: unknown; pgVersion: string };

      return { factBase: parsed.facts, pgVersion: parsed.pgVersion };
    },
  };

  const world: FakeWorld = {
    root,
    log,
    calls,
    dbs,
    localUrl: urlOf("54322"),
    failStart: undefined,
    failLoad: false,
    seeded: SEEDED,
    ctx: {
      root,
      env,
      log: (line) => {
        log.push(line);
      },
      supabase,
      run,
    },
    connect: (url) =>
      Promise.resolve({
        client: client(url),
        close: () => Promise.resolve(),
        describe: url,
      }),
    openPool: (url) =>
      // SAFETY: the fake pool carries its URL for the fake pg-delta and ends.
      Promise.resolve({ url, end: () => Promise.resolve() } as never),
    // SAFETY: the fake provides the parts of pg-delta that baseline calls.
    delta: delta as unknown as PgDelta,
  };

  return world;
}
