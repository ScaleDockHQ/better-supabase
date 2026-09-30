# Tooling

## Registry and versions

- Query the registry with `pnpm view <pkg> version` or `pnpm view <pkg> time --json`.
  Don't read `~/.npmrc` or other credential files.
- `minimumReleaseAge` in `pnpm-workspace.yaml` rejects a release younger than
  a day. Pin the previous release and move on; never lower the setting.
- Catalog entries are exact versions. A package the root uses goes into the
  catalog and into the root `devDependencies` as `catalog:`.

## Scripts and hooks

- `pnpm verify` is the gate. There is no `pnpm check` script.
- Lefthook formats and lints staged files on commit, runs commitlint on the
  message, and runs `turbo run lint typecheck test --affected` on push.
- Commit headers stay under 73 characters and body lines under 101.

## Changesets and releases

- `pnpm version-packages` runs `scripts/root-changelog.ts` before
  `changeset version`, because `changeset version` deletes the changeset
  files the root changelog is built from.
- The release workflow opens the version PR with `pnpm run version-packages`
  and publishes with `pnpm run release` when `NPM_PUBLISH` is set.

## CI

- The composite action in `.github/actions/setup` connects the Vercel Remote
  Cache through OIDC (the job needs `id-token: write`), then installs Node and
  pnpm with the store cache. Composite actions can't read the `vars` context,
  so pass values in as inputs.
- `verify.yml` is a reusable workflow with a `fail-fast: false` matrix. Add a
  check there as a new matrix entry, not as a new workflow.
- Turbo fails `lint` when code reads an env var that no `turbo.json` declares
  (`turbo/no-undeclared-env-vars`). Declare it in `globalEnv` or the task's `env`.
