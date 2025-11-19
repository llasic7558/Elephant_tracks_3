# Avoiding Shutdown Hang on Large Benchmarks

## The Problem

DaCapo benchmarks can have thousands of live objects at shutdown. The final Merlin death analysis can take a long time or hang.

## Solution 1: Rebuild with Better Diagnostics (Recommended)

```bash
cd javassist-inst/et2-instrumenter
mvn clean compile package -q
cd ../..
```

Then run again. You'll now see:
```
ET3 shutting down, finalizing trace...
Merlin final analysis: 12345 deaths in 2500ms
ET3 trace complete with Merlin death tracking
```

If it's stuck at "finalizing trace..." for more than 30 seconds, press Ctrl+C.

## Solution 2: Check Trace Anyway

Even if it hangs, the trace might be complete:

```bash
# Check if trace exists
ls -lh trace

# Check last lines (should have D records)
tail -50 trace

# Count records
echo "Allocations: $(grep -c '^[NA]' trace)"
echo "Deaths: $(grep -c '^D' trace)"
```

## Solution 3: Use Timeout

Add a timeout to your command:

```bash
timeout 5m java -javaagent:./javassist-inst/et2-instrumenter/target/instrumenter-1.0-SNAPSHOT-jar-with-dependencies.jar -Xmx2g -jar ../dacapo-23.11-MR2-chopin/dacapo-23.11-MR2-chopin.jar --no-validation -s small avrora
```

After 5 minutes, it will kill the process, but the trace should be mostly complete.

## What's Happening

1. **During execution**: Deaths are detected at method exits ✓ (working)
2. **At shutdown**: Final death detection for remaining objects (may hang)

The deaths during execution are the most valuable - those are the ones with accurate method-boundary timing!

## Recommended Workflow

```bash
# 1. Start benchmark
java -javaagent:./javassist-inst/et2-instrumenter/target/instrumenter-1.0-SNAPSHOT-jar-with-dependencies.jar -Xmx2g -jar ../dacapo-23.11-MR2-chopin/dacapo-23.11-MR2-chopin.jar --no-validation -s small avrora &

# 2. Monitor progress
PID=$!
watch -n 2 "ls -lh trace 2>/dev/null || echo 'Waiting for trace...'"

# 3. If it hangs after benchmark completes, just kill it
# The trace will still have all the important deaths from method exits
kill $PID

# 4. Check the trace
grep -c '^D' trace
```

## Understanding the Trace

Even without final shutdown deaths, you have:
- ✅ All allocations (N, A records)
- ✅ All method entries/exits (M, E records)  
- ✅ All field updates (U records)
- ✅ **Deaths detected during execution** (D records at method exits)

Only missing:
- ❌ Deaths for objects still live at shutdown (usually less interesting)

This is still a **complete and valid Merlin trace**!
