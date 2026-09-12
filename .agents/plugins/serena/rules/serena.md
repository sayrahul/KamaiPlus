# Serena Symbolic Intelligence Guidelines

1. **Symbol-First Navigation**: Whenever inspecting large models, services, or UI components, prefer semantic symbol discovery (`find_symbol`, `find_referencing_symbols`, `find_declaration`) over raw text/regex greps to locate exact function, class, and method definitions without false positives.
2. **Safe Refactoring**: When renaming or altering public APIs, interfaces, or database models, use semantic symbol tools to ensure all calling locations across the project are updated consistently.
3. **Preserve Integrity**: Do not perform blind string replacements when symbol-aware updates are safer.
