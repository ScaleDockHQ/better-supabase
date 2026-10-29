# Expo and PowerSync example

An Expo Router app over the fixture database. On the web, server loaders read
through PostgREST (`bsb.loader`, `bsb.bootstrap`). On iOS and Android, screens
read the PowerSync database, and the sync service streams each user the rows
of the organizations and teams they belong to.

## Run it

1. From the repository root, start the stack and load the fixture:
   `pnpm supabase:start`, then `pnpm supabase:reset`.
2. Copy the Supabase URL and publishable key into `.env.local` as
   `EXPO_PUBLIC_SUPABASE_URL` and `EXPO_PUBLIC_SUPABASE_PUBLISHABLE_KEY`.
3. For the native app, set `EXPO_PUBLIC_POWERSYNC_URL` to a PowerSync instance
   (see below), then run `pnpm dev` and open the iOS or Android build.

## What it shows

| Where                             | What                                                                                           |
| --------------------------------- | ---------------------------------------------------------------------------------------------- |
| `src/app/_layout.native.tsx`      | `<SessionProvider>` with `AppState` and `powersync={sync}`: one Realtime subscription per user |
| `src/lib/powersync/sync.ts`       | `syncWithAuth`, and `afterSwitch`: refresh the session, then `sync.reconnect()`                |
| `src/components/revoke-admin.tsx` | Takes the admin role from a member, so you can watch their device drop rows                    |
| `src/app/activity.tsx`            | A web loader that reads the session, the live authorization version and counts in one call     |
| `powersync/sync-streams.yaml`     | Streams that `better-supabase gen` writes, for notifications, memberships, teams and profiles  |

`sessions.authzVersions` is on, so a role change bumps the member's
authorization version. Their device refreshes the token, `syncWithAuth` sees the
new version claim and reconnects, and the sync service evaluates the streams
again under the new token. The streams here filter on membership, so removing a
member from an organization removes its rows from their device; a stream that
filters on the role drops the rows the old role could read the same way.

`better-supabase gen` regenerates the streams and the client schema
(`powersync/schema.ts`) from `gen.powersync` after a config change. The
fixture database has no `powersync` publication, because only this example
syncs; the manual check below creates it.

## Manual check against a real sync service

The test suite runs against a fake sync service. Before a release that changes
`syncWithAuth`, the streams or the version claim, check the flow once against a
real one:

1. Run `better-supabase powersync streams` in this folder. It writes a
   `supabase/migrations/*_powersync_publication.sql` file: run it against the
   local database with `psql`, then delete the folder so the fixture stays the
   only migration history.
2. Create a PowerSync instance (cloud or self-hosted) connected to the local
   database, with Supabase Auth as the JWT source, and deploy
   `powersync/sync-streams.yaml` to it.
3. Sign in on a device as a member with the admin role in two organizations,
   and on a second device as an owner of the first organization.
4. As the owner, revoke the member's admin role with the Revoke admin action on
   the team screen.
5. Within a few seconds the member's device refreshes its token and reconnects:
   the synced membership row shows the `member` role and the admin actions are
   gone, without restarting the app.
6. As the owner, remove the member from the organization. Confirm the
   organization, its teams and its memberships are gone from the device
   database.
7. Add the member back, put the app in the background, change their role, and bring it back.
   Confirm it catches up on the change it missed.
8. Switch organizations on the activity screen. Confirm the switch returns only
   after the device reconnected with a token for the new organization.
9. Sign out. Confirm the device database is empty.
