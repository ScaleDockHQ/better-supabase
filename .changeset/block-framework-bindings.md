---
"better-supabase": minor
---

The 14 blocks with a headless controller (ai-chat, announcements, bookings, calendar, forms, inbox, notifications, onboarding, reactions, saved-views, search, undo, workflows and workflow-builder) get `better-supabase/blocks/<name>/vue`, `/svelte` and `/solid` entries. Each exports the React hook names (`useInbox`, `useUndoStack` and so on) over the same controllers: Vue returns a shallow ref of the snapshot, Svelte a readable store and Solid an accessor from `from`, with the controller's actions next to it. They take the controller's options; `auth` and `ports` come from `betterSupabase(bs)`, `setBetterSupabase(bs)` or `<BetterSupabaseProvider>` unless you pass them. The work starts on mount, never during server rendering, and the controller is disposed with the component.

`testControllerBinding` from `better-supabase/testing` checks that a framework binding renders a controller's snapshot, follows its changes, passes its actions through and stops it on unmount. The React, Vue, Svelte and Solid bindings run it.
