# Personas

**Status: TEMPLATE. Nothing below is a fact about your product. Fill it in.**

Every block marked `EXAMPLE` describes a fictional company called **Nimbus Freight**.
Nimbus Freight does not exist. Delete the examples once you have written your own.

---

## The rule that makes this file useful

A persona the agent cannot identify in a query is decoration. It cannot be counted,
segmented, or compared, so it never appears in a report.

Every persona below needs a row in **How to identify in the data** that is a literal
predicate against a real column or event property. If you cannot write one, write
`NOT IDENTIFIABLE` and say what would make it identifiable. That is an honest answer
and it is useful. A guess is not.

Keep the list short. Three to five personas. A list of eleven means nobody has picked.

---

## Persona template

Copy this block once per persona.

### `TODO: persona name`

| Field | Your answer |
|---|---|
| One-line description | `TODO` |
| What they are trying to get done | `TODO` |
| How often they use the product | `TODO` |
| **How to identify in the data** | `TODO: a literal predicate, or NOT IDENTIFIABLE plus what would fix it` |
| Which source carries that field | `TODO` |
| Roughly how many there are | `TODO: a count, with the date you counted` |
| What success looks like for them | `TODO: an observable behaviour, not a feeling` |
| The metric that tracks that success | `TODO: must exist in metrics.md` |
| What makes them leave | `TODO` |

---

## Worked examples

*Everything below is EXAMPLE content for the fictional Nimbus Freight.*

### EXAMPLE persona: Shipping coordinator

| Field | Answer |
|---|---|
| One-line description | Books and babysits freight all day. The daily user. |
| What they are trying to get done | Know a shipment is late before the customer tells them. |
| How often they use the product | Every weekday, 20 or more sessions. |
| **How to identify in the data** | `users.role = 'coordinator'` in Postgres `public.users`. Set at invite time, 94% populated. |
| Which source carries that field | Postgres, mirrored to PostHog as `person.properties.role`. Postgres wins on disagreement, per `entities.md` section 4. |
| Roughly how many there are | 4,100 users across 180 accounts, counted 2026-02-14. |
| What success looks like for them | They update a shipment's status without opening a carrier portal. |
| The metric that tracks that success | `portal_free_updates` in `metrics.md`. |
| What makes them leave | Their carrier is not integrated, so they are back in the portal anyway. |

### EXAMPLE persona: Operations director

| Field | Answer |
|---|---|
| One-line description | Signs the contract. Logs in weekly at most. |
| What they are trying to get done | Show the CEO that on-time delivery is improving. |
| How often they use the product | Weekly, mostly the reporting tab. |
| **How to identify in the data** | `users.role = 'admin' AND users.id = accounts.owner_user_id`. Being an admin alone is not enough, coordinators get promoted to admin. |
| Which source carries that field | Postgres `public.users` and `public.accounts`. |
| Roughly how many there are | 180, one per account, counted 2026-02-14. |
| What success looks like for them | They open the on-time-delivery report at least once between renewal conversations. |
| The metric that tracks that success | `director_report_opens_per_quarter` in `metrics.md`. |
| What makes them leave | They cannot answer the CEO's question without exporting to a spreadsheet. |

### EXAMPLE persona: Carrier dispatcher

| Field | Answer |
|---|---|
| One-line description | Works at the carrier, not at the customer. Replies to messages, never signs in. |
| What they are trying to get done | Answer a status question in under a minute and get back to work. |
| How often they use the product | Only when a coordinator messages them. |
| **How to identify in the data** | `NOT IDENTIFIABLE`. Dispatchers reply by email through a mail gateway. No user row is created, and the reply lands as `events.properties.channel = 'email_gateway'` with no identity attached. What would fix it: a `carrier_contact_id` on the inbound message row. That is a product change, not an analysis change. |
| Which source carries that field | None today. |
| Roughly how many there are | Unknown. Roughly 3,000 distinct reply-to addresses in 2025, which is an upper bound and is not the same as a person count. |
| What success looks like for them | They never have to sign in to anything. |
| The metric that tracks that success | None. Do not report a dispatcher metric until the id exists. |
| What makes them leave | Not applicable, they were never a user. |

---

## Segments that are not personas

Plan tier, company size, and signup channel are segments, not personas. Put them in
`metrics.md` as cuts. A persona is a job someone is doing. If the only thing that
separates two of your personas is how much they pay, they are one persona on two
plans.
