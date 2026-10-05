# Contributing

Thanks for contributing to better-supabase. This repository is a pnpm and Turborepo monorepo with one published package, `better-supabase` in `packages/better-supabase`, which also ships the `better-supabase` CLI from `src/cli`. Maintainer rules and invariants live in [`AGENTS.md`](./AGENTS.md).

## Requirements

- Node.js 24 or later (CI runs 24 LTS)
- pnpm 12.8.1, the version pinned in `packageManager`
- Docker and the [Supabase CLI](https://supabase.com/docs/guides/local-development/cli/getting-started), for the integration suites
- The Vercel CLI, to pull the hosted environment variables (maintainers only; everything runs without them)

`devEngines` in `package.json` downloads the right Node version for pnpm. npm and Yarn are not supported. Any pnpm 11 or later switches to the pinned version on its own. Install pnpm with its [standalone installer](https://pnpm.io/installation) rather than Corepack, because pnpm does not switch versions when Corepack runs it.

## Setup

```bash
pnpm install
pnpm run verify
```

`pnpm install` runs `lefthook install` through the `prepare` script, so the Git hooks are set up locally.

### First local run

```bash
pnpm install
vercel link           # maintainers: link the scaledock team's project
pnpm env:pull         # maintainers: hosted keys in .env.local
pnpm supabase:start   # API on 55421, Postgres on 55422
pnpm env:local        # local stack and Portless URLs in .env.development.local
pnpm dev:portless     # docs, marketing and the Next.js example over HTTPS
```

The first `pnpm dev:portless` asks to trust the Portless certificate authority. The apps are then served on stable HTTPS URLs:

| App             | URL                           |
| --------------- | ----------------------------- |
| Marketing       | `https://www.localhost`       |
| Docs            | `https://docs.localhost/docs` |
| Next.js example | `https://example.localhost`   |

The seed creates two users in the Acme organization, both with the password `password123`: `admin@acme.test` (role `admin`) and `member@acme.test` (role `member`).

### Commands

| Command                  | What it does                                                              |
| ------------------------ | ------------------------------------------------------------------------- |
| `pnpm run verify`        | Format check, lint, prose, typecheck, boundaries, tests, doctor and audit |
| `pnpm dev:portless`      | Docs, marketing and the Next.js example on `.localhost` URLs              |
| `pnpm run build`         | `turbo run build`                                                         |
| `pnpm run test`          | Unit and type tests                                                       |
| `pnpm typecheck:matrix`  | Published types against TypeScript 6 and 7                                |
| `pnpm typecheck:perf`    | Type-instantiation and `gen` time benchmark on 150- and 250-table schemas |
| `pnpm size`              | Bundle size baselines and the WinterTC import check                       |
| `pnpm test:integration`  | Integration tests against a running `supabase start` stack                |
| `pnpm supabase:reset`    | Rebuilds the local database from the migrations and the seed              |
| `pnpm supabase:test`     | pgTAP tests in `supabase/tests`                                           |
| `pnpm db:gen`            | Regenerates the typed client in every example and validation project      |
| `pnpm run check:publish` | publint and arethetypeswrong on the packed tarball                        |
| `pnpm run format`        | Format with Oxfmt                                                         |
| `pnpm changeset`         | Add a changeset for a user-visible change                                 |

The local stack uses the API on port 55421 and Postgres on 55422. Override them with `SUPABASE_URL` and `SUPABASE_DB_URL`. It needs Docker; `SUPABASE_EXPERIMENTAL_STACK=1` runs it on the Supabase CLI's native stack instead (its Realtime private channels fail the integration tests). After you edit `supabase/schemas`, create the migration with `pnpm supabase:sync <name>` (see `docs/agents/database.md`).

Before the first `supabase start`, create the stack's ES256 signing key with `node packages/better-supabase/src/cli/bin.ts keys --cwd .`. It writes `supabase/signing_keys.json` (gitignored), which `config.toml` loads, and the integration tests sign their tokens with it.

## Layout

```text
packages/better-supabase   the published library, the better-supabase CLI and its consumer skills
packages/next-config       shared Next.js config for docs and marketing
packages/ox-config         Oxlint presets, Oxfmt config and the anti-slop plugin
packages/typescript-config tsconfig presets
apps/docs                  bettersupabase.com/docs (Fumadocs)
apps/marketing             bettersupabase.com
apps/examples/*            one runnable app per adapter
tests/*                    bundle size, the TypeScript matrix and validation ports
supabase/                  the local stack: schemas, migrations, seed and pgTAP tests
docs/                      agent notes and architecture decision records
```

## Architecture

The package is one ESM module with subpath exports. The runtime entries import no Node built-ins, so they run on every WinterTC runtime; the CLI, `postgres` and `testing` entries run on Node. The CLI introspects the local database and writes `database.types.ts` and `generated.ts` into each app, and those files carry every type through inferring functions, without `declare module`. The examples and the integration suite run against the fixture schema in `supabase/`. [`AGENTS.md`](./AGENTS.md) lists the invariants.

## Deploy and release

Docs and marketing deploy to Vercel as two services of one project (`vercel.json`), on the domain bettersupabase.com: `/docs` goes to the docs app and everything else to marketing, in the `fra1` region. Only `main` deploys (`git.deploymentEnabled`), and `turbo-ignore` skips a service whose app did not change.

The npm package is released by `.github/workflows/release.yml`: changesets open a version pull request, and merging it publishes to npm with provenance when the `NPM_PUBLISH` variable is set.

## Commits

Commit messages follow [Conventional Commits](https://www.conventionalcommits.org/). Lefthook runs commitlint on `commit-msg`.

Allowed types: `feat`, `fix`, `docs`, `chore`, `ci`, `refactor`, `test`, `perf`, `style`, `revert`. The subject is lower-case and the header is at most 72 characters.

```
feat(sql): add vector search kit
docs: explain read replicas
```

## Pull requests

- Open a [feature request](https://github.com/ScaleDockHQ/better-supabase/issues/new?template=feature.yml) before adding a subpath, changing an exported identifier, or adding a CLI flag.
- Every user-visible change needs a changeset (`pnpm changeset`). The two packages are in one `fixed` group, so a changeset for either releases both.
- Follow the "When you change X, also update Y" table in [`AGENTS.md`](./AGENTS.md).
- Docs pages are Fumadocs MDX. Each has a `title` and `description` in its frontmatter, no `# h1`, and a place in its folder's `meta.json`.

## Code of conduct

This project follows the [Contributor Covenant](./CODE_OF_CONDUCT.md).

## Security

Do not open public issues for vulnerabilities. See [`SECURITY.md`](./SECURITY.md).
