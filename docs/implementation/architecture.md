# ET3 Architecture Overview

## System Components

```
┌─────────────────────────────────────────────────────────┐
│                    Java Application                      │
└──────────────────┬──────────────────────────────────────┘
                   │ bytecode
                   ↓
┌─────────────────────────────────────────────────────────┐
│              Javassist Instrumentation                   │
│  (DynamicInstrumenter.java + MethodInstrumenter.java)   │
└──────────────────┬──────────────────────────────────────┘
                   │ instrumented bytecode
                   ↓
┌─────────────────────────────────────────────────────────┐
│                  ETProxy.java                           │
│  - Trace writing                                        │
│  - Logical clock management                             │
│  - Event buffering                                      │
│  - Merlin integration                                   │
└──────────────────┬──────────────────────────────────────┘
                   │ events
                   ↓
┌─────────────────────────────────────────────────────────┐
│               MerlinTracker.java                        │
│  - Live object tracking                                 │
│  - Object graph construction                            │
│  - Reachability analysis                                │
│  - Death detection                                      │
└──────────────────┬──────────────────────────────────────┘
                   │ death records
                   ↓
┌─────────────────────────────────────────────────────────┐
│                    Trace File                           │
│  (N, A, M, E, U, D records in temporal order)          │
└─────────────────────────────────────────────────────────┘
```

## Build Process

### Maven Structure

```
javassist-inst/et2-instrumenter/
├── pom.xml                    # Maven configuration
├── src/main/java/veroy/research/et2/javassist/
│   ├── DynamicInstrumenter.java    # Java agent entry point
│   ├── MethodInstrumenter.java     # Bytecode instrumentation
│   ├── ETProxy.java                # Runtime tracing
│   ├── MerlinTracker.java          # Integrated death tracking
│   ├── MerlinDeathTracker.java     # Offline death tracking
│   └── InstrumentFlag.java         # Configuration
└── target/
    └── instrumenter-1.0-SNAPSHOT-jar-with-dependencies.jar
```

### Build Command

```bash
cd javassist-inst/et2-instrumenter
mvn clean compile package
```

### Dependencies (from pom.xml)

```xml
<dependencies>
    <dependency>
        <groupId>org.javassist</groupId>
        <artifactId>javassist</artifactId>
        <version>3.24.1-GA</version>
    </dependency>
    <dependency>
        <groupId>commons-io</groupId>
        <artifactId>commons-io</artifactId>
        <version>2.6</version>
    </dependency>
    <dependency>
        <groupId>log4j</groupId>
        <artifactId>log4j</artifactId>
        <version>1.2.17</version>
    </dependency>
</dependencies>
```

## Runtime Execution Flow

### 1. JVM Startup with Agent

```bash
java -javaagent:instrumenter.jar YourProgram
```

JVM calls `DynamicInstrumenter.premain()`

### 2. Class Loading Interception

```java
// DynamicInstrumenter.java
public static void premain(String agentArgs, Instrumentation inst) {
    // Register transformer
    inst.addTransformer(new ClassFileTransformer() {
        public byte[] transform(...) {
            // Intercept class loading
            return MethodInstrumenter.instrumentClass(classfileBuffer);
        }
    });
    
    // Register shutdown hook
    Runtime.getRuntime().addShutdownHook(new Thread() {
        public void run() {
            ETProxy.onShutdown();
        }
    });
}
```

### 3. Bytecode Instrumentation

```java
// MethodInstrumenter.java
public static byte[] instrumentClass(byte[] bytecode) {
    ClassPool pool = ClassPool.getDefault();
    CtClass ctClass = pool.makeClass(bytecode);
    
    // Instrument all methods
    for (CtMethod method : ctClass.getDeclaredMethods()) {
        // Insert at method entry
        method.insertBefore(
            "veroy.research.et2.javassist.ETProxy.onEntry(" +
            "METHOD_ID, $0, Thread.currentThread().getId());"
        );
        
        // Insert at method exit
        method.insertAfter(
            "veroy.research.et2.javassist.ETProxy.onExit(" +
            "METHOD_ID, Thread.currentThread().getId());"
        );
    }
    
    // Instrument field accesses
    method.instrument(new ExprEditor() {
        public void edit(FieldAccess f) {
            f.replace(
                "veroy.research.et2.javassist.ETProxy.onPutField(...);" +
                "$_ = $proceed($$);"
            );
        }
        
        public void edit(NewExpr e) {
            e.replace(
                "$_ = $proceed($$);" +
                "veroy.research.et2.javassist.ETProxy.onObjectAlloc(...);"
            );
        }
    });
    
    return ctClass.toBytecode();
}
```

### 4. Event Interception

Every instrumented action calls `ETProxy`:

```java
// Your code:
Object obj = new Object();

// Becomes:
Object obj = new Object();
ETProxy.onObjectAlloc(obj.hashCode(), size, typeId, siteId, threadId);
```

```java
// Your code:
myMethod(arg);

// Becomes:
ETProxy.onEntry(METHOD_ID, this.hashCode(), threadId);
myMethod(arg);
ETProxy.onExit(METHOD_ID, threadId);
```

### 5. Trace Writing

```java
// ETProxy.java
public static void onObjectAlloc(...) {
    // Format record
    String record = String.format("N %d %d %d %d %d %d",
        objectId, size, typeId, siteId, 0, timestamp);
    
    // Buffer for performance
    buffer.add(record);
    
    if (buffer.size() >= BUFFER_SIZE) {
        flushBuffer();
    }
    
    // Update Merlin
    MerlinTracker.onObjectAlloc(objectId, threadId, timestamp);
}

private static void flushBuffer() {
    synchronized (traceWriter) {
        for (String record : buffer) {
            traceWriter.println(record);
        }
        buffer.clear();
    }
}
```

### 6. Merlin Death Tracking

```java
// ETProxy.java
public static void onExit(...) {
    // Get deaths detected at this method boundary
    List<MerlinTracker.DeathRecord> deaths = 
        MerlinTracker.onMethodExit(methodId, threadId);
    
    // Write method exit
    long timestamp = logicalClock.incrementAndGet();
    traceWriter.println("E " + methodId + " " + timestamp);
    
    // Write death records
    for (DeathRecord death : deaths) {
        traceWriter.println("D " + death.objectId + " " + death.threadId + " " + timestamp);
    }
}
```

### 7. Shutdown

```java
// DynamicInstrumenter shutdown hook
public void run() {
    ETProxy.onShutdown();
    MethodInstrumenter.writeMapsToFile();
}

// ETProxy.java
public static void onShutdown() {
    // Final death detection
    List<DeathRecord> deaths = MerlinTracker.performFinalAnalysis();
    for (DeathRecord death : deaths) {
        traceWriter.println(death.toString());
    }
    
    // Flush and close
    flushBuffer();
    traceWriter.close();
}
```

## Data Structures

### ETProxy State

```java
// Trace output
private static PrintWriter traceWriter;
private static List<String> buffer = new ArrayList<>();
private static final int BUFFER_SIZE = 1000;

// Logical time
private static AtomicInteger logicalClock = new AtomicInteger(0);

// Thread safety
private static final Object LOCK = new Object();
```

### MerlinTracker State

```java
// Live objects
private static Set<Integer> liveObjects = 
    Collections.synchronizedSet(new HashSet<>());

// Object graph (object → references)
private static Map<Integer, Set<Integer>> objectGraph = 
    Collections.synchronizedMap(new HashMap<>());

// Per-thread stacks (for root set)
private static Map<Long, Stack<Integer>> threadStacks = 
    Collections.synchronizedMap(new HashMap<>());

// Static field roots
private static Set<Integer> staticRoots = 
    Collections.synchronizedSet(new HashSet<>());

// Event counter (for periodic analysis)
private static AtomicInteger eventCounter = new AtomicInteger(0);
```

## Thread Safety

### Synchronization Strategy

1. **Trace Writing**: Synchronized on `traceWriter`
   ```java
   synchronized (traceWriter) {
       traceWriter.println(record);
   }
   ```

2. **Merlin State**: Synchronized collections
   ```java
   Collections.synchronizedSet(...)
   Collections.synchronizedMap(...)
   ```

3. **Logical Clock**: AtomicInteger
   ```java
   logicalClock.incrementAndGet();  // Thread-safe
   ```

### Multi-Threading Challenges

- Multiple threads generate events concurrently
- Trace records from different threads interleave
- Merlin must track per-thread stacks
- Death detection runs from any thread

### Solution

```java
// Per-thread stacks
Map<Long, Stack<Integer>> threadStacks;

// Thread-safe collections
Collections.synchronizedSet();
Collections.synchronizedMap();

// Atomic clock
AtomicInteger logicalClock;
```

## Performance Optimizations

### 1. Event Buffering

```java
// Buffer BUFFER_SIZE events before writing
private static List<String> buffer = new ArrayList<>(BUFFER_SIZE);
```

**Benefit**: Reduces I/O overhead by ~10x

### 2. Periodic Analysis

```java
// Reachability analysis every N events, not every event
if (eventCounter.incrementAndGet() % ANALYSIS_INTERVAL == 0) {
    performReachabilityAnalysis();
}
```

**Benefit**: Reduces CPU overhead from 100% to 5-10%

### 3. Lazy Graph Cleanup

```java
// Only remove dead objects from graph when detected
for (Integer objId : deadObjects) {
    objectGraph.remove(objId);
}
```

**Benefit**: Keeps graph size bounded to live objects only

### 4. Fast Object IDs

```java
// Use hashCode() instead of custom ID generation
int objectId = System.identityHashCode(object);
```

**Benefit**: Zero overhead for ID assignment

## File Outputs

### Runtime Trace (trace)

Generated during execution:

```
N 1001 32 100 200 0 1
M 200 1001 2
U 1001 1002 3 2
E 200 3
D 1001 5001 3
```

### Class/Method Maps

Generated at shutdown:

```
# class_list
100,java/lang/Object
101,java/lang/String

# method_list
200,100,<init>
201,101,toString
```

### Offline Processing Outputs

Post-processing can generate:

- **trace_with_deaths**: Original + deaths appended
- **trace_reordered**: Deaths in temporal order
- **oracle.txt**: Human-readable oracle
- **oracle.csv**: Machine-readable for gem5

## Extension Points

### Adding New Event Types

1. **Instrument in MethodInstrumenter**
   ```java
   method.instrument(new ExprEditor() {
       public void edit(NewExpr e) {
           // Your new event type
       }
   });
   ```

2. **Add handler in ETProxy**
   ```java
   public static void onNewEvent(...) {
       // Write trace record
       // Update Merlin if needed
   }
   ```

3. **Update Merlin if reachability-related**
   ```java
   // MerlinTracker.java
   public static void onNewEvent(...) {
       // Update graph/roots
   }
   ```

### Configuration

Edit `InstrumentFlag.java`:

```java
public class InstrumentFlag {
    public static final boolean TRACE_ALLOCATIONS = true;
    public static final boolean TRACE_METHODS = true;
    public static final boolean TRACE_FIELDS = true;
    public static final boolean ENABLE_MERLIN = true;
}
```

## Two-Mode Architecture

### Online Mode (Integrated Merlin)

```
Instrumentation → ETProxy → MerlinTracker → Trace with Deaths
```

**Characteristics**:
- Deaths in original trace
- Single-pass execution
- Real-time analysis

### Offline Mode (Post-Processing)

```
Instrumentation → ETProxy → Trace without Deaths
                              ↓
                   MerlinDeathTracker → Trace with Deaths
```

**Characteristics**:
- Two-pass algorithm
- Can reprocess existing traces
- Witness-aware death detection

See `ET3_TWO_MODES.md` (archived) for details.

## Next Steps

- See [Merlin Implementation](merlin.md) for death tracking details
- Read [Logical Clock](logical-clock.md) for time measurement
- Review [Getting Started](../getting-started/) for usage examples
