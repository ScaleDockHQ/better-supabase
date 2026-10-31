---
"better-supabase": minor
---

Adds the `care` preset for home care, nursing homes, disability care and youth care. It installs contacts for
clients and their representatives, guest access, encrypted fields, audit with read logging on the
client, data lifecycle, consents, activities, care plans, observations with the vitals catalog,
medications, forms, bookings, calendar, reminders, time tracking, funding, shifts, qualifications,
courses, cases for incidents, staff incidents and complaints, acknowledgements, the drive with
controlled documents released through approvals, and signatures. Missed doses open an incident, and
tracked time registers funding deliveries. Install it with `better-supabase add --preset care`.

A block entity that registers a subject now takes `team` and `auditReads`, the same settings as an
app table subject, and a preset instance passes them under `subjects`:

```ts
blocks: {
  contacts: {
    entities: { person: { team: { actions: ["read", "write"] }, auditReads: true } },
  },
},
```

The settings are refused on an entity that registers no subject.
