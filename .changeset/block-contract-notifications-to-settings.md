---
"better-supabase": minor
---

Blocks from `notifications` to `settings` follow the block contract.

`onboarding`, `outbox` and `settings` have a `create<Name>(options)` creator, and their manifests build it. `createOnboarding({ transport })` replaces `checklist.connect(...)`: its methods take the checklist first (`onboarding.complete(gettingStarted, "invite", organizationId)`), and `createOnboardingController` takes `client` and `checklist` instead of `scope`. `createSettings({ settings, transport })` replaces `settings.connect(...)`, with flat methods (`getUser`, `setUser`, `resetUser`, `getOrganization`, `setOrganization`, `resetOrganization`, `getPlatform`, `setPlatform`, `resetPlatform`); `defineSettings` returns only the `schemas`. `createOutbox({ transport, source })` replaces `createOutbox(source, options)`: pass `sqlTransport(postgres.admin)` for a server connection, and `service` for the consumer calls when `transport` acts as a user.

`hooks` (and `logger`) now work on `createNumberSequences`, `createPush`, `createRank`, `createRateLimit`, `createRelations`, `createReminders`, `createSavedViews`, `createServicePrincipals`, `createOnboarding`, `createSettings` and `createOutbox`; job handlers call their methods through the hooks. `createNotifications` sends its delivery calls through `blockCall`, so `deliver()` rejects with the mapped `DbError`.

`options.extraColumns` and a typed `fields` option cover the main table of `invitations` (as `invitationFields` on `createOrganizations`), `notifications`, `orders`, `pipelines`, `promotions`, `push`, `relations`, `reminders`, `saved-views` and `service-principals`, and `fields` now types the columns `parties` and `quotes` already took. Writes take `fields` and validate them before the call; reads return them in `fields`, built with `jsonb_build_object`, and parse them with the schema. Without `extraColumns` the SQL is unchanged.
