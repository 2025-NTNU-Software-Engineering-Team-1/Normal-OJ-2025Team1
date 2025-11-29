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
| [CONFIG_REFERENCE.md](./Guides/CONFIG_REFERENCE.md) | Configuration file reference (dispatcher, submission, interactive) |
| [BUILD_STRATEGY_GUIDE.md](./Guides/BUILD_STRATEGY_GUIDE.md) | Build strategies (compile, makeNormal, makeFunctionOnly, makeInteractive) |
| [STATIC_ANALYSIS.md](./Guides/STATIC_ANALYSIS.md) | Static analysis (Python AST, C/C++ libclang) |
| [CHECKER_SCORING_GUIDE.md](./Guides/CHECKER_SCORING_GUIDE.md) | Custom checker and scoring system |
| [NETWORK_CONTROL_GUIDE.md](./Guides/NETWORK_CONTROL_GUIDE.md) | Network access control (firewall, local services) |
| [SECURITY_GUIDE.md](./Guides/SECURITY_GUIDE.md) | Security mechanisms (Seccomp, Docker isolation, risks) |
| [DEPLOYMENT_GUIDE.md](./Guides/DEPLOYMENT_GUIDE.md) | Production deployment guide (setup, SSL, monitoring, backup) |
| [TESTING_GUIDE.md](./Guides/TESTING_GUIDE.md) | Testing strategy (pytest, Playwright, CI/CD, coverage) |
| [FRONTEND_DEV_GUIDE.md](./Guides/FRONTEND_DEV_GUIDE.md) | Frontend development guide (Vue 3, TypeScript, routing, API) |
| [ARTIFACT_GUIDE.md](./Guides/ARTIFACT_GUIDE.md) | Artifact collection (compiled binary, test outputs) |
| [InteractivePermissions.md](./Guides/InteractivePermissions.md) | Interactive mode permissions guide |

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
| [InteractiveMode.md](./Flows/InteractiveMode.md) | Interactive mode flow explanation |
| [FUNCTION_ONLY_FLOW.md](./Flows/FUNCTION_ONLY_FLOW.md) | Function-only mode explanation |
| [SA_FAILURE_FLOW.md](./Flows/SA_FAILURE_FLOW.md) | Static analysis failure scenarios |
| [ZIP_MODE_FLOW.md](./Flows/ZIP_MODE_FLOW.md) | ZIP submission requirements |

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
