# Oracle Projects Workspace

This workspace is structured for Oracle database development across SQL, PL/SQL, schema environments, and APEX exports.

## Folder Structure

- `sql/scripts`: ordered SQL scripts for setup and data operations
- `migrations`: migration artifacts and execution notes
- `plsql/packages`: package specs and bodies
- `plsql/procedures`: standalone procedures
- `plsql/functions`: standalone functions
- `schemas/dev`, `schemas/test`, `schemas/prod`: environment-specific schema assets
- `apex/exports`: APEX exports and related files
- `tests`: SQL and PL/SQL test assets
- `data`: seed and reference datasets
- `docs`: conventions and process docs

## Getting Started

1. Save Oracle connection profiles (for SQLcl):
   - `conn -save dev -savepwd user/password@host:1521/service`
2. Place DDL and bootstrap statements in `sql/scripts`.
3. Start with `sql/scripts/001_init.sql` and execute in your target environment.
4. Keep environment-specific settings under the matching `schemas/*` folder.

## Suggested Workflow

1. Draft object definitions in `plsql/*` or `schemas/dev`.
2. Add corresponding migration notes in `migrations`.
3. Validate behavior with scripts in `tests`.
4. Promote changes from `dev` -> `test` -> `prod` folders.

## VS Code Notes

Recommended extensions are listed in `.vscode/extensions.json`.
Editor defaults for SQL and markdown are in `.vscode/settings.json`.

## Compliance Notes

- Internal AI provenance note: [docs/ai-provenance-note.md](docs/ai-provenance-note.md)
