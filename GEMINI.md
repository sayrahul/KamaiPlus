<!-- context7 -->
Use Context7 MCP to fetch current documentation whenever the user asks about a library, framework, SDK, API, CLI tool, or cloud service — even well-known ones like React, Next.js, Prisma, Express, Tailwind, Django, or Spring Boot. This includes API syntax, configuration, version migration, library-specific debugging, setup instructions, and CLI tool usage. Use even when you think you know the answer — your training data may not reflect recent changes. Prefer this over web search for library docs.

Do not use for: refactoring, writing scripts from scratch, debugging business logic, code review, or general programming concepts.

## Steps

1. Always start with `resolve-library-id` using the library name and what to look up in the library's documentation, unless the user provides an exact library ID in `/org/project` format
2. Pick the best match (ID format: `/org/project`) by: exact name match, description relevance, code snippet count, source reputation (High/Medium preferred), and benchmark score (higher is better). If results don't look right, try alternate names or queries (e.g., "next.js" not "nextjs", or rephrase the question). Use version-specific IDs when the user mentions a version
3. `query-docs` with the selected library ID and what to look up in the library's documentation (not single words), scoped to a single concept. If the question spans multiple distinct concepts (e.g. routing and auth and caching), make a separate `query-docs` call per concept with the same library ID, unless the question is about how the concepts interact — combined queries dilute ranking and return shallow results for each topic
4. Answer using the fetched docs
<!-- context7 -->

<!-- serena -->
## Serena Code Intelligence & Symbolic Navigation

Use Serena MCP tools for deep semantic code navigation, symbol inspection, and safe refactoring across Dart, Flutter, and multi-language projects:

1. **Symbol Search & Usage Analysis**:
   - Use `find_symbol`, `find_declaration`, and `find_referencing_symbols` to locate exact definitions, call-sites, and usages instead of brittle plain-text search across large files.
   - Use `find_implementations` to inspect class hierarchies, polymorphic implementations, and interface contracts.
2. **Safe Structural Refactoring**:
   - Use `rename_symbol` and `replace_symbol_body` when modifying core entities, methods, or database schema models to guarantee zero broken references across other screens and services.
3. **Diagnostics & Code Health**:
   - Use `get_diagnostics_for_file` to inspect compile errors, type mismatches, and linter warnings with symbol precision.
4. **Persistent Project Memory**:
   - Use `read_memory` and `write_memory` to retain architectural invariants, vertical configs, and locked UX patterns across agent turns.
<!-- serena -->

<!-- chrome-devtools -->
## Chrome DevTools for Agents

Use `chrome-devtools` MCP tools for inspecting, testing, and debugging web apps, admin console, redirect flows, and webviews:
- Inspect console logs, network payloads, runtime errors, and DOM elements.
- Analyze live page performance, Core Web Vitals, and CrUX field data.
- Automate interactive browser testing for admin console (`admin_console/`) and payment redirects.
<!-- chrome-devtools -->

<!-- android-skills -->
## Official Android Skills Suite

Activate installed official Android skills in `.agents/skills/` or `.agent/skills/` when performing Android native tasks:
- `edge-to-edge`: Adaptive edge-to-edge layout & system inset handling.
- `camerax`: Camera & barcode scanning pipeline best practices.
- `play-policy-insights`: Google Play compliance, permissions hygiene, and data safety.
- `android-profiler`: Analyzing trace logs, memory allocations, jank, and startup bottlenecks.
- `android-intent-security`: Intent redirection prevention and exported component security.
- `r8-analyzer`: Proguard/R8 optimization, size shrink, and keep rules.
- `testing-setup`: Android testing harnesses, unit/integration and UI tests.
<!-- android-skills -->


