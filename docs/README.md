# Claude Tower Documentation

## Structure

```
docs/
├── README.md              # This file
├── SPECIFICATION.md       # Core specification (v3.2)
├── GLOSSARY.md           # Domain terminology
├── PSEUDOCODE.md         # Implementation pseudocode (v3.2)
├── CONFIGURATION.md      # Complete configuration reference
├── QUICKSTART.md         # Getting started guide
├── TROUBLESHOOTING.md    # Common issues and solutions
├── architecture/
│   ├── DESIGN_PHILOSOPHY.md  # Design principles
│   ├── socket-separation.md  # Server architecture
│   └── error-handling.md     # Error handling patterns
├── development/
│   ├── GAP_ANALYSIS.md       # Spec vs implementation (archived)
│   ├── SPEC_CODE_MAPPING.md  # Detailed code mapping
│   └── REVIEW_GUIDE.md       # Code review guidelines
└── testing/
    └── TEST_PYRAMID.md       # Test structure and coverage
```

## Document Overview

### Core Documents

| Document | Purpose |
|----------|---------|
| [SPECIFICATION.md](./SPECIFICATION.md) | ⚠️ Outdated (v3.x) — describes the removed worktree model |
| [GLOSSARY.md](./GLOSSARY.md) | Domain vocabulary definitions |
| [PSEUDOCODE.md](./PSEUDOCODE.md) | ⚠️ Outdated (v3.x) — implementation reference for the pre-v4 design |

### User Guides

The current user documentation is the [top-level README](../README.md). The
three guides below predate v4 and describe the worktree-based model that was
removed; they are kept for historical reference only.

| Document | Purpose |
|----------|---------|
| [QUICKSTART.md](./QUICKSTART.md) | ⚠️ Outdated (v3.x) |
| [CONFIGURATION.md](./CONFIGURATION.md) | ⚠️ Outdated (v3.x) |
| [TROUBLESHOOTING.md](./TROUBLESHOOTING.md) | ⚠️ Outdated (v3.x) |

### Architecture

| Document | Purpose |
|----------|---------|
| [DESIGN_PHILOSOPHY.md](./architecture/DESIGN_PHILOSOPHY.md) | Guiding principles and decisions |
| [socket-separation.md](./architecture/socket-separation.md) | Server isolation design |
| [error-handling.md](./architecture/error-handling.md) | Error recovery patterns |

### Development

| Document | Purpose |
|----------|---------|
| [SPEC_CODE_MAPPING.md](./development/SPEC_CODE_MAPPING.md) | Code-to-spec traceability |
| [REVIEW_GUIDE.md](./development/REVIEW_GUIDE.md) | Code review checklist |
| [GAP_ANALYSIS.md](./development/GAP_ANALYSIS.md) | Implementation status (archived) |

### Testing

| Document | Purpose |
|----------|---------|
| [TEST_PYRAMID.md](./testing/TEST_PYRAMID.md) | Test structure and coverage |

## Quick Links

- **Getting Started**: See the [top-level README](../README.md)
- **Contributing**: See [CONTRIBUTING.md](../CONTRIBUTING.md)
