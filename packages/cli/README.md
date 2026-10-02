# @better-supabase/cli

The `better-supabase` command: project setup, code generation from your database, the SQL kit, doctor and local stack keys for [better-supabase](https://www.npmjs.com/package/better-supabase).

[![npm](https://img.shields.io/npm/v/@better-supabase/cli)](https://www.npmjs.com/package/@better-supabase/cli)
[![license](https://img.shields.io/badge/license-MIT-blue.svg)](https://github.com/ScaleDockHQ/better-supabase/blob/main/LICENSE)

## Install

```bash
pnpm add better-supabase @supabase/supabase-js
pnpm add -D @better-supabase/cli pg
```

The CLI is released at the same version as `better-supabase`; keep the two in step. It needs Node 24 or later. In a new project, `npx @better-supabase/cli init` writes the config and framework glue, then prints the install command.

## Usage

```bash
supabase start
pnpm better-supabase init     # config, src/lib/supabase.ts and framework glue
pnpm better-supabase gen      # database.types.ts and generated.ts
pnpm better-supabase doctor   # RLS, indexes, drift, auth config and env files
```

Every command takes `--help`. Commands that write files accept `--check` (exit 1 on drift, with a diff) or `--dry-run`. In a terminal, `init` and `add` ask for the casing, the integrations and overwrites; `--yes` and CI skip the questions.

## Programmatic use

`run` never calls `process.exit`. It returns the exit code and the output:

```ts
import { run } from "@better-supabase/cli";

const { code, stdout, stderr } = await run(["gen", "--check"]);
```

Add your own commands with `defineCliCommand` and `registerCommand`; see [the CLI docs](https://bettersupabase.com/docs/cli#programmatic-use).

## Documentation

[bettersupabase.com/docs/cli](https://bettersupabase.com/docs/cli)

## License

[MIT](https://github.com/ScaleDockHQ/better-supabase/blob/main/LICENSE)
