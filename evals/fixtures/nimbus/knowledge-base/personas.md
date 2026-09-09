# Personas

**FILLED FIXTURE. Nimbus Freight is fictional.**

A persona is only useful here if it is identified by a predicate at a grain. Every
persona below has one, or an honest `NOT IDENTIFIABLE`.

### Shipping coordinator

- Grain: user
- Identifying predicate: `users.role = 'coordinator'`
- Populated on 94% of user rows. The other 6% are NULL and are not assigned a persona.
- What they do: create shipments, chase status. They are the daily active user.

### Operations director

- Grain: user
- Identifying predicate: `users.role = 'ops_director'`
- What they do: look at the dashboard weekly, sign the renewal. Low event volume, high
  influence. A retention metric built on event frequency will call them inactive.

### Carrier dispatcher

- Grain: user
- Identifying predicate: **NOT IDENTIFIABLE.** Dispatchers work for the carrier, not the
  customer, and reach Nimbus through a public tracking link with no account. They have no
  `users` row and their PostHog events carry no `account_id`.
- Effect: any funnel that starts at a tracking-link view cannot be attributed to an
  account. Do not try.

## Segments that are not personas

Plan tier and carrier count are cuts, listed in `metrics.md`. They describe the account,
not the human. Do not report them as personas.
