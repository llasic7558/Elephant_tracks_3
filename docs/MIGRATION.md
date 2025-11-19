# Documentation Migration Guide

## What Changed

The ET3 documentation has been reorganized from **27+ scattered markdown files** in the root directory into a **structured documentation hierarchy** in the `docs/` folder.

## Old Structure (Before)

```
et2-java/
├── Readme.md
├── QUICK_START.md
├── FINAL_SUMMARY.md
├── IMPLEMENTATION_SUMMARY.md
├── ET3_INTEGRATED_MERLIN.md
├── MERLIN_README.md
├── MERLIN_USAGE.md
├── MERLIN_ANALYSIS_REPORT.md
├── MERLIN_APPROACHES_COMPARISON.md
├── MERLIN_COMPARISON_SUMMARY.md
├── LOGICAL_CLOCK_EXPLAINED.md
├── LOGICAL_CLOCK_SUMMARY.md
├── WITNESS_FIX_SUMMARY.md
├── WITNESS_RECORD_BUG.md
├── ALLOCATION_DEATH_MISMATCH.md
├── DEATH_TIMESTAMP_ANALYSIS.md
├── FIELD_UPDATES_AND_LOTSOFALLOCS_EXPLAINED.md
├── ORACLE_CONSTRUCTION.md
├── TEST_RESULTS_ANALYSIS.md
├── UPGRADE_SUMMARY.md
├── FINAL_RECOMMENDATION.md
├── ET3_DESIGN_PHILOSOPHY.md
├── ET3_TWO_MODES.md
├── OFFLINE_MODE_CHANGES.md
├── SWITCH_TO_OFFLINE_MERLIN.md
├── DACAPO_NO_HANG.md
├── DACAPO_USAGE.md
├── OBJECT_GRAPH_EXAMPLE.md
└── ... (code and other files)
```

**Problems**:
- 27+ markdown files cluttering root
- Overlapping content (multiple summaries)
- No clear hierarchy
- Hard to find information
- Redundant explanations

## New Structure (After)

```
et2-java/
├── Readme.md                    # Updated main README
├── docs/
│   ├── README.md               # Documentation hub
│   │
│   ├── getting-started/        # User guides
│   │   ├── README.md          # Quick start
│   │   └── testing.md         # Testing guide
│   │
│   ├── implementation/         # Technical details
│   │   ├── merlin.md          # Merlin algorithm
│   │   ├── logical-clock.md   # Logical time
│   │   └── architecture.md    # System design
│   │
│   ├── development/           # Development notes
│   │   ├── witness-fix.md     # Bug fix details
│   │   └── oracle.md          # Oracle construction
│   │
│   └── reference/             # Reference materials
│       ├── dacapo.md          # DaCapo usage
│       └── trace-format.md    # Trace specification
│
└── docs-archive/              # Original files (preserved)
    └── ... (old markdown files moved here)
```

**Benefits**:
- ✅ Clear hierarchy
- ✅ Consolidated content
- ✅ Easy navigation
- ✅ No duplication
- ✅ Clean root directory

## Content Mapping

### Getting Started

**Old Files** → **New Location**

- `QUICK_START.md` → `docs/getting-started/README.md`
- `FINAL_SUMMARY.md` → `docs/getting-started/README.md`
- `test_*` scripts → Referenced in `docs/getting-started/testing.md`

### Implementation

**Old Files** → **New Location**

- `ET3_INTEGRATED_MERLIN.md` → `docs/implementation/merlin.md`
- `MERLIN_README.md` → `docs/implementation/merlin.md`
- `MERLIN_USAGE.md` → `docs/implementation/merlin.md`
- `IMPLEMENTATION_SUMMARY.md` → `docs/implementation/merlin.md`
- `LOGICAL_CLOCK_EXPLAINED.md` → `docs/implementation/logical-clock.md`
- `LOGICAL_CLOCK_SUMMARY.md` → `docs/implementation/logical-clock.md`
- `ET3_DESIGN_PHILOSOPHY.md` → `docs/implementation/architecture.md`
- `ET3_TWO_MODES.md` → `docs/implementation/architecture.md`

### Development Notes

**Old Files** → **New Location**

- `WITNESS_FIX_SUMMARY.md` → `docs/development/witness-fix.md`
- `WITNESS_RECORD_BUG.md` → `docs/development/witness-fix.md`
- `ORACLE_CONSTRUCTION.md` → `docs/development/oracle.md`
- `ALLOCATION_DEATH_MISMATCH.md` → `docs/development/oracle.md`
- `DEATH_TIMESTAMP_ANALYSIS.md` → Consolidated into other docs
- `TEST_RESULTS_ANALYSIS.md` → `docs/getting-started/testing.md`

### Reference

**Old Files** → **New Location**

- `DACAPO_USAGE.md` → `docs/reference/dacapo.md`
- `DACAPO_NO_HANG.md` → `docs/reference/dacapo.md`
- `et2docs.md` → `docs/reference/trace-format.md`
- `OBJECT_GRAPH_EXAMPLE.md` → `docs/implementation/merlin.md`

### Analysis Reports (Archived)

These were interim analysis documents:

- `MERLIN_ANALYSIS_REPORT.md` → Archived
- `MERLIN_APPROACHES_COMPARISON.md` → Archived
- `MERLIN_COMPARISON_SUMMARY.md` → Archived
- `FIELD_UPDATES_AND_LOTSOFALLOCS_EXPLAINED.md` → Archived
- `OFFLINE_MODE_CHANGES.md` → Archived
- `SWITCH_TO_OFFLINE_MERLIN.md` → Archived
- `UPGRADE_SUMMARY.md` → Archived
- `FINAL_RECOMMENDATION.md` → Archived

## How to Use the New Documentation

### Finding Information

**Starting point**: `docs/README.md`

**I want to...**

- **Get started quickly** → `docs/getting-started/README.md`
- **Run tests** → `docs/getting-started/testing.md`
- **Understand Merlin** → `docs/implementation/merlin.md`
- **Learn about logical time** → `docs/implementation/logical-clock.md`
- **Understand the architecture** → `docs/implementation/architecture.md`
- **Fix a bug** → `docs/development/witness-fix.md`
- **Generate oracles** → `docs/development/oracle.md`
- **Run DaCapo** → `docs/reference/dacapo.md`
- **Parse traces** → `docs/reference/trace-format.md`

### Navigation

Each document includes:
- Clear section headers
- Table of contents (where needed)
- Links to related documents
- Code examples
- Command references

### Original Files

All original markdown files are preserved in `docs-archive/` for reference.

## Key Improvements

### Consolidated Content

**Before**: 3 separate Merlin files  
**After**: Single comprehensive `docs/implementation/merlin.md`

**Before**: 2 separate logical clock files  
**After**: Single comprehensive `docs/implementation/logical-clock.md`

**Before**: Multiple summary files  
**After**: Content integrated into appropriate sections

### Better Organization

- **Getting Started**: User-facing, action-oriented
- **Implementation**: Technical details for developers
- **Development**: Bug fixes and analysis
- **Reference**: Specifications and external tools

### Reduced Redundancy

- Eliminated duplicate explanations
- Consolidated overlapping summaries
- Single source of truth for each topic

### Easier Maintenance

- Clear place for new documentation
- Logical grouping of related content
- Easier to update and keep current

## Migration Checklist

If you have bookmarks or references to old files:

- [ ] Update bookmarks to new `docs/` locations
- [ ] Update scripts that reference old paths
- [ ] Update external documentation links
- [ ] Check `docs-archive/` for any missing content

## Questions?

The new documentation structure is designed to be intuitive, but if you can't find something:

1. Check `docs/README.md` for the full directory structure
2. Use search in your editor to find content across all docs
3. Check `docs-archive/` for original files

## Next Steps

- Start with `docs/README.md` for an overview
- Jump to `docs/getting-started/README.md` to begin using ET3
- Explore implementation details in `docs/implementation/`
- Reference `docs-archive/` only if you need original files

The documentation is now organized, consolidated, and easier to navigate!
