## Android Changes

- After updating the Android app, run './dandroid/debug.sh build` to test the new build.

## Convex Changes

- use `pnpm` instead of `npm` or `yarn` for package management.
- install dependencies with `pnpm install`.
- run the project with `pnpm dlx convex dev` to check that everything is working correctly.

## Issue Tracking

This project uses **bd (beads)** for issue tracking.
Run `bd prime` for workflow context.

**Quick reference:**

- `bd ready` - Find unblocked work
- `bd create "Title" --type task --priority 2` - Create issue
- `bd close <id>` - Complete work
- `bd sync` - Sync with git (run at session end)

Example of a bead issue id: 'Clipsync-3tw'. If the message contains a bead id, reference the issue details and begin working.
