# Repository guidance

- Prefer `NPINS_OVERRIDE_offloads="$PWD"` when evaluating local changes against the pinned
  `offloads` source; do not rewrite the pin before merge.
- Run `npins` only from `nixpkgs-unstable`, for example:
  `nix shell github:NixOS/nixpkgs/nixpkgs-unstable#npins -c npins ...`.
