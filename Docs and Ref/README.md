# Sandbox Documentation

Complete documentation for the Normal-OJ Sandbox system.

---

## 📁 Directory Structure

```
Docs and Ref/
├── API/            # API reference documentation
├── Architecture/   # System architecture, schemas, and core concepts
├── Guides/         # Implementation and operational guides
├── Flows/          # Flow diagrams (HTML + markdown)
└── DevNotes/       # Transient analysis, debug notes, and plans
```

---

## 🏛️ Architecture & Core

System architecture, schemas, and core concepts.

| Document | Description |
|----------|-------------|
| [SystemArchitecture.md](./Architecture/SystemArchitecture.md) | System architecture overview |
| [DirectoryStructure.md](./Architecture/DirectoryStructure.md) | Codebase structure |
| [DatabaseSchema.md](./Architecture/DatabaseSchema.md) | MongoDB and Redis schema reference |
| [InteractiveMode.md](./Architecture/InteractiveMode.md) | Interactive mode architecture |
| [PathTranslation.md](./Architecture/PathTranslation.md) | Path translation logic (Host vs Container) |

---

## 🔌 API Reference

| Document | Description |
|----------|-------------|
| [Reference.md](./API/Reference.md) | Complete API documentation (Backend & Sandbox) |

---

## 📖 Implementation Guides

Detailed guides for each system component.

| Document | Description |
|----------|-------------|
| [01_FILE_CONTROL.md](./Guides/01_FILE_CONTROL.md) | File control and asset caching |
| [02_STATIC_ANALYSIS.md](./Guides/02_STATIC_ANALYSIS.md) | Static analysis (Python AST, C/C++ libclang) |
| [03_NETWORK_CONTROL.md](./Guides/03_NETWORK_CONTROL.md) | Network access control (firewall, local services) |
| [04_FUNCTION_ONLY.md](./Guides/04_FUNCTION_ONLY.md) | Function-only mode details |
| [05_INTERACTIVE.md](./Guides/05_INTERACTIVE.md) | Interactive mode guide |
| [06_CHECKER.md](./Guides/06_CHECKER.md) | Custom checker system |
| [07_SCORING.md](./Guides/07_SCORING.md) | Custom scoring system |
| [08_ARTIFACT.md](./Guides/08_ARTIFACT.md) | Artifact collection (compiled binary, test outputs) |
| [09_ACCESS_CONTROL.md](./Guides/09_ACCESS_CONTROL.md) | Access control guide |
| [10_RESOURCE_DATA.md](./Guides/10_RESOURCE_DATA.md) | Resource data guide |
| [CONFIG_REFERENCE.md](./Guides/CONFIG_REFERENCE.md) | Configuration file reference (dispatcher, submission, interactive) |
| [BUILD_STRATEGY_GUIDE.md](./Guides/BUILD_STRATEGY_GUIDE.md) | Build strategies (compile, makeNormal, makeFunctionOnly, makeInteractive) |
| [DEPLOYMENT.md](./Guides/DEPLOYMENT.md) | Deployment guide (Docker Compose, environment variables) |
| [SECURITY.md](./Guides/SECURITY.md) | Security model (Seccomp, capabilities, resource limits) |
| [TESTING.md](./Guides/TESTING.md) | Testing strategy (pytest, Playwright, CI/CD, coverage) |
| [FRONTEND_DEV_GUIDE.md](./FRONTEND_DEV_GUIDE.md) | Frontend development guide (Vue 3, TypeScript, routing, API) |

---

## 📊 Flow Diagrams

Interactive Mermaid flowcharts (HTML) with supporting documentation (Markdown).

### HTML Flowcharts

| Flowchart | Description |
|-----------|-------------|
| [BUILD_STRATEGY_FLOW.html](./Flows/BUILD_STRATEGY_FLOW.html) | Build strategy decision tree |
| [STATIC_ANALYSIS_FLOW.html](./Flows/STATIC_ANALYSIS_FLOW.html) | Static analysis workflow |
| [INTERACTIVE_MODE_FLOW.html](./Flows/INTERACTIVE_MODE_FLOW.html) | Interactive mode execution |
| [FUNCTION_ONLY_FLOW.html](./Flows/FUNCTION_ONLY_FLOW.html) | Function-only mode |
| [SA_FAILURE_FLOW.html](./Flows/SA_FAILURE_FLOW.html) | Static analysis failure handling |
| [ZIP_MODE_FLOW.html](./Flows/ZIP_MODE_FLOW.html) | ZIP submission mode |

### Supporting Documentation

| Document | Description |
|----------|-------------|
| [InteractiveMode.md](./Architecture/InteractiveMode.md) | Interactive mode architecture |
| [SA_FAILURE_FLOW.md](./Flows/SA_FAILURE_FLOW.md) | Static analysis failure scenarios |

---

## 📝 DevNotes

Transient analysis, debugging notes, and refactoring plans. These are kept for historical context.

*   `INTERACTIVE_REFACTORING_PLAN.md`
*   `TEACHER_COMPILE_ERROR_DIAGNOSIS.md`
*   `TEACHER_LANG_TRACING.md`
*   `INTERACTIVE_CODE_REVIEW.md`
*   `INTERACTIVE_COMPREHENSIVE_ANALYSIS.md`
*   `INTERACTIVE_PERMISSIONS_ANALYSIS.md`

---

## 🔄 Recent Changes

**2025-12-03**: Documentation Reorganization
- Reorganized Guides with numbered prefixes.
- Merged File Control and Asset Caching.
- Merged Interactive Mode documentation.
- Split Checker and Scoring guides.

**2025-11-30**: Documentation Consolidation
- Reorganized into `API`, `Architecture`, `Guides`, `Flows`, `DevNotes`
- Consolidated Path Translation documentation
- Moved transient analysis files to `DevNotes`

**2025-11-29**: Major documentation expansion
- Added comprehensive guides: DEPLOYMENT, TESTING, DATABASE_SCHEMA, FRONTEND_DEV, ARTIFACT
- Updated API_REFERENCE with complete Backend & Sandbox documentation

---

## 📞 Maintainers

For questions or updates to documentation, consult the development team.
