# Entities

**Status: TEMPLATE. Nothing below is a fact about your product. Fill it in.**

Every row marked `EXAMPLE` describes a fictional company called **Nimbus Freight**, a
made-up B2B logistics SaaS with three levels: an account, its depots, and the users at
each depot. Nimbus Freight does not exist. Delete every EXAMPLE row once you have
written your own. An agent that reads an EXAMPLE row as fact will produce a
confidently wrong number.

This file is the one read that is never optional. `AGENTS.md` tells the agent to
read it before any query, every time. If a section here is still `TODO`, the agent
does not invent a rule. It names what is undefined, says what it assumed instead,
puts both in the output, and answers. An answer built on a stated assumption is
usable. One built on a silent guess is not.

---

## 1. Grain

**List every level you count, biggest first. Then say which one "a customer" means.**

The grain is the thing you count one of. Most businesses have more than one level. A
plain SaaS has accounts, and users inside them. A franchise has a brand, its
locations, and the staff at each location. Write one row per level, top to bottom.
Two rows is the common case. One row is fine.

Counting at the wrong level does not throw an error. It silently returns a number
that is off by the average number of lower-level rows per higher-level one. Skip two
levels and the two averages multiply.

- **Level**: a plain, singular name. Reports use it to label every count.
- **Id column**: the column that names one of it.
- **Parent level**: the level directly above. `none` for the top row.
- **Link to parent**: the column on this level's table that holds the parent's id. If
  a row can have more than one parent, for example staff who work at two locations,
  name the link table and say so. If a table holds ids for two levels above it, say
  which one wins when they disagree.
- **Count from a lower table**: the exact aggregation that counts this level from a
  table one or more levels below it.

| Level | Id column | Where it lives | Parent level | Link to parent | Count from a lower table |
|---|---|---|---|---|---|
| `TODO` | `TODO` | `TODO: source and table` | none | none | `TODO: COUNT(DISTINCT <id>)` |
| `TODO` | `TODO` | `TODO: source and table` | `TODO` | `TODO` | `TODO: COUNT(DISTINCT <id>)` |

Add or delete rows until the table matches your business.

| Field | Your answer |
|---|---|
| "A customer" means one | `TODO: one level from the table above` |
| Other levels are allowed when | `TODO: name the cases, or write "never"` |

*EXAMPLE (fictional Nimbus Freight):*

| Level | Id column | Where it lives | Parent level | Link to parent | Count from a lower table |
|---|---|---|---|---|---|
| account | `accounts.id` | Postgres `public.accounts` | none | none | `COUNT(DISTINCT account_id)`, never `COUNT(*)` on a depot or user table |
| depot | `depots.id` | Postgres `public.depots` | account | `depots.account_id` | `COUNT(DISTINCT depot_id)` |
| user | `users.id` | Postgres `public.users` | depot | `users.depot_id`. Empty for head-office admins, about 9% of users. They link to their account through `users.account_id`, which wins if the two paths disagree. | `COUNT(DISTINCT user_id)` |

| Field | Answer |
|---|---|
| "A customer" means one | Account. Nimbus sells one contract per shipping company. |
| Other levels are allowed when | Depot for regional rollout questions. User for seat adoption and feature usage. The report names the level in its Filters section. |

**Why this matters, EXAMPLE figures:** a 40-seat account counted at the user level
contributes 40 to a number a PM will read as 40 customers. A Nimbus account averages
3 depots and a depot 4 users, so a user count read as a customer count is off by
about 12x, and a depot count by about 3x.

### More than one hierarchy

Most businesses skip this. If yours does, write `Not applicable. One hierarchy.`

Fill it only when two different kinds of customer share the same tables, for example
teams and solo individuals. Do not answer "both". Name each hierarchy, say which
levels from the table above it uses, and write a rule that puts every row in exactly
one. Then say which hierarchy each metric in `metrics.md` uses.

| Field | Your answer |
|---|---|
| Hierarchies, by name, with the levels each uses | `TODO` |
| Rule that assigns a row to each one | `TODO: one literal predicate per hierarchy` |
| Rows matching no rule | `TODO: how to treat them, and roughly how many there are` |
| Rows matching more than one rule | `TODO: which rule wins` |
| Rows that move from one hierarchy to another | `TODO: what happens on the date they move` |

*EXAMPLE:* `team` uses all three levels, for rows where
`accounts.plan_type IN ('team','enterprise')`. `solo` uses only the user level, for
rows where `accounts.plan_type = 'solo'`. A solo account has one user and no depot. A
solo user who later joins a team account moves hierarchy on the date of the join, and
longitudinal metrics treat the two periods as separate entities.

---

## 2. Active

**"Active" is not a word. It is a window plus a qualifying action. Write both.**

| Field | Your answer |
|---|---|
| Window | `TODO: exact number of days, e.g. 28` |
| Window anchor | `TODO: rolling from the query date, or calendar month` |
| Timezone the window is evaluated in | `TODO: e.g. UTC` |
| Qualifying action, as an event or column filter | `TODO` |
| Actions that explicitly do NOT qualify | `TODO` |
| Level the qualifying action happens at | `TODO: a level from section 1, usually the lowest` |

### Rolling activity up

Activity happens at one level, usually the person. Every level above it needs a rule
for when it counts as active. Write one row per step, from the level the action
happens at up to the customer level. Do not skip a step. If a location sits between
the person and the company, say how people make a location active, then how
locations make the company active. "At least 3 active people per location" and "at
least 3 active people per company" are different numbers.

Only rows that survive the exclusions in section 3 count toward a parent. One active
internal user does not make a customer account active.

| From level | To level | The higher level is active when |
|---|---|---|
| `TODO` | `TODO` | `TODO: at least one active <lower level>, or a threshold` |

With one level, write `Not applicable. One level.`

*EXAMPLE (fictional Nimbus Freight):*

| Field | Answer |
|---|---|
| Window | 28 days |
| Window anchor | Rolling, ending at the query's end date inclusive |
| Timezone | UTC |
| Qualifying action | PostHog event `shipment_created` or `shipment_status_updated` |
| Actions that do NOT qualify | `user_signed_in`, `page_viewed`, `settings_opened`, any event where `$lib = 'posthog-python'` (backfills) |
| Level the action happens at | User |

| From level | To level | The higher level is active when |
|---|---|---|
| user | depot | At least one active, non-excluded user in the depot |
| depot | account | At least one active, non-excluded depot in the account. A head-office admin with no depot counts toward the account directly. |

**Why this matters, EXAMPLE figures:** at Nimbus, "active = signed in" returns roughly
2.4x the count that "active = created or updated a shipment" returns. Both are
defensible. Only one can be in a report, and the report has to say which.

### Named variants

If more than one definition of active is in real use, name each one and say where it
is allowed. Do not let the agent pick.

| Variant name | Definition | Where it may be used | Where it may not |
|---|---|---|---|
| `TODO` | `TODO` | `TODO` | `TODO` |

*EXAMPLE:* `active_28d_core` is the definition above and is the only one allowed in
reports. `active_login_30d` exists because the billing dashboard uses it. It may be
quoted only when comparing against that dashboard, and the report must label it.

---

## 3. Exclusions

**Each rule must be mechanically applicable. A rule the agent cannot turn into a
`WHERE` clause is not a rule, it is a wish.**

C-10 requires every analysis to apply these and to state which ones it applied.

Fill one row per rule. `Level` is the level whose rows the rule removes, from section
1, or `event` for a rule that removes individual events rather than entities. `Rule`
is the literal predicate. `Source` says which table or event property carries the
field. `Confidence` is `confirmed` or `unconfirmed`. The agent applies confirmed rules
automatically and stops to ask about unconfirmed ones.

Rules are written to KEEP wanted rows, so they `AND` together into one `WHERE`
clause. Wrap any rule containing `OR` in parentheses. Without them,
`a AND x IS NULL OR x > d` reads as `(a AND x IS NULL) OR x > d`, which brings back
every row the other rules removed, with no error.

| # | Category | Level | Rule (literal predicate, written to KEEP wanted rows) | Source | Confidence | Notes |
|---|---|---|---|---|---|---|
| E-1 | Internal by email domain | `TODO` | `TODO` | `TODO` | `TODO` | `TODO` |
| E-2 | Internal by account id list | `TODO` | `TODO` | `TODO` | `TODO` | `TODO` |
| E-3 | Internal by flag | `TODO` | `TODO` | `TODO` | `TODO` | `TODO` |
| E-4 | Demo accounts | `TODO` | `TODO` | `TODO` | `TODO` | `TODO` |
| E-5 | Sandbox and staging | `TODO` | `TODO` | `TODO` | `TODO` | `TODO` |
| E-6 | Test accounts created by real users | `TODO` | `TODO` | `TODO` | `TODO` | `TODO` |
| E-7 | Bots and automated traffic | `TODO` | `TODO` | `TODO` | `TODO` | `TODO` |
| E-8 | Churned entities | `TODO` | `TODO` | `TODO` | `TODO` | `TODO` |
| E-9 | Deleted entities | `TODO` | `TODO` | `TODO` | `TODO` | `TODO` |
| E-10 | Free vs paid | `TODO` | `TODO` | `TODO` | `TODO` | `TODO` |
| E-11 | Anything else, at any level | `TODO` | `TODO` | `TODO` | `TODO` | `TODO` |

*EXAMPLE (fictional Nimbus Freight):*

| # | Category | Level | Rule (literal predicate, written to KEEP wanted rows) | Source | Confidence | Notes |
|---|---|---|---|---|---|---|
| E-1 | Internal by email domain | user | `(users.email IS NULL OR (users.email NOT ILIKE '%@nimbusfreight.example' AND users.email NOT ILIKE '%@nimbus-qa.example'))` | Postgres `public.users` | confirmed | Name the column in every clause. `AND NOT ILIKE '...'` on its own is not valid SQL, and rules here are pasted verbatim. The `IS NULL` half keeps a user with no email recorded. A third domain, `nimbusfreight.test`, was retired in 2025 and still has 6 rows. |
| E-2 | Internal by account id list | account | `(accounts.id IS NULL OR accounts.id NOT IN (1, 2, 7, 41, 903))` | Postgres `public.accounts` | confirmed | Founder-owned accounts on real customer domains, so E-1 misses them. `accounts.id` is never empty in `accounts` itself. The `IS NULL` half matters when this rule is applied to users through a `LEFT JOIN`: a user with no account has an empty `accounts.id`, and a bare `NOT IN` drops them. |
| E-3 | Internal by flag | account | `accounts.is_internal IS NOT TRUE` | Postgres `public.accounts` | confirmed | Nullable. `IS NOT TRUE` and not `= FALSE`, because NULL means "never reviewed". |
| E-4 | Demo accounts | account | `accounts.account_type IS DISTINCT FROM 'demo'` | Postgres `public.accounts` | confirmed | `IS DISTINCT FROM` and not `<>`. A blank `account_type` is not a demo account, but `<>` drops it silently. Sales creates these per prospect, roughly 300 live at any time. |
| E-5 | Sandbox and staging | event | `events.properties.environment = 'production'` | PostHog | confirmed | Staging writes to the same project. Property is missing on events before 2025-03-01, so treat missing as non-production before that date. |
| E-6 | Test accounts created by real users | account | `(accounts.name IS NULL OR accounts.name !~* '^(test\|asdf\|delete me\|zzz)')` | Postgres `public.accounts` | unconfirmed | The `IS NULL` half matters: an unnamed account is not a test account, but the bare regex drops it. Heuristic on a free-text field, so report both numbers when it moves the answer. |
| E-7 | Bots and automated traffic | event | `(events.properties.$lib IS NULL OR events.properties.$lib NOT IN ('posthog-python','posthog-node')) AND (events.properties.$user_agent IS NULL OR events.properties.$user_agent !~* 'bot\|crawler\|spider\|headless')` | PostHog | confirmed | Written as one pasteable predicate. `NOT IN` drops rows where the property is missing, which is most of them, so the `IS NULL` halves are load-bearing. Server-side libs here are backfills and integration tests, not humans. |
| E-8 | Churned entities | account | `(accounts.churned_at IS NULL OR accounts.churned_at > <window_start>)` | Postgres `public.accounts` | confirmed | Do not drop churned accounts from historical windows. They were real then. `<window_start>` and not `<window_end>`: an account that churned mid-window was a customer for part of it, and comparing against `<window_end>` deletes exactly the rows this note says to keep. Parenthesized because it contains `OR`. |
| E-9 | Deleted entities | account | `(accounts.deleted_at IS NULL)` for current-state questions. For historical windows use `(accounts.deleted_at IS NULL OR accounts.deleted_at >= <window_start>)`. | Postgres `public.accounts` | confirmed | Point in time. An account alive when the window opened belongs in that window's number, whatever happened later. `<window_start>` and not `<window_end>`: using `window_end` deletes it retroactively from a month it was really there for. Soft delete, so the rows stay and this is a reporting choice, not a data one. |
| E-10 | Free vs paid | account | Not excluded by default. Split by `accounts.plan_type = 'free'` when the question is about revenue or retention. | Postgres `public.accounts` | confirmed | Free accounts are 61% of the account count and 0% of revenue. Mixing them flattens any revenue-adjacent metric. |
| E-11 | Training depots | depot | `depots.is_training IS NOT TRUE` | Postgres `public.depots` | confirmed | Every account gets one practice depot at onboarding. Excludes the depot and its users. Never excludes the account. |

**Why this matters, EXAMPLE figures:** at Nimbus, applying E-1 through E-7 to a signup
count drops it from 12,400 to 9,850. A report that shows only one of those numbers is
hiding a 21% swing.

### Exclusions across levels

Exclusion flows down, never up.

- **Down.** An excluded row excludes every row below it. An excluded company excludes
  its locations and its people. An excluded location excludes its people, and never
  its company. To apply a rule to a level below the rule's own level, `LEFT JOIN` up
  through the links in section 1 and `AND` the rule in. A row whose link to its
  parent is empty is not inside an excluded parent. It stays, because every rule
  keeps an empty value. Count those rows and say how many.
- **Never up.** An excluded row never removes the row above it. An internal person
  does not exclude their company. An excluded event does not exclude the person who
  fired it. A lower-level rule changes a higher-level number only through the
  roll-up in section 2: the excluded row does not count toward its parent being
  active. When you count a higher level, do not join down to apply a lower-level
  rule. That join multiplies rows, and "keep the company if any of its people pass"
  and "keep it only if all of them pass" give different numbers with no error. In
  the report, list such a rule as not applicable at this level.
- **To drop a whole company because of who is in it,** write a rule at the company
  level, for example a flag, an id list, or the owner's email domain. Do not get it
  by applying a person rule to a company count.

### How to state exclusions in a report

Every report lists the rule ids it applied, by id, in the `Exclusions applied`
section. A rule that cannot touch the query, because its level is below the level
counted or its source was not queried, is listed as not applicable, with the reason.
If it applied none, it says why in a sentence. "None" on its own gets flagged by
`evals/check-output.sh`.

### Writing a rule against a column that can be empty

If a column can be empty, write the rule so an empty value is KEPT, not silently
dropped. This is the single most common way a count comes out quietly too low.

`account_type <> 'demo'` looks like it means "not a demo account". For a row where
`account_type` is empty, the database cannot say true or false, so it answers
"unknown", and unknown rows are dropped. An account with no type recorded is not a
demo account, but it disappears from the number anyway, with no error.

Write `IS DISTINCT FROM 'demo'`, or `(account_type <> 'demo' OR account_type IS NULL)`.
Same for `NOT IN (...)` and for a regex: add the `IS NULL` half.

A column that is never empty in its own table can still be empty after a `LEFT JOIN`
from a lower level. That is why E-2 above has an `IS NULL` half on a primary key.

When empty values are a meaningful share of the rows, say how many in the report.
"1,118 accounts, of which 34 had no account_type recorded" is honest. Quietly
counting 1,084 is not.

### When a past number changes

Numbers are point in time. If a report went out in August saying 1,240 accounts,
someone read that number and made a decision on it. August stays 1,240.

So historical windows count what was alive during the window, whatever happened
afterwards. That is why E-8 and E-9 compare against `<window_start>` and not
`<window_end>`. Comparing against `window_end` deletes an entity retroactively from
a month it really was there for.

When a number you are reporting now differs from a number previously reported for
the same period, do not just show the new one. Show both and name the cause:

> August accounts: 1,240 as reported on 2026-09-01, 1,232 as computed today.
> 8 accounts were deleted in September. The August figure of 1,240 stands.
> The 8 leave in September's number, not August's.

A silently restated history is worse than a wrong number, because nobody knows to
go back and check what they decided on.

### When a case has no rule

Do not invent one. Report the case, the row count it affects, say which way you
treated it and why, and carry on. A new internal email domain is the common version
of this, and the fix is a row in the table above, not a guess in a query.

---

## 4. Identity and joins

C-11 forbids inferring a join. A join runs only on an identifier listed as
`confirmed` here, with its cardinality and precedence stated.

Each identifier belongs to one level from section 1. A join confirmed at one level
confirms nothing at another: `account_id` joining cleanly says nothing about
`user_id`. The links in section 1 are joins too. A link inside one source, backed by
a foreign key, needs no row here. A link that crosses sources does.

### Confirmed identifiers

| Identifier | Level | Links which sources | Cardinality | Source of truth | Precedence when they disagree | Verified how, and when |
|---|---|---|---|---|---|---|
| `TODO` | `TODO` | `TODO` | `TODO` | `TODO` | `TODO` | `TODO` |

*EXAMPLE (fictional Nimbus Freight):*

| Identifier | Level | Links which sources | Cardinality | Source of truth | Precedence when they disagree | Verified how, and when |
|---|---|---|---|---|---|---|
| `account_id` | account | Postgres `accounts.id` to PostHog `events.properties.account_id` | 1 to many. One account, many events. | Postgres | Postgres wins. PostHog copies the value at event time and does not update it after an account merge. | Sampled 500 PostHog `account_id` values against Postgres on 2026-02-14. 3 orphans, all from a merged account. |
| `user_id` | user | Postgres `users.id` to PostHog `distinct_id` | 1 to many. One user can have several `distinct_id` values across devices before identify fires. | Postgres | Postgres wins. Resolve `distinct_id` to `user_id` through PostHog's person merge, never by string equality. | Same sample, same date. 11% of pre-identify events have no resolvable `user_id`. Those are dropped and the drop is stated. |
| `stripe_customer_id` | account | Postgres `accounts.stripe_customer_id` to Stripe `customer.id` | 1 to 1 | Stripe | Stripe wins on plan and amount. Postgres wins on account name and owner. | Reconciled 2026-01-30. 4 Postgres rows point at deleted Stripe customers. |

**Why this matters, EXAMPLE figures:** joining PostHog `distinct_id` directly to
Postgres `users.id` looks like it works, returns rows, and quietly drops every user
who used two devices.

### Unconfirmed, do not join

These look joinable. They are not. Any analysis that needs one of them stops and says
what it could not join.

| Identifier pair | Why it is not confirmed | What to do instead |
|---|---|---|
| `TODO` | `TODO` | `TODO` |

*EXAMPLE (fictional Nimbus Freight):*

| Identifier pair | Why it is not confirmed | What to do instead |
|---|---|---|
| PostHog `events.properties.depot_id` to Postgres `depots.id` | The property was added on 2026-03-01 and has not been sampled. | Answer depot questions from Postgres alone, or at account level through the confirmed `account_id`, and say the level moved. |
| `users.email` to Zendesk `requester.email` | Users file tickets from personal addresses. A 2026-01 check matched 58% of tickets. The unmatched 42% are not random, they skew to enterprise. | Report ticket volume unjoined, at Zendesk grain, and say it cannot be attributed to accounts. |
| `accounts.name` to Salesforce `Account.Name` | Free text on both sides. Casing, suffixes, and "Inc" vs "Inc." differ. | Ask the user for a mapping table. Do not fuzzy match. |
| PostHog `$session_id` to Postgres session rows | Different definitions of a session. PostHog uses 30 minutes of inactivity, the app uses a 14-day token. | Pick one and say which. Never treat them as the same object. |

---

## 5. Lifecycle edge cases

These break longitudinal metrics quietly. Cohort counts drift, retention curves bend,
and nothing errors. Merge, split and move can happen at any level in section 1. Write
the rule once if it is the same everywhere, or name the level it covers.

| Event | Your rule |
|---|---|
| Merge: two rows at the same level become one, such as two accounts or two locations | `TODO: which id survives, what happens to the other one's history, whether the cohort date is the older or the newer` |
| Split: one row becomes two, at any level | `TODO` |
| Move: a row changes parent, such as a person moving to another location | `TODO: does past activity stay with the old parent or follow the row` |
| Plan change: upgrade, downgrade, trial to paid | `TODO: does the entity keep its original cohort date` |
| Re-signup: a churned entity comes back | `TODO: new entity or the same one, and the reactivation window` |
| Row added or removed below the customer level, such as a seat | `TODO` |
| Hard delete or a GDPR erasure request | `TODO: how history is treated after the row is gone` |

*EXAMPLE (fictional Nimbus Freight):*

| Event | Rule |
|---|---|
| Merge | Accounts: the surviving `account_id` is the one with the earlier `created_at`. The merged account's events keep the old `account_id` in PostHog forever, so any longitudinal query maps through `account_merges(old_id, new_id, merged_at)` in Postgres. The cohort date is the surviving account's, not the merge date. Depots: same rule, through `depot_merges`. |
| Split | Rare, 3 cases total, all accounts. The new account is a new entity with a new cohort date. The original keeps its history. Both are listed in `account_splits`. |
| Move | A user who moves depot keeps their own cohort date. Their past activity stays with the depot it happened in, so depot history uses the depot on the row or event at the time, not today's `users.depot_id`. |
| Plan change | The entity keeps its original cohort date. Plan is a point-in-time attribute, so any plan filter must state whether it is the plan at window start, window end, or the plan today. Default is plan at window end. |
| Re-signup | Same `account_id` if it returns within 90 days of `churned_at`, and it does not enter a new cohort. After 90 days it is a new entity with a new cohort date. This 90-day line is a decision, not a fact, and it is the reason two retention numbers ever disagree. |
| Row added or removed below the customer level | No effect on the account count. At the user level the user's cohort date is their own `created_at`, not the account's. |
| Hard delete or GDPR erasure | The row is gone and the history is not recoverable. Aggregates computed before the erasure are not restated. Any window covering an erasure states the count of erased entities from `erasure_log`. |

**Why this matters, EXAMPLE figures:** treating a 100-day re-signup as the same
entity turns a new customer into a retained one, and quietly inflates every retention
cohort it lands in.

---

## 6. Change log

Every edit to this file changes past numbers. Record it.

| Date | Section | What changed | Reports affected |
|---|---|---|---|
| `TODO` | `TODO` | `TODO` | `TODO` |

*EXAMPLE:* `2026-02-14 | Exclusions | Added E-2, five founder-owned accounts on customer
domains | 2026-01-20-signup-trend.md understated the exclusion by roughly 400 signups.`
