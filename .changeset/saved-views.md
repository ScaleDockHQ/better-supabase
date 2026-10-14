---
"better-supabase": minor
---

Add the `saved-views` block. The SQL module stores named list views per user, team or organization, with one default per slot and rank order; sharing a view with a team or the organization needs `views.share`, and team views use the `teams` module. `better-supabase/blocks/saved-views` exports `createSavedViews`, which checks a view's query against its `defineListQuery` definition before saving, plus `savedViewStateSchema`, `defaultView` and helpers that convert between nuqs URL state and a stored query. `better-supabase/blocks/saved-views/react` exports `useSavedViews`, which opens the default view and saves the URL's query. The default roles gain `views.read` for members and `views.*` for admins.
