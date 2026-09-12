---
name: serena
description: "Semantic code retrieval, symbol-level navigation, LSP refactoring, and code intelligence using Serena"
---

# Serena Semantic Code Intelligence

Serena equips Antigravity with IDE-level symbolic awareness and Language Server Protocol (LSP) capabilities for Dart, Flutter, and multi-language projects.

## When to Use Serena Tools
- **Symbol Search & Navigation**: When you need to find where a class, method, function, enum, or variable is defined or used across the entire codebase (`find_symbol`, `find_declaration`, `find_referencing_symbols`).
- **Implementation Lookup**: When you need to find all subclasses or implementors of an interface (`find_implementations`).
- **File Diagnostics**: Checking compilation diagnostics or lint issues on specific files or line ranges (`get_diagnostics_for_file`).
- **Safe Semantic Refactoring**: When renaming symbols or safely editing entire symbol bodies across files without risk of broken references (`rename_symbol`, `replace_symbol_body`, `insert_before_symbol`, `insert_after_symbol`).
- **Persistent Project Memory**: Reading and storing key architectural notes or decisions (`read_memory`, `write_memory`, `list_memories`).

## Key Tools & Usage Patterns
1. `find_symbol`: Search for symbols by name across the codebase or within specific files.
2. `find_referencing_symbols`: Find all call sites or usages of a function/class before modifying or deprecating it.
3. `get_symbols_overview`: Get a clean structural overview of symbols declared in a file.
4. `replace_symbol_body`: Replace a method or class body cleanly at the AST/symbol level.
