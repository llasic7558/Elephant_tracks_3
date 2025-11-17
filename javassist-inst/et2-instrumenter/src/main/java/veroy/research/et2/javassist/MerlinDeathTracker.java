package veroy.research.et2.javassist;

import java.io.*;
import java.util.*;

/**
 * MerlinDeathTracker - Implements the Merlin Algorithm for tracking object deaths
 * 
 * The Merlin algorithm reconstructs object death information from trace files
 * by maintaining object reachability information. Objects are considered dead
 * when they become unreachable from any root (stack frames or static fields).
 * 
 * Based on the paper: "Merlin: Efficient and Enhanced Memory Leak Detection"
 * https://cse.buffalo.edu/~mhertz/toplas-2006-merlin.pdf
 */
public class MerlinDeathTracker {
    
    // Data structures for tracking object reachability
    private Map<Integer, ObjectInfo> liveObjects;           // objectId -> ObjectInfo
    private Map<Integer, Set<Integer>> objectGraph;         // objectId -> Set of referenced objectIds
    private Map<Integer, Set<Integer>> reverseGraph;        // objectId -> Set of objects referencing it
    private Map<Long, Set<Integer>> threadStacks;           // threadId -> Set of objectIds on stack
    private Set<Integer> staticRoots;                       // Objects in static fields
    
    // Thread-local method call stacks (for tracking stack roots)
    private Map<Long, Stack<MethodFrame>> threadCallStacks;
    
    // Track death events to be written
    private List<DeathRecord> deathRecords;
    
    // Logical clock (increments at method entry/exit, same as ETProxy)
    private long logicalClock;
    
    // Witness tracking: Map object ID to its last witness (access) time
    // This prevents marking objects dead before their last access
    private Map<Integer, Long> lastWitnessTime;
    
    // Configuration
    private boolean verbose;
    private PrintWriter outputWriter;
    
    /**
     * Represents information about a live object
     */
    @SuppressWarnings("unused") // Fields kept for potential future analysis enhancements
    private static class ObjectInfo {
        int objectId;
        int typeId;
        int allocSiteId;
        long size;
        long threadId;
        boolean isArray;
        int arrayLength;
        
        ObjectInfo(int objectId, int typeId, int allocSiteId, long size, long threadId) {
            this.objectId = objectId;
            this.typeId = typeId;
            this.allocSiteId = allocSiteId;
            this.size = size;
            this.threadId = threadId;
            this.isArray = false;
        }
    }
    
    /**
     * Represents a method frame on the call stack
     */
    @SuppressWarnings("unused") // Fields kept for potential debugging and analysis
    private static class MethodFrame {
        int methodId;
        int receiverObjectId;
        Set<Integer> localObjects; // Objects referenced in this frame
        
        MethodFrame(int methodId, int receiverObjectId) {
            this.methodId = methodId;
            this.receiverObjectId = receiverObjectId;
            this.localObjects = new HashSet<>();
        }
    }
    
    /**
     * Represents a death record to be output
     */
    private static class DeathRecord {
        int objectId;
        long threadId;
        long timestamp;  // Logical time of death
        
        DeathRecord(int objectId, long threadId, long timestamp) {
            this.objectId = objectId;
            this.threadId = threadId;
            this.timestamp = timestamp;
        }
        
        @Override
        public String toString() {
            return "D " + objectId + " " + threadId + " " + timestamp;
        }
    }
    
    /**
     * Constructor
     */
    public MerlinDeathTracker(boolean verbose) {
        this.verbose = verbose;
        this.liveObjects = new HashMap<>();
        this.objectGraph = new HashMap<>();
        this.reverseGraph = new HashMap<>();
        this.threadStacks = new HashMap<>();
        this.staticRoots = new HashSet<>();
        this.threadCallStacks = new HashMap<>();
        this.deathRecords = new ArrayList<>();
        this.logicalClock = 0;  // Start at 0, increments at M/E records
        this.lastWitnessTime = new HashMap<>();  // Track last access times
    }
    
    /**
     * Process a trace file and generate death records
     * Uses two-pass algorithm to handle witness records correctly
     */
    public void processTrace(String inputTraceFile, String outputTraceFile) throws IOException {
        if (verbose) {
            System.err.println("MerlinDeathTracker: Starting two-pass processing...");
        }
        
        // PASS 1: Collect all witness times and logical clock progression
        buildWitnessMap(inputTraceFile);
        
        if (verbose) {
            System.err.println("MerlinDeathTracker: Found witness records for " + lastWitnessTime.size() + " objects");
        }
        
        // PASS 2: Process trace with witness-aware death detection
        processTraceWithWitnesses(inputTraceFile, outputTraceFile);
    }
    
    /**
     * PASS 1: Build map of last witness times for each object
     */
    private void buildWitnessMap(String inputTraceFile) throws IOException {
        long clock = 0;
        
        try (BufferedReader reader = new BufferedReader(new FileReader(inputTraceFile))) {
            String line;
            while ((line = reader.readLine()) != null) {
                line = line.trim();
                
                if (line.isEmpty() || line.startsWith("#")) {
                    continue;
                }
                
                String[] parts = line.split("\\s+");
                if (parts.length == 0) continue;
                
                String recordType = parts[0];
                
                // Track logical clock (increments at M and E)
                if (recordType.equals("M") || recordType.equals("E")) {
                    clock++;
                }
                
                // Record witness times
                if (recordType.equals("W") && parts.length >= 2) {
                    int objectId = Integer.parseInt(parts[1]);
                    lastWitnessTime.put(objectId, clock);
                }
            }
        }
    }
    
    /**
     * PASS 2: Process trace with witness-aware death detection
     */
    private void processTraceWithWitnesses(String inputTraceFile, String outputTraceFile) throws IOException {
        String line;
        int lineNumber = 0;
        
        // Reset state for second pass
        this.logicalClock = 0;
        this.liveObjects.clear();
        this.objectGraph.clear();
        this.reverseGraph.clear();
        this.threadStacks.clear();
        this.staticRoots.clear();
        this.threadCallStacks.clear();
        this.deathRecords.clear();
        
        try (BufferedReader reader = new BufferedReader(new FileReader(inputTraceFile));
             PrintWriter writer = new PrintWriter(new BufferedWriter(new FileWriter(outputTraceFile)))) {
            
            outputWriter = writer;
            while ((line = reader.readLine()) != null) {
                lineNumber++;
                line = line.trim();
                
                if (line.isEmpty() || line.startsWith("#")) {
                    // Copy comments and empty lines to output
                    outputWriter.println(line);
                    continue;
                }
                
                // Write the original line to output
                outputWriter.println(line);
                
                // Process the trace record
                processTraceRecord(line);
                
                // Perform reachability analysis at method exits
                // Now witness-aware: won't mark objects dead if they have future witnesses
                if (line.startsWith("E ")) {
                    performReachabilityAnalysis();
                }
            }
            
            // Final reachability analysis
            performReachabilityAnalysis();
            
            // Write all death records
            writeDeathRecords();
        }
        
        if (verbose) {
            System.err.println("MerlinDeathTracker: Processed " + lineNumber + " trace records");
            System.err.println("MerlinDeathTracker: Generated " + deathRecords.size() + " death records");
        }
    }
    
    /**
     * Process a single trace record
     */
    private void processTraceRecord(String line) {
        String[] parts = line.split("\\s+");
        if (parts.length == 0) return;
        
        String recordType = parts[0];
        
        try {
            switch (recordType) {
                case "N": // Object allocation: N <object-id> <size> <type-id> <site-id> <length> <thread-id>
                    handleObjectAllocation(parts);
                    break;
                case "A": // Array allocation: A <object-id> <size> <type-id> <site-id> <length> <thread-id>
                    handleArrayAllocation(parts);
                    break;
                case "U": // Field update: U <obj-id> <new-tgt-obj-id> <field-id> <thread-id>
                    handleFieldUpdate(parts);
                    break;
                case "M": // Method entry: M <method-id> <receiver-object-id> <thread-id>
                    handleMethodEntry(parts);
                    break;
                case "E": // Method exit: E <method-id> <thread-id>
                    handleMethodExit(parts);
                    break;
                case "X": // Exception exit: X <method-id> <receiver-object-id> <exception-id> <thread-id>
                    handleExceptionExit(parts);
                    break;
                case "T": // Exception throw: T <method-id> <receiver-id> <exception-object-id> <thread-id>
                    handleExceptionThrow(parts);
                    break;
                case "H": // Exception handled: H <method-id> <receiver-id> <exception-object-id> <thread-id>
                    handleExceptionHandled(parts);
                    break;
                case "W": // Witness (getfield): W <object-id> <class-id> <thread-id>
                    handleWitness(parts);
                    break;
                case "I": // Initial heap allocation
                case "P": // Preexisting object
                case "V": // VM allocated object
                    handleSpecialAllocation(parts);
                    break;
                default:
                    if (verbose) {
                        System.err.println("Unknown record type: " + recordType);
                    }
            }
        } catch (Exception e) {
            if (verbose) {
                System.err.println("Error processing line: " + line);
                e.printStackTrace();
            }
        }
    }
    
    /**
     * Handle object allocation
     */
    private void handleObjectAllocation(String[] parts) {
        if (parts.length < 7) return;
        
        int objectId = Integer.parseInt(parts[1]);
        long size = Long.parseLong(parts[2]);
        int typeId = Integer.parseInt(parts[3]);
        int siteId = Integer.parseInt(parts[4]);
        long threadId = Long.parseLong(parts[6]);
        
        ObjectInfo obj = new ObjectInfo(objectId, typeId, siteId, size, threadId);
        liveObjects.put(objectId, obj);
        objectGraph.putIfAbsent(objectId, new HashSet<>());
        reverseGraph.putIfAbsent(objectId, new HashSet<>());
        
        // Add to current stack frame if one exists
        addToCurrentStackFrame(threadId, objectId);
    }
    
    /**
     * Handle array allocation
     */
    private void handleArrayAllocation(String[] parts) {
        if (parts.length < 7) return;
        
        int objectId = Integer.parseInt(parts[1]);
        long size = Long.parseLong(parts[2]);
        int typeId = Integer.parseInt(parts[3]);
        int siteId = Integer.parseInt(parts[4]);
        int length = Integer.parseInt(parts[5]);
        long threadId = Long.parseLong(parts[6]);
        
        ObjectInfo obj = new ObjectInfo(objectId, typeId, siteId, size, threadId);
        obj.isArray = true;
        obj.arrayLength = length;
        
        liveObjects.put(objectId, obj);
        objectGraph.putIfAbsent(objectId, new HashSet<>());
        reverseGraph.putIfAbsent(objectId, new HashSet<>());
        
        addToCurrentStackFrame(threadId, objectId);
    }
    
    /**
     * Handle field update: U <obj-id> <new-tgt-obj-id> <field-id> <thread-id>
     */
    private void handleFieldUpdate(String[] parts) {
        if (parts.length < 4) return;
        
        int sourceObjId = Integer.parseInt(parts[1]);
        int targetObjId = Integer.parseInt(parts[2]);
        // fieldId not currently used but parsed for completeness
        // int fieldId = Integer.parseInt(parts[3]);
        
        // If sourceObjId is 0, this is a static field update
        if (sourceObjId == 0) {
            if (targetObjId != 0) {
                staticRoots.add(targetObjId);
            }
            return;
        }
        
        // Update object graph
        if (targetObjId != 0) {
            objectGraph.computeIfAbsent(sourceObjId, k -> new HashSet<>()).add(targetObjId);
            reverseGraph.computeIfAbsent(targetObjId, k -> new HashSet<>()).add(sourceObjId);
        }
    }
    
    /**
     * Handle method entry: M <method-id> <receiver-object-id> <thread-id>
     */
    private void handleMethodEntry(String[] parts) {
        if (parts.length < 4) return;
        
        // Logical clock ticks at method entry (same as ETProxy)
        logicalClock++;
        
        int methodId = Integer.parseInt(parts[1]);
        int receiverObjId = Integer.parseInt(parts[2]);
        long threadId = Long.parseLong(parts[3]);
        
        Stack<MethodFrame> callStack = threadCallStacks.computeIfAbsent(threadId, k -> new Stack<>());
        MethodFrame frame = new MethodFrame(methodId, receiverObjId);
        
        // Add receiver to the frame's local objects
        if (receiverObjId != 0) {
            frame.localObjects.add(receiverObjId);
        }
        
        callStack.push(frame);
        
        // Update thread stacks
        threadStacks.computeIfAbsent(threadId, k -> new HashSet<>()).add(receiverObjId);
    }
    
    /**
     * Handle method exit: E <method-id> <thread-id>
     */
    private void handleMethodExit(String[] parts) {
        if (parts.length < 3) return;
        
        // Logical clock ticks at method exit (same as ETProxy)
        logicalClock++;
        
        long threadId = Long.parseLong(parts[2]);
        
        Stack<MethodFrame> callStack = threadCallStacks.get(threadId);
        if (callStack != null && !callStack.isEmpty()) {
            MethodFrame frame = callStack.pop();
            
            // Remove objects that were only referenced by this frame
            Set<Integer> threadStack = threadStacks.get(threadId);
            if (threadStack != null) {
                threadStack.removeAll(frame.localObjects);
            }
        }
    }
    
    /**
     * Handle exception exit
     */
    private void handleExceptionExit(String[] parts) {
        if (parts.length < 5) return;
        
        int exceptionObjId = Integer.parseInt(parts[3]);
        long threadId = Long.parseLong(parts[4]);
        
        handleMethodExit(new String[]{"E", parts[1], parts[4]});
        
        // Add exception object to current frame
        addToCurrentStackFrame(threadId, exceptionObjId);
    }
    
    /**
     * Handle exception throw
     */
    private void handleExceptionThrow(String[] parts) {
        if (parts.length < 5) return;
        
        int exceptionObjId = Integer.parseInt(parts[3]);
        long threadId = Long.parseLong(parts[4]);
        
        addToCurrentStackFrame(threadId, exceptionObjId);
    }
    
    /**
     * Handle exception handled
     */
    private void handleExceptionHandled(String[] parts) {
        if (parts.length < 5) return;
        
        int exceptionObjId = Integer.parseInt(parts[3]);
        long threadId = Long.parseLong(parts[4]);
        
        addToCurrentStackFrame(threadId, exceptionObjId);
    }
    
    /**
     * Handle witness records (getfield): W <object-id> <class-id> <thread-id>
     * Witness records show that an object was accessed (read), proving liveness
     */
    private void handleWitness(String[] parts) {
        if (parts.length < 4) return;
        
        int objectId = Integer.parseInt(parts[1]);
        // int classId = Integer.parseInt(parts[2]); // Not currently used
        long threadId = Long.parseLong(parts[3]);
        
        // If object is accessed, it's still alive - add to current stack frame
        // This reinforces reachability for objects being read
        addToCurrentStackFrame(threadId, objectId);
    }
    
    /**
     * Handle special allocations (I, P, V)
     */
    private void handleSpecialAllocation(String[] parts) {
        // Similar to regular allocation but may have different semantics
        if (parts.length < 7) return;
        handleObjectAllocation(parts);
    }
    
    /**
     * Add an object to the current stack frame
     */
    private void addToCurrentStackFrame(long threadId, int objectId) {
        if (objectId == 0) return;
        
        Stack<MethodFrame> callStack = threadCallStacks.get(threadId);
        if (callStack != null && !callStack.isEmpty()) {
            callStack.peek().localObjects.add(objectId);
        }
        
        threadStacks.computeIfAbsent(threadId, k -> new HashSet<>()).add(objectId);
    }
    
    /**
     * Perform reachability analysis using the Merlin algorithm
     * Objects that are not reachable from roots are considered dead
     * 
     * WITNESS-AWARE: Won't mark objects dead if they have future witness records
     */
    private void performReachabilityAnalysis() {
        Set<Integer> reachable = computeReachableObjects();
        
        // Find dead objects
        Set<Integer> deadObjects = new HashSet<>(liveObjects.keySet());
        deadObjects.removeAll(reachable);
        
        // Record deaths and remove from live set
        // Use current logical time as death timestamp
        for (int objectId : deadObjects) {
            ObjectInfo obj = liveObjects.get(objectId);
            if (obj != null) {
                // CHECK: Does this object have a future witness record?
                Long lastWitness = lastWitnessTime.get(objectId);
                if (lastWitness != null && lastWitness > logicalClock) {
                    // Object will be accessed in the future - DON'T mark it dead yet
                    if (verbose) {
                        System.err.println("Delaying death of object " + objectId + 
                                         " (current=" + logicalClock + ", last_witness=" + lastWitness + ")");
                    }
                    continue;
                }
                
                // Safe to mark as dead
                deathRecords.add(new DeathRecord(objectId, obj.threadId, logicalClock));
                liveObjects.remove(objectId);
                
                // Clean up graph structures
                objectGraph.remove(objectId);
                reverseGraph.remove(objectId);
                
                // Remove from other objects' reference lists
                for (Set<Integer> refs : objectGraph.values()) {
                    refs.remove(objectId);
                }
                for (Set<Integer> refs : reverseGraph.values()) {
                    refs.remove(objectId);
                }
            }
        }
    }
    
    /**
     * Compute the set of reachable objects from all roots
     * using breadth-first search
     */
    private Set<Integer> computeReachableObjects() {
        Set<Integer> reachable = new HashSet<>();
        Queue<Integer> worklist = new LinkedList<>();
        
        // Add all root objects to worklist
        // 1. Static roots
        for (int objId : staticRoots) {
            if (liveObjects.containsKey(objId)) {
                reachable.add(objId);
                worklist.add(objId);
            }
        }
        
        // 2. Stack roots (objects on any thread's stack)
        for (Set<Integer> stackObjects : threadStacks.values()) {
            for (int objId : stackObjects) {
                if (objId != 0 && liveObjects.containsKey(objId) && !reachable.contains(objId)) {
                    reachable.add(objId);
                    worklist.add(objId);
                }
            }
        }
        
        // Perform BFS to find all reachable objects
        while (!worklist.isEmpty()) {
            int currentObjId = worklist.poll();
            Set<Integer> references = objectGraph.get(currentObjId);
            
            if (references != null) {
                for (int refObjId : references) {
                    if (liveObjects.containsKey(refObjId) && !reachable.contains(refObjId)) {
                        reachable.add(refObjId);
                        worklist.add(refObjId);
                    }
                }
            }
        }
        
        return reachable;
    }
    
    /**
     * Write all death records to the output
     */
    private void writeDeathRecords() {
        for (DeathRecord record : deathRecords) {
            outputWriter.println(record.toString());
        }
    }
    
    /**
     * Main method for standalone usage
     */
    public static void main(String[] args) {
        if (args.length < 2) {
            System.err.println("Usage: MerlinDeathTracker <input-trace-file> <output-trace-file> [--verbose]");
            System.exit(1);
        }
        
        String inputFile = args[0];
        String outputFile = args[1];
        boolean verbose = args.length > 2 && args[2].equals("--verbose");
        
        try {
            MerlinDeathTracker tracker = new MerlinDeathTracker(verbose);
            tracker.processTrace(inputFile, outputFile);
            System.out.println("Death tracking complete. Output written to: " + outputFile);
        } catch (IOException e) {
            System.err.println("Error processing trace: " + e.getMessage());
            e.printStackTrace();
            System.exit(1);
        }
    }
}
