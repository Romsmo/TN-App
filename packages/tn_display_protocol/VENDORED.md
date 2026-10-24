# tn_display_protocol (vendored)

A copy of `protocol/dart/` of the display project (`Romsmo/TN-DSP`, a private repository of the same owner), taken at the tag
`protocol-v1.0.0`, commit `3e108fc05b540d012ceec5f17c0efec61ffd0c81` (2026-10-24), together with the contract files its tests read
(`docs/contract/vectors/`, `sign-rules.json`, the manifest schema and example, now under `contract/`). Licence: MIT (see `LICENSE`),
compatible with this project's Apache 2.0.

Changed from the original: only the paths in `test/*.dart` (`../../docs/contract` -> `contract`). Nothing else. To update it, copy the
files again from a new `protocol-v*` tag and re-run the tests; never edit the copy by hand.
