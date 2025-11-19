# ET3 Documentation

This directory contains all documentation for Elephant Tracks 3 (ET3) with Merlin integration.

## Quick Links

- **[Getting Started](getting-started/)** - Build, run, and test ET3
- **[Implementation Guide](implementation/)** - Technical details and architecture
- **[Development Notes](development/)** - Bug fixes, analysis, and research notes
- **[Reference](reference/)** - DaCapo usage, trace formats, papers

## Directory Structure

```
docs/
├── getting-started/        # User-facing guides
│   ├── README.md          # Quick start
│   └── testing.md         # Testing instructions
│
├── implementation/         # Technical implementation
│   ├── merlin.md          # Merlin algorithm integration
│   ├── logical-clock.md   # Logical clock implementation
│   └── architecture.md    # Overall system design
│
├── development/           # Development notes and fixes
│   ├── witness-fix.md     # Witness record bug fix
│   ├── oracle.md          # Oracle construction
│   └── analysis.md        # Results analysis
│
└── reference/             # Reference materials
    ├── dacapo.md          # DaCapo benchmark usage
    └── trace-format.md    # Trace file format spec
```

## What is ET3?

Elephant Tracks 3 is a garbage collection tracing tool for Java programs that produces:
- ✅ In-order traces of allocations, deaths, method calls, and field updates
- ✅ Object death tracking using the Merlin Algorithm
- ✅ Logical time measurements at method boundaries
- ✅ Oracle files for memory allocator simulation

## Quick Start

```bash
# Build
cd javassist-inst/et2-instrumenter
mvn clean compile package

# Run
java -javaagent:target/instrumenter-1.0-SNAPSHOT-jar-with-dependencies.jar YourProgram
```

See [Getting Started](getting-started/) for details.
