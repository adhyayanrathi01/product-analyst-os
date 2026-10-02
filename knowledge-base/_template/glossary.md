# Glossary

**Status: TEMPLATE. Nothing below is a fact about your product. Fill it in.**

Every row marked `EXAMPLE` describes a fictional company called **Nimbus Freight**.
Nimbus Freight does not exist. Delete the examples once you have written your own.

Three kinds of term belong here. The third one causes the most damage.

1. **Product nouns.** Objects in your product an outsider would not know.
2. **Internal shorthand.** Words used in Slack that appear in no document.
3. **Words whose everyday meaning is not the meaning here.** These are dangerous
   because nobody asks. The reader thinks they already know.

Metric names live in `metrics.md`. Entity rules live in `entities.md`. Do not restate
them here. Link instead.

---

## Product nouns

| Term | What it means here | Where it shows up in the data |
|---|---|---|
| `TODO` | `TODO` | `TODO` |

*EXAMPLE:*

| Term | What it means here | Where it shows up in the data |
|---|---|---|
| Shipment | One freight move from one origin to one destination, under one carrier booking. A truck carrying three customers' goods is three shipments. | `shipments.id`, PostHog `properties.shipment_id` |
| Leg | One segment of a shipment that changes carrier or mode. Most shipments have one leg. | `shipment_legs.id` |
| Connection | A carrier integration an account has authorised. Not a network connection. | `integrations` |
| Board | The main screen. A filtered list of shipments. Users call it "the board", the code calls it `shipment_list`. | `shipment_list_loaded` |

---

## Internal shorthand

| Term | What it means | Where it came from |
|---|---|---|
| `TODO` | `TODO` | `TODO` |

*EXAMPLE:*

| Term | What it means | Where it came from |
|---|---|---|
| The dark hours | The gap between a shipment leaving and its first carrier scan. Usually 4 to 30 hours. | A 2024 support post-mortem. |
| A Tuesday account | An account that only uses Nimbus on the day it books, then goes quiet. Named after a customer who did exactly that. | Sales, roughly 2025. |
| Portal-back | A coordinator who reverts to a carrier's own website. The thing `portal_free_updates` measures the absence of. | Product. |
| P0 | Here it means a customer cannot create a shipment. It does not mean "important". | Eng on-call runbook. |

---

## Words whose everyday meaning differs here

**This is the section that prevents wrong answers.** Fill it even if you fill nothing
else.

| Term | What an outsider assumes | What it actually means here | The mistake this causes |
|---|---|---|---|
| `TODO` | `TODO` | `TODO` | `TODO` |

*EXAMPLE:*

| Term | What an outsider assumes | What it actually means here | The mistake this causes |
|---|---|---|---|
| Customer | A person who pays. | An account, never a person. Nimbus has 180 customers and 4,300 users. | Reporting user counts as customer counts, off by 24x. |
| Active | Signed in. | Created or updated a shipment in 28 days. See `entities.md` section 2. | A 2.4x overcount. |
| Delivered | The goods arrived. | The carrier's API reported a delivery scan. The scan can lag the arrival by a day, or never fire. | Treating a missing scan as a failed delivery. |
| Trial | A free period. | A Team-plan trial. Solo is free forever and is not a trial. | Counting every free account as a trial, which inflates trial-to-paid denominators. |
| Session | One visit. | PostHog's 30-minutes-of-inactivity session, which is not the app's 14-day auth session. Two different objects, same word. | Joining them. `entities.md` section 4 forbids it. |
| Churn | Stopped using it. | The billing cancel date, since 2025-12-02. Not last activity. | Comparing a post-2025-12 churn number to a pre-2025-12 one. |
| Cancelled | The customer cancelled. | Ambiguous. A cancelled *shipment* is a shipment event. A cancelled *account* is churn. The word appears in both tables. | Reading `cancelled_at` from the wrong table. |

---

## Terms we deliberately do not use

Sometimes the fix is to ban a word rather than define it.

| Banned term | Use instead | Why |
|---|---|---|
| `TODO` | `TODO` | `TODO` |

*EXAMPLE:*

| Banned term | Use instead | Why |
|---|---|---|
| User, when you mean account | Account | The two counts differ by 24x. |
| Engagement | The specific metric name | It has meant four different things in four decks. |
| MAU | `active_28d_core` with its window stated | "Monthly" hides whether it is 28 days or a calendar month. |
