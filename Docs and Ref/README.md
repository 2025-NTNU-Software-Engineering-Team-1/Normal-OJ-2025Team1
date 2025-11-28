# Sandbox Documentation

Complete documentation for the Normal-OJ Sandbox system.

---

## 📁 Directory Structure

```
Docs and Ref/
├── Core/           # System architecture and API reference
├── Guides/         # Implementation guides
├── Interactive/    # Interactive mode documentation
└── Flows/          # Flow diagrams (HTML + markdown)
```

---

## 📘 Core Documentation

System architecture and API reference.

| Document | Description |
|----------|-------------|
| [ARCHITECTURE.md](./Core/ARCHITECTURE.md) | System architecture overview |
| [STRUCTURE.md](./Core/STRUCTURE.md) | Codebase structure |
| [API_REFERENCE.md](./Core/API_REFERENCE.md) | Complete API documentation (Backend & Sandbox) |
| [DATABASE_SCHEMA.md](./Core/DATABASE_SCHEMA.md) | MongoDB and Redis schema reference |

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

---

## 🔐 Interactive Mode

Complete documentation for Interactive execution mode.

| Document | Description |
|----------|-------------|
| [INTERACTIVE_MODE_FLOW.md](./Interactive/INTERACTIVE_MODE_FLOW.md) | Interactive mode architecture and flow |
| [INTERACTIVE_PERMISSIONS_GUIDE.md](./Interactive/INTERACTIVE_PERMISSIONS_GUIDE.md) | Permissions control guide (UID/GID, file permissions) |
| [INTERACTIVE_PERMISSIONS_ANALYSIS.md](./Interactive/INTERACTIVE_PERMISSIONS_ANALYSIS.md) | **Latest** permissions analysis (v2.0) |

**Flow Diagram**: [INTERACTIVE_MODE_FLOW.html](./Flows/INTERACTIVE_MODE_FLOW.html)

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
| [FUNCTION_ONLY_FLOW.md](./Flows/FUNCTION_ONLY_FLOW.md) | Function-only mode explanation |
| [SA_FAILURE_FLOW.md](./Flows/SA_FAILURE_FLOW.md) | Static analysis failure scenarios |
| [ZIP_MODE_FLOW.md](./Flows/ZIP_MODE_FLOW.md) | ZIP submission requirements |

---

- **Links**: Use relative paths within documentation
- **Flow diagrams**: HTML files contain interactive Mermaid charts

---

## 🔄 Recent Changes

**2025-11-29**: Major documentation expansion
- Added comprehensive guides: DEPLOYMENT, TESTING, DATABASE_SCHEMA, FRONTEND_DEV, ARTIFACT
- Updated API_REFERENCE with complete Backend & Sandbox documentation
- Enhanced CHECKER_SCORING, NETWORK_CONTROL, and SECURITY guides
- Completed 9 out of 10 planned documentation guides (90%)

**2025-11-29**: Documentation reorganization
- Created subdirectory structure (Core, Guides, Interactive, Flows)
- Removed outdated `INTERACTIVE_PERMISSIONS_DIAGNOSIS.md`
- Added this README for navigation

---

## 📞 Maintainers

For questions or updates to documentation, consult the development team.
