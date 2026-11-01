---
"better-supabase": minor
---

The warehouse block suggests putaway (rules, bins that hold the variant, free bins by walking rank, also per goods receipt) and slotting (fast movers into the closest bins), saves walking routes on pick lists and orders them through the `RouteOptimizer` port with its nearest-neighbour fallback (`optimizePickRoute`), and `completePickList` now moves the picker's work item to done. New tables: `putaway_rules`, `bin_slots`, `variant_sizes`; new column `pick_lines.route_position`. See ADR 0177.
