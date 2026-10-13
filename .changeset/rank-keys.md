---
"better-supabase": minor
---

Add fractional rank keys. `better-supabase/blocks/rank` exports `rankBetween`, `rankKeys`, `isRankKey` and `createRank`, and the new `rank` SQL module adds `rank_between`, `move()` and a `rank.rebalance` job for subjects with a `rank` entry in `config.subjects`. `move()` runs as the caller and can change the row's group, so a state-machine trigger on that column checks the change.

Tags and custom fields now order definitions by a `rank` key instead of an integer `position`. Both modules move to version 2: the upgrade backfills keys in the old order and drops `position`. `tags.reorder` and `customFields.reorderDefinition` take the neighbours' keys. Adopt configs that mapped `position` map `rank` instead. An adopted table without a rank column maps it to `null` (`columns: { tags: { rank: null } }`, and `definitions` and `options` for custom fields); `sql sync` names the column until you do.

A state-machine config without `initial` now names `initial` in its error instead of `column`.
