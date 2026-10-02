# Current task

Your workspace state. The agent reads this at the start of a session and keeps it
current. `log.md` has the history. Both stay on this machine: they are gitignored.

---

## First run

**Agents: check this before answering a product question.** If
`knowledge-base/entities.md` still contains `TODO` in sections 1 to 4, this workspace has
never been set up. Work on the repo itself does not trigger this. A question about the
user's product does.

1. Before answering, tell the user in a few plain sentences what this is and what setup
   takes. Adapt this, do not read it out:

   > This workspace answers product questions from your data, and every number comes with
   > the query behind it. Right now it does not know your definitions, like what counts as
   > an active customer or which accounts are your own team, so any number would rest on
   > my guesses. Setup is about eight questions in plain words and takes 5 to 10 minutes.
   > You approve the result by running one command. Want to do it now?

2. On yes, run `skills/setup/onboard`. When it finishes, answer the question they asked.
3. On no, answer anyway on stated assumptions, as `AGENTS.md` already requires. Offer the
   setup once more at the end of that answer, and then not again this session.

When setup is done, `skills/setup/onboard` replaces this whole section with one line.

---

## Plan

None yet.

## Status

Nothing analyzed yet.

## Blockers

None.

## Next action

Ask a question about your product.
