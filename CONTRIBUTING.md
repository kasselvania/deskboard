# Contributing to Deskboard

Deskboard is currently a small personal and portfolio project. Contributions should preserve its deliberate scope, calm product behavior, and understandable architecture.

Read `MANIFESTO.md`, `ARCHITECTURE.md`, `ROADMAP.md`, and `AGENTS.md` before proposing or implementing a change.

## Development Principles

- Work in bounded vertical slices.
- Prefer clear code over reusable abstractions that are not yet needed.
- Keep source ownership explicit.
- Add dependencies only for current requirements.
- Treat privacy, failure states, and documentation as part of the feature.
- Do not begin the next roadmap phase inside the current one.

## Branch Workflow

`main` should remain buildable and understandable.

Create a short-lived branch for implementation work. Suggested names:

```text
feat/fixture-board
fix/board-overflow
refactor/contracts-validation
docs/sync-boundaries
chore/ci-node-version
```

Avoid long-running environment branches and broad branches such as `development` or `everything-v1`.

## Commits

Use small, coherent commits. Conventional-style prefixes are preferred:

```text
feat: add fixture board endpoint
fix: prevent overflow at Steam Deck viewport
test: cover invalid board schema
docs: clarify read-only Apple phase
refactor: share temporal contract
chore: configure continuous integration
```

A commit should represent one comprehensible change. Do not combine feature work with unrelated formatting, dependency upgrades, or file moves.

Do not rewrite shared history or force-push `main`.

## Pull Requests

A pull request should describe:

- the slice or problem being addressed;
- the product or architectural assumption being proven;
- what changed;
- what was intentionally left out;
- validation commands and results;
- screenshots or browser-test artifacts when the Board changes;
- any new dependency and why it is necessary.

Keep pull requests small enough to review in one sitting. If the description requires explaining multiple unrelated goals, split the work.

## Quality Gate

Before requesting review, run the repository’s documented checks. Once Phase 1 exists, the expected gate will include:

```text
lint
typecheck
test
browser tests
production build
```

Use the root package scripts rather than undocumented one-off commands. Local checks and CI should run the same underlying tasks.

Do not mark work complete while a required check is failing.

## UI Changes

Changes to the Board must be checked at least at:

- iPad landscape reference viewport: `1366 × 1024`;
- Steam Deck viewport: `1280 × 800`;
- one narrower portrait sanity viewport.

For the two primary viewports, the default Board should not produce document-level vertical scrolling.

UI changes should preserve:

- semantic HTML;
- keyboard access;
- touch-sized controls when controls exist;
- visible focus state;
- reduced-motion support;
- legibility without relying only on color;
- calm empty, stale, loading, and error states.

Do not introduce a component framework or generic dashboard template merely to accelerate styling.

## Tests

Tests should protect observable behavior and architectural boundaries.

Good examples include:

- a Board fixture passes the runtime schema;
- an invalid date-only value is rejected;
- the API returns a contract-valid response;
- capacity limits are deterministic;
- unsupported schema versions fail safely;
- the target viewports have no page-level vertical overflow.

Avoid tests that only mirror internal implementation details.

## Fixtures and Personal Data

All committed data must be synthetic.

Never commit real:

- Calendar events;
- Reminders;
- notes;
- names or contact information;
- addresses or locations;
- recovery, health, household, or employment details;
- exported source snapshots;
- screenshots containing personal information.

When future Apple integration work begins, sanitize exported examples before placing them under `fixtures/`.

## Documentation

Documentation must describe the behavior that actually exists.

Update relevant documents when a change affects:

- architecture;
- source ownership;
- synchronization;
- API contracts;
- run or test commands;
- roadmap status;
- privacy expectations.

Do not quietly change an architectural decision in code and leave the repository documents behind.

## Licensing

No open-source license has been selected yet. Do not add or assume a license without an explicit project-owner decision.
