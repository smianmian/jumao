# Semantic Repair Codex Execution: SaaS Web Membership

## Scope and reproducibility

This is a new execution comparison for the fixed Semantic Repair sources. It is not the earlier Product Validation execution result.

| Item | Baseline | Semantic Repair |
| --- | --- | --- |
| Runtime source commit | `3cc08cb4461f364f9e99c8eea9f4c70a1e1a3567` | `277f16d9e42d4a52e8f3b4cffd5617cff6ff0d64` |
| `src/core/planning-runtime.js` SHA-256 | `4823c5657ece9c46c83a90f9963066f68b559d29c9eb9aedb23f83b55fd0686f` | `13313da367a2fce6ef28c11da19691be5c9f8a956959f02517c0f1b595ee5159` |
| Generated plan run | `20260725153816047-841b6e95` | `20260725153816123-c99f1956` |
| First-stage task entries | 9 | 10 |
| Native `priorityTasks` | 6 | 8 |

The two runtime trees were created with `git archive <fixed-commit>` under the temporary root `/tmp/jumao-semantic-repair-saas.niuEnp`; the source workspace was not used as either runtime. For each side, `benchmark/cases.js` materialized the same `saas-web-membership.files` into a newly initialized temporary Git project before planning.

Input equality was checked before either plan was generated. The input fingerprint is `68af646aa8b4c6544fcfdcca5b1bfb38fd9e5fd389baa0076e9673b1fde89309`, calculated as the SHA-256 of the sorted list of SHA-256/path pairs for the six materialized files. The two sorted lists were byte-for-byte identical:

- `.jumao/intake-answers.json`
- `package.json`
- `product/release-boundaries.md`
- `src/access.js`
- `src/catalog.js`
- `test/catalog.test.js`

Each generated `.jumao/` and `tasks/` plan was committed to its own temporary repository *before* Codex ran. Codex was told not to commit. Thus the final Git status measures only execution changes, rather than plan generation output.

## Identical Codex setup

Both runs used `codex-cli 0.141.0` with the same loaded provider configuration and explicit execution flags:

```sh
codex exec --ephemeral -m gpt-5.6-terra \
  -c 'model_reasoning_effort="high"' \
  -s danger-full-access -C <temporary-project> \
  -o <temporary-output> '<exact prompt below>'
```

Both Codex session headers recorded: model `gpt-5.6-terra`, provider `cliproxyapi`, approval `never`, sandbox `danger-full-access`, and reasoning effort `high`.

The prompt was identical, with no appended plan interpretation or follow-up:

> Implement only the requested change using the supplied Jumao plan. Preserve all stated constraints. Work in this temporary project only. Do not commit. Run the project tests and report commands, modified files, unmet plan items, invalid changes, constraints violations, human interventions, and rework loops.

## Final execution evidence

| Measure | Baseline | Semantic Repair |
| --- | --- | --- |
| Core goal completion | Partial | Partial |
| Modified product files | 3: `src/access.js`, `test/catalog.test.js`, `product/membership-phase-one.md` | 2: `src/access.js`, `test/catalog.test.js` |
| Independently evidenced execution outcomes | 3: local access model, local-data inventory, regression tests | 2: local access model, regression tests |
| Actual executed priority-task count | Not safely derivable from a file diff; the six planned priorities mix implementation, inspection, and governance work | Not safely derivable from a file diff; the eight planned priorities mix implementation, inspection, and governance work |
| `npm test` after Codex had finished | Pass: 2/2 | Pass: 3/3 |
| Build | No `build` script exists | No `build` script exists |
| Tracked diff check | Pass: no output from `git diff --check` | Pass: no output from `git diff --check` |
| Untracked-file diff check | Pass: `product/membership-phase-one.md` also passed `git diff --no-index --check` | N/A: no untracked product file |
| Commits made by Codex | 0 | 0 |
| Manual intervention after launch | 0 | 0 |
| Evidence of rework | 1 loop | 0 loops |

The count labelled “independently evidenced execution outcomes” is deliberately narrower than a claim that every first-stage plan line was done. It counts only outcomes with a final file/test artifact. In particular, an assertion that a UI was “confirmed absent” or that a scope restriction was respected cannot be counted as a completed code task from the diff alone.

### Baseline outcome

Baseline added a three-value `accessStates` model, a local `.test`-address map, and `signInWithEmail()`. Its tests verify anonymous browsing, a non-member local account, a member local account, and an unknown account. It also added `product/membership-phase-one.md`, documenting the two local fields, their in-memory storage, deletion condition, and production prerequisites.

The Codex transcript proves one rework loop: after the initial successful test run it changed the unknown-email fixture from a `.com` address to `visitor@example.test`, then reran tests. That is a constraint-alignment rework, not a human edit.

### Semantic Repair outcome

Semantic Repair added `loginWithEmail()` using two local `.test` records. It preserves `canBrowseCatalog() === true` and distinguishes invalid input, unknown account, authenticated account, and member account in the return value. Its three tests cover anonymous browsing, the two known local accounts, and invalid/unknown inputs.

It made no local-data inventory document. Its final response explicitly lists the privacy-policy task as unmet; it says no UI or member benefit was added because the fixture has no existing UI/benefit scope.

## Goal quality, omissions, and constraints

The requested capability is “email login and subscription membership while anonymous browsing remains available, using only local fake data.” Both implementations satisfy only the state-model portion. Neither creates a visible webpage login entrypoint nor an observable membership benefit. The fixture has no UI source file, and both plans prohibit inventing unrequested surface area, so this is an execution limitation/omission rather than evidence that either run should add arbitrary UI.

Both final diffs preserve anonymous browsing and use only local `.test` fixtures. The execution transcript's static scan found no URLs, `fetch`, browser storage, passwords, payments, or databases in the changed source/tests. No production release, real payment integration, real credential storage, or commit occurred.

No invalid product-code modification was observed. Baseline's new `product/membership-phase-one.md` is supported by its own first-stage data-inventory tasks and does not overwrite a user document. Semantic Repair's absence of that document leaves its planned data-boundary work without a durable artifact, but is not itself an invalid modification.

There is, however, an unresolved **procedural semantic conflict** on both sides: both plans state “在项目主人确认前，不要修改代码” (do not modify code before owner confirmation). No explicit owner-confirmation artifact was included in the case input. The execution prompt orders implementation, but it is an audit instruction and is not evidence that the product owner confirmed the plan. Baseline's final response calls the prompt confirmation; Semantic Repair says no human intervention. Neither statement resolves the missing case-level confirmation. This comparison must not score either side as fully plan-compliant on that point.

## Interpretation

Semantic Repair did not demonstrate a better real-execution result in this case. It produced more planned items (10 first-stage / 8 priority versus 9 / 6) but fewer final product artifacts (2 versus 3), while both achieved the same partial core goal and passed tests. Repair's extra invalid/unknown-input tests are useful, but they do not compensate for the shared absence of an end-user entrypoint and member benefit, and it left its privacy-policy task explicitly unmet.

This is evidence against treating the repaired plan's structure as proof of superior Codex execution quality. It also exposes that the “owner confirmation before code” instruction remains semantically ambiguous when the requested Codex prompt says to implement.

## Commands used

```sh
# Export fixed, distinct planning sources; no checkout or worktree was made in the source repo.
git archive 3cc08cb4461f364f9e99c8eea9f4c70a1e1a3567 | tar -x -C <baseline-runtime>
git archive 277f16d9e42d4a52e8f3b4cffd5617cff6ff0d64 | tar -x -C <repair-runtime>

# Materialize identical benchmark/cases.js SaaS input, then plan each temporary project.
node <baseline-runtime>/bin/jumao.js plan <baseline-project> --force
node <repair-runtime>/bin/jumao.js plan <repair-project> --force

# Run the same Codex CLI/config/prompt shown above for each temporary project.

# Run only after both Codex sessions completed.
(cd <baseline-project> && npm test)
(cd <repair-project> && npm test)
git -C <baseline-project> diff --check
git -C <repair-project> diff --check
git -C <baseline-project> diff --no-index --check /dev/null product/membership-phase-one.md
```
