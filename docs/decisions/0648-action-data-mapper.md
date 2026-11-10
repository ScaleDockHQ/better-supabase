# 0648: Map the data of a bsb.action to another type with a third argument

- Status: accepted
- Date: 2026-11-10

## Context

`bsb.action` has a `result` option that maps the whole `ActionResult`, but it is typed
`ActionResult<unknown>` in and out, so an app that wants `ActionResult<ViewModel>` from a body that
returns a row has to cast or map in every caller. The plan item `p5b-next-rest` asked for a mapper that
changes the data type.

## Decision

`bsb.action(options, fn, map?)` takes `map(data)` as a third argument. A second option could not be typed,
because `T` comes from `fn`, which is the argument after the options. `map` receives the unwrapped data of
a successful body, may be async, and the declared return type is `ActionResult<O>` where `O` is its
return type (the body's type without a mapper). It runs after the `invalidates` tags drop, because the
write already happened. A `DbException` it throws becomes the error of the result; other errors propagate.
`result` stays for errors and the whole outcome, and runs last.

## Alternatives considered

- Widen `result` with generics: the options object is built before `fn`, so `T` can't flow in.
- A wrapper function `mapAction(action, map)`: it can't run before the cache tags and the result mapper.

## Consequences

`ActionMapper<D, O>` is a new type export of `better-supabase/next`. The runtime casts the returned
function once, because the declared signature carries the mapped type.
