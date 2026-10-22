---
"better-supabase": minor
---

Turn an event in one block into a record in another, and build forms from a block's entity schema with the organization's custom fields. See [Flows](https://bettersupabase.com/docs/blocks/flows), [Entity forms](https://bettersupabase.com/docs/blocks/entity-forms) and [Composing blocks](https://bettersupabase.com/docs/blocks/composing-blocks).

- `better-supabase/flows` is a new subpath. `defineFlow({ name, on, target, source, load, input, map, create })` describes a flow, and `createFlows({ flows, clients, enqueue })` runs the listed flows from the outbox through `flows.sink()`, or as jobs through `enqueue` and `flows.handler()`. A flow runs once per source record: it records a `created_from` relation and finds it again on a redelivered event. Flows carry `apiVersion: 1`.
- Four built-in flows, each off until listed: `conversationToWorkItem`, `applicationToEmployee`, `bookingToEngagement` and `quoteToOrder` (which takes your `create`, since orders have no conversion from a quote yet).
- `entityForm(schema, { fields, labels, customFields, timeZone })` in `better-supabase/records` lists the form fields of an entity schema and the custom fields, turns input text into typed values and validates both, returning the entity input and the custom values apart.
- `useEntityForm(form, { initial, onSubmit })` in `better-supabase/react` holds the values, errors and pending state of an entity form.
- The `entity-form` recipe renders the work item create dialog with the organization's custom fields.
