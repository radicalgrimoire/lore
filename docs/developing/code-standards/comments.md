# Lore commenting and documentation standards

This document defines the standard patterns for code documentation across the Lore codebase.

## Function documentation

Each function should have clear documentation in Rust doc format outlining what the function does,
what the expected preconditions are and what the meaning, expectations and limits are for each argument.

If the function is complex enough to warrant a code example it should be in correct code and pass the Rust
doc test, not ignored.

## Code comments best practices

- Code comments shouldn't be used to group functions into sections.
- Code comments shouldn't be used for code sections that are self-explanatory from the code itself.
- Code comments can be used to document complex logic and dependencies between different code sections.
