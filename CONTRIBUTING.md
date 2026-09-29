# Contributing

Thanks for contributing to better-supabase. This repository is a pnpm and Turborepo monorepo with one published package, `packages/better-supabase`. Maintainer rules and invariants live in [`AGENTS.md`](./AGENTS.md).

## Requirements

- Node.js 24 or later (CI runs 24 LTS)
- pnpm 11.21.0, through Corepack
- Docker and the [Supabase CLI](https://supabase.com/docs/guides/local-development/cli/getting-started), for the integration and end-to-end suites

npm and Yarn are not supported.

```bash
corepack enable
corepack prepare pnpm@11.21.0 --activate
```

## Setup

```bash
pnpm install
pnpm run check
```

`pnpm install` runs `lefthook install` through the `prepare` script, so the Git hooks are set up locally.

| Command                  | What it does                                                |
| ------------------------ | ----------------------------------------------------------- |
| `pnpm run check`         | Format check, Oxlint, prose check and typecheck             |
| `pnpm run build`         | `turbo run build`                                           |
| `pnpm run test`          | Unit and type tests                                         |
| `pnpm typecheck:matrix`  | Published types against TypeScript 5.9, 6 and 7             |
| `pnpm typecheck:perf`    | Type-instantiation benchmark on a 150-table schema          |
| `pnpm size`              | Bundle size baselines and the WinterTC import check         |
| `pnpm test:integration`  | Integration tests against a running `supabase start` stack  |
| `pnpm test:e2e`          | The example apps against a running `supabase start` stack   |
| `pnpm run check:publish` | publint and arethetypeswrong on the packed tarball          |
| `pnpm run fmt`           | Format with Oxfmt                                           |
| `pnpm changeset`         | Add a changeset for a user-visible change                   |

The local stack uses the API on port 55421 and Postgres on 55422. Override them with `SUPABASE_URL` and `SUPABASE_DB_URL`.

## Commits

Commit messages follow [Conventional Commits](https://www.conventionalcommits.org/). Lefthook runs commitlint on `commit-msg`.

Allowed types: `feat`, `fix`, `docs`, `chore`, `ci`, `refactor`, `test`, `perf`, `style`, `revert`. The subject is lower-case and the header is at most 72 characters.

```
feat(sql): add vector search kit
docs: explain read replicas
```

## Pull requests

- Open a [feature request](https://github.com/ScaleDockHQ/better-supabase/issues/new?template=feature.yml) before adding a subpath, changing an exported identifier, or adding a CLI flag.
- Every user-visible change needs a changeset (`pnpm changeset`).
- Follow the "When you change X, also update Y" table in [`AGENTS.md`](./AGENTS.md).
- Docs pages are Fumadocs MDX. Each has a `title` and `description` in its frontmatter, no `# h1`, and a place in its folder's `meta.json`.

## Code of conduct

This project follows the [Contributor Covenant](./CODE_OF_CONDUCT.md).

## Security

Do not open public issues for vulnerabilities. See [`SECURITY.md`](./SECURITY.md).
