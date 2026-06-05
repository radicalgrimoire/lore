# Code standards

Coding conventions governing how Lore source is written.

## What this folder is

Per-language, per-area conventions for error handling, logging, task spawning, testing, comments, and similar concerns. Each page is a Code-Standard doc — imperative rules paired with rationale, code examples, and reference tables.

## The standards

- [Error handling](errors.md). Typed `thiserror` enums, the public `LoreError` interface, logging extension traits, and the no-`unwrap` rule.
- [Logging](logging.md). `tracing` for server and tool code, Lore macros for library code, and when to use each log level.
- [Task spawning](tasks.md). The `lore_spawn!` macros that keep `LORE_CONTEXT` propagating across async and blocking tasks.
- [Testing](testing.md). Unit, async, and smoke test patterns, with the test-independence rules that keep them isolated.
- [Comments and documentation](comments.md). Rust doc-comment expectations and when a code comment earns its place.

## Suggested starting points

- **Writing a new Code Standard page?** Start at the [doc-standards walkthrough](../doc-standards/writing-a-doc.md).

See [docs/README.md](../README.md) for the full docs structure.
