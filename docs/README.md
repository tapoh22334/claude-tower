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
| [SPECIFICATION.md](./SPECIFICATION.md) | Authoritative behavioral specification (v3.2) |
| [GLOSSARY.md](./GLOSSARY.md) | Domain vocabulary definitions |
| [PSEUDOCODE.md](./PSEUDOCODE.md) | Implementation reference (v3.2) |

### User Guides

| Document | Purpose |
|----------|---------|
| [QUICKSTART.md](./QUICKSTART.md) | Getting started in 5 minutes |
| [CONFIGURATION.md](./CONFIGURATION.md) | Complete configuration reference |
| [TROUBLESHOOTING.md](./TROUBLESHOOTING.md) | Common issues and solutions |

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

- **Getting Started**: See [QUICKSTART.md](./QUICKSTART.md)
- **Current Version**: v3.2 (2026-01-03)
- **Test Status**: All behavioral tests passing
