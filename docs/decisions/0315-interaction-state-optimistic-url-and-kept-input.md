# 0315: Keep interaction state in `useOptimistic`, the URL and the action state

- Status: accepted
- Date: 2026-11-07
- Amends: 0310

## Context

The audit found a hand-rolled `pending` boolean around the comment thread's
submit, list searches held in `useState` (a shared link lost them), and auth
forms that cleared the email after a rejected sign-in because React resets an
uncontrolled form after its action.

## Decision

- The comment thread submits inside `useTransition` and shows the new comment
  through `useOptimistic` at once; the server's list replaces it. It keeps no
  `pending` state of its own.
- The members, teams and employees searches (and the teams status filter) live
  in the URL: `lib/url-filters.ts` exports `useUrlParam` and `useSearchParam`
  (`?q=`, cleared at its default, URL writes debounced 250 ms through
  `history.replaceState`), so a link carries the filter and a reload keeps it.
  The hooks use `useSearchParams` and no nuqs: the nuqs hooks add about 7 kB
  to the first load of the routes that use them, and the next-build baseline
  never grows.
- A form whose action can reject returns the submitted values in its action
  state and the fields read them as `defaultValue`: the login and forgot
  password forms keep the email, the sign-up form keeps the name and the email.
  Passwords are never returned.

## Consequences

Other hand-rolled lists keep `useState` until they gain a shareable filter.
The customers list keeps the library's `customerList.nuqs` parsers.
