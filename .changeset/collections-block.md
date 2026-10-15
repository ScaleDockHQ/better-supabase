---
"better-supabase": minor
---

The `collections` SQL module and `better-supabase/blocks/collections` add favorites and lists on any record registered in `config.subjects`. Favorites are a member's own stars, ranked for a sidebar (`star`, `unstar`, `starred`, `reorderStar`). Lists are named, static collections of one record type owned by a user, a team or the organization (`create`, `rename`, `archive`, `add`, `remove`, `reorder`, keyset-paged `entries` and `listsOf`); an entry is visible only when the caller can read its record, and deleting a record with `cascade: true` deletes its entries and stars. A saved view can keep to a list through `state.collectionId` and `collections.where(id)`, and the bulk module gains the `collections.add` action.
