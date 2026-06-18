# Conventions

## Naming

- Use `snake_case` for tables, columns, and standalone routines.
- Use uppercase for Oracle keywords in SQL scripts.
- Prefix script files with ordered numbers (for example: `001_`, `002_`).

## Script Rules

- Make scripts idempotent when possible.
- Add a header comment with purpose and owner for non-trivial scripts.
- Keep one logical change per script.

## PL/SQL Guidelines

- Keep package specs and bodies together by feature.
- Favor explicit exception handling for integration-facing routines.
- Include basic usage examples in comments for public package procedures/functions.

## Environment Promotion

- Author first in `schemas/dev`.
- Validate in `schemas/test` before copying to `schemas/prod`.
- Track promotion notes in `migrations`.
