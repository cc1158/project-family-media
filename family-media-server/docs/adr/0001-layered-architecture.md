# ADR 0001: Layered Architecture

## Status

Accepted

## Context

The service starts as a lightweight NAS media catalog for Apple TV, but planned iterations include SQLite indexing, thumbnails, metadata extraction, and optional transcoding. A flat package layout would make the MVP fast to write, but it would make later replacements and background workflows harder to isolate.

## Decision

Use a layered architecture with explicit dependency direction:

```text
cmd -> bootstrap -> interfaces -> application -> domain
                 -> infrastructure -> domain
                 -> platform
```

Rules:

- `domain` contains business models and interfaces only.
- `application` owns use cases and depends on domain interfaces.
- `infrastructure` implements domain/application interfaces.
- `interfaces` owns HTTP and future external entrypoints.
- `platform` owns cross-cutting runtime concerns such as config and logging.
- `bootstrap` is the composition root.

## Consequences

- MVP has a few more packages than a single-file service.
- Future SQLite, thumbnail, transcoding, and background scan implementations can be added without rewriting HTTP handlers or domain models.
- Tests can target use cases with fake repositories and infrastructure adapters independently.

