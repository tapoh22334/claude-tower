# Claude Tower Documentation

## Structure

```
docs/
├── README.md              # This file
├── SPECIFICATION.md       # Core specification (v3.1)
├── GLOSSARY.md           # Domain terminology
├── PSEUDOCODE.md         # Implementation pseudocode
├── architecture/
│   ├── DESIGN_PHILOSOPHY.md  # Design principles
│   ├── socket-separation.md  # Server architecture
│   └── error-handling.md     # Error handling patterns
├── development/
│   ├── GAP_ANALYSIS.md       # Spec vs implementation status
│   ├── SPEC_CODE_MAPPING.md  # Detailed code mapping
│   └── REVIEW_GUIDE.md       # Code review guidelines
└── testing/
    └── TEST_PYRAMID.md       # Test structure and coverage
```

## Document Overview

### Core Documents

| Document | Purpose |
|----------|---------|
| [SPECIFICATION.md](./SPECIFICATION.md) | Authoritative behavioral specification |
| [GLOSSARY.md](./GLOSSARY.md) | Domain vocabulary definitions |
| [PSEUDOCODE.md](./PSEUDOCODE.md) | Implementation reference |

### Architecture

| Document | Purpose |
|----------|---------|
| [DESIGN_PHILOSOPHY.md](./architecture/DESIGN_PHILOSOPHY.md) | Guiding principles and decisions |
| [socket-separation.md](./architecture/socket-separation.md) | Server isolation design |
| [error-handling.md](./architecture/error-handling.md) | Error recovery patterns |

### Development

| Document | Purpose |
|----------|---------|
| [GAP_ANALYSIS.md](./development/GAP_ANALYSIS.md) | Implementation status tracking |
| [SPEC_CODE_MAPPING.md](./development/SPEC_CODE_MAPPING.md) | Code-to-spec traceability |
| [REVIEW_GUIDE.md](./development/REVIEW_GUIDE.md) | Code review checklist |

### Testing

| Document | Purpose |
|----------|---------|
| [TEST_PYRAMID.md](./testing/TEST_PYRAMID.md) | Test structure and coverage |

## Quick Links

- **Getting Started**: See [README.md](../README.md) in project root
- **Current Version**: v3.1 (2026-01-02)
- **Test Status**: 171/175 passing (97.7%)
