# 0041: Deploy a Create preset through a Supabase OAuth app

- Status: accepted
- Date: 2026-10-18

## Context

Create hands its result to the CLI: copy a command, run `init --preset`,
then `sql sync` and a migration. Visitors asked to try a preset on a real
project first, with no local setup. The projects are theirs, in their own
Supabase account, and Create has no database or user accounts of its own
(ADR 0040 keeps designs in the URL for the same reason). Supabase offers two
ways in: Platform Kit, which manages projects that a platform creates in its
own organization, and an OAuth app, which acts on the visitor's account with
their consent.

## Decision

`/create` shows a Deploy to Supabase button when the marketing app has
`SUPABASE_OAUTH_CLIENT_ID`, `SUPABASE_OAUTH_CLIENT_SECRET` and
`SUPABASE_OAUTH_COOKIE_SECRET` (`apps/marketing/env.ts`). The dialog posts a
form to `/create/supabase/connect`, which starts an authorization code flow
with PKCE. The callback exchanges the code and keeps the tokens in an
AES-GCM sealed, `httpOnly` cookie scoped to `/create/supabase`
(`lib/supabase-oauth.ts`, `lib/supabase-session.ts`). Nothing is stored on
our side.

The visitor picks an existing project or creates one through the
Management API (`lib/supabase-management.ts`). The deploy route renders the
SQL on the server from the preset and design codes with `previewFiles`, so
the browser never sends SQL. It joins every schema file and then every data
file into one migration, `better_supabase_blocks`, and applies it with
`POST /v1/projects/{ref}/database/migrations`, which runs it in a
transaction. pgTAP files stay out. A project with tables in `public` needs
an explicit confirm, checked again on the server. Presets with
`access: "provider"` can't deploy, because their preview renders a stand-in
provider schema. The result lists the security advisor's lints and the CLI
commands that link the project and fetch the migration.

## Alternatives considered

Platform Kit lost because it creates projects in our organization: we would
own and pay for every visitor's database, and moving one to the visitor's
account is a manual transfer. Asking for a personal access token works
without an OAuth app, but it teaches people to paste a token with full account access
into a website. Running the CLI in a sandbox would need the visitor's
database password and a server with Docker. Sending the rendered SQL from
the browser would let any page call the deploy route with arbitrary SQL
under the visitor's token.

## Consequences

Trying a preset takes a consent screen and a project instead of a local
stack. The marketing app now has server routes that call Supabase on a
visitor's behalf, so the OAuth app's scopes, the cookie secret and the
same-origin checks on every write need care. The deploy writes one
migration, and the visitor's repo still has to fetch it with
`supabase migration fetch` before `sql sync` takes over. Deploying a design
twice applies the migration twice; the modules are idempotent, but a changed
app table column still needs a migration by hand, as in ADR 0040. If
Supabase ships a deploy button for OAuth apps, or Create gains accounts,
revisit this.
