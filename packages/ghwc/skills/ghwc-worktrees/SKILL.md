---
name: ghwc-worktrees
description: "Clone GitHub repos on this machine with ghwc: canonical owner/repo casing, shared bare clone, branch-named sibling worktrees under ~/Projects."
---

# ghwc Worktrees

Use `ghwc` whenever cloning an existing GitHub repo or adding a worktree.

Layout:

```text
~/Projects/gh/CanonicalOwner/canonical-repo/
├── .bare/
├── main/
└── feature-branch/
```

Rules:

- Use GitHub's canonical upstream `Owner/repo` casing, not the casing typed by the user.
- Worktree directories are named after the branch.
- `ghwc REPO` creates/checks out the default branch worktree.
- `ghwc REPO branch-name` checks out that existing branch into `./branch-name`.
- For a new branch: `ghwc REPO branch-name -b branch-name`.
- For reset/recreate: `ghwc REPO branch-name -B branch-name`.
- `GHWC_ROOT` overrides `~/Projects`.

Examples:

```bash
ghwc ToxicPine/offloads
ghwc ToxicPine/offloads main
ghwc ToxicPine/offloads feature-x -b feature-x
ghwc ToxicPine/offloads opinionated
```

Report the resulting local path after running it.
