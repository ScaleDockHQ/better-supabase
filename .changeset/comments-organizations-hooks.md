---
"better-supabase": minor
---

Add client controllers and hooks for the `comments` and `organizations` blocks. `createCommentsController` and `useComments()` (`better-supabase/blocks/comments/react`, `/vue`, `/svelte` and `/solid`) load one subject's thread and keep it current after `add`, `edit` and `remove`, which return a `Result`. `createOrganizationsController` and `useOrganizations()` (`better-supabase/blocks/organizations/react`, `/vue`, `/svelte` and `/solid`) list the caller's organizations, read the active one from the tenant claim, and switch with `switchTo()`, which refreshes the session when `switch_organization` asks for it. Both hooks run in React DOM and React Native, and the comment thread and organization switcher recipes show them in the Next.js and Expo examples.
