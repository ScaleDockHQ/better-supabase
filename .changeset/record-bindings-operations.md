---
"better-supabase": minor
---

The `bookings`, `expenses`, `leave` and `risks` blocks have record bindings. `bookingsBinding` loads a customer's bookings, `expensesBinding` a member's expense reports, `leaveBinding` the leave requests of an employee or a member, and `risksBinding` the open risks linked to a record. Each takes the organization from the block's `tenant` option. Bookings gets `forCustomer`, leave gets `forOwner` and risks gets `linkedTo`, with the SQL functions `list_bookings_for_customer` and `list_risks_for_subject`; run `better-supabase upgrade` and apply the new migration. `LeaveOptions` accepts `tenant`.

| Before                                                                                                      | After                                                                            |
| ----------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------- |
| `bookingsBlock.record`, `expensesBlock.record`, `leaveBlock.record` and `risksBlock.record` are `undefined` | They are `bookingsBinding`, `expensesBinding`, `leaveBinding` and `risksBinding` |
| A customer's bookings read by hand from the range list                                                      | `bookings.forCustomer({ subject })`                                              |
| Leave of an employee read with `list({ employeeId })` only                                                  | `leave.forOwner({ subject })`, or the binding                                    |
| Risks of a record found by hand through relations                                                           | `risks.linkedTo({ subject })`                                                    |
