---
"better-supabase": minor
---

Add the bookings block (`better-supabase/blocks/bookings` and `better-supabase/blocks/bookings/react`): bookable resources with weekly hours, exceptions and a capacity, services with a duration and buffers, open slots from the `available_slots` SQL function, holds that a `bookings.expire-holds` job cancels, an exclusion constraint that refuses double bookings (the module installs `btree_gist`), public booking through a share link with a rate limit and an access token, confirmed bookings copied into the calendar block, customer reminders, and a `useAvailableSlots` hook typed for headless time pickers such as ReUI's.
