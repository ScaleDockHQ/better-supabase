---
"better-supabase": minor
---

Glue for your app now installs with the shadcn CLI from the `@better-supabase` registry at `https://bettersupabase.com/r/{name}.json`: block wiring (`blocks`, `postgres`, `outbox`, `onboarding-checklist`), Next.js server actions for notifications, the `use-current-organization` and `push-native` hooks, route handlers for the outbox relay (Next.js and Hono), Stripe webhooks and the jobs drain, the Expo config, and the `saas-next` and `saas-expo` bundles. The registry holds no UI components, config or SQL.

The UI comes from recipes instead: the notification bell, notification list, command search and onboarding checklist show the shadcn components to add and the web and React Native code side by side, with the same hook call. They are on bettersupabase.com/recipes, in the docs at `/docs/registry/ui-recipes` and in the `better-supabase` skill (`references/ui-recipes.md`). `SPEC_PINS.shadcnRegistry` pins the shadcn registry schema the items follow.
