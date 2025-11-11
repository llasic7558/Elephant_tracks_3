package veroy.research.et2.javassist;

import java.util.*;
import java.util.concurrent.ConcurrentHashMap;

/**
 * Real-time Merlin Algorithm tracker integrated with ET3
 * Tracks object reachability and generates death records during trace generation
 */
public class MerlinTracker {
    
    // Track live objects and their metadata
    private static final Map<Integer, ObjectInfo> liveObjects = new ConcurrentHashMap<>();
    
    // Object graph: objectId -> Set of referenced object IDs
    private static final Map<Integer, Set<Integer>> objectGraph = new ConcurrentHashMap<>();
    
    // Reverse graph: objectId -> Set of objects that reference it
    private static final Map<Integer, Set<Integer>> reverseGraph = new ConcurrentHashMap<>();
    
    // Per-thread call stacks
    private static final Map<Long, Stack<MethodFrame>> threadStacks = new ConcurrentHashMap<>();
    
    // Static field roots
    private static final Set<Integer> staticRoots = Collections.newSetFromMap(new ConcurrentHashMap<>());
    
    // Death detection happens only at method exits (for accurate timing) and shutdown
    
    /**
     * Object metadata
     */
    @SuppressWarnings("unused") // Fields available for future enhancements
    private static class ObjectInfo {
        final int objectId;
        final long threadId;
        final long timestamp;
        
        ObjectInfo(int objectId, long threadId, long timestamp) {
            this.objectId = objectId;
            this.threadId = threadId;
            this.timestamp = timestamp;
        }
    }
    
    /**
     * Method frame on call stack
     */
    @SuppressWarnings("unused") // Fields available for debugging and analysis
    private static class MethodFrame {
        final int methodId;
        final int receiverObjectId;
        final Set<Integer> localObjects;
        
        MethodFrame(int methodId, int receiverObjectId) {
            this.methodId = methodId;
            this.receiverObjectId = receiverObjectId;
            this.localObjects = Collections.newSetFromMap(new ConcurrentHashMap<>());
            if (receiverObjectId != 0) {
                localObjects.add(receiverObjectId);
            }
        }
    }
    
    /**
     * Record object allocation
     */
    public static void onObjectAlloc(int objectId, long threadId, long timestamp) {
        liveObjects.put(objectId, new ObjectInfo(objectId, threadId, timestamp));
        objectGraph.putIfAbsent(objectId, Collections.newSetFromMap(new ConcurrentHashMap<>()));
        reverseGraph.putIfAbsent(objectId, Collections.newSetFromMap(new ConcurrentHashMap<>()));
        
        // Add to current stack frame if exists
        addToCurrentFrame(threadId, objectId);
    }
    
    /**
     * Record field update: source.field = target
     */
    public static void onFieldUpdate(int sourceObjId, int targetObjId, long threadId) {
        if (sourceObjId == 0) {
            // Static field update
            if (targetObjId != 0) {
                staticRoots.add(targetObjId);
            }
        } else {
            // Instance field update
            if (targetObjId != 0) {
                objectGraph.computeIfAbsent(sourceObjId, k -> Collections.newSetFromMap(new ConcurrentHashMap<>()))
                           .add(targetObjId);
                reverseGraph.computeIfAbsent(targetObjId, k -> Collections.newSetFromMap(new ConcurrentHashMap<>()))
                            .add(sourceObjId);
            }
        }
    }
    
    /**
     * Record method entry
     */
    public static void onMethodEntry(int methodId, int receiverObjId, long threadId) {
        Stack<MethodFrame> stack = threadStacks.computeIfAbsent(threadId, k -> new Stack<>());
        stack.push(new MethodFrame(methodId, receiverObjId));
    }
    
    /**
     * Record method exit - trigger death detection
     */
    public static List<DeathRecord> onMethodExit(int methodId, long threadId) {
        Stack<MethodFrame> stack = threadStacks.get(threadId);
        if (stack != null && !stack.isEmpty()) {
            stack.pop();
        }
        
        // Perform reachability analysis at method exit for accurate death timing
        // This is the primary death detection point per the Merlin algorithm
        return performReachabilityAnalysis();
    }
    
    /**
     * Add object to current stack frame
     */
    private static void addToCurrentFrame(long threadId, int objectId) {
        if (objectId == 0) return;
        
        Stack<MethodFrame> stack = threadStacks.get(threadId);
        if (stack != null && !stack.isEmpty()) {
            stack.peek().localObjects.add(objectId);
        }
    }
    
    /**
     * Perform reachability analysis and detect deaths
     * Returns list of death records to be written
     */
    public static synchronized List<DeathRecord> performReachabilityAnalysis() {
        List<DeathRecord> deaths = new ArrayList<>();
        
        // Compute reachable objects
        Set<Integer> reachable = computeReachableObjects();
        
        // Find dead objects
        Set<Integer> allLive = new HashSet<>(liveObjects.keySet());
        allLive.removeAll(reachable);
        
        // Generate death records and clean up
        long currentTime = System.nanoTime(); // Death time = method exit time
        for (int deadObjId : allLive) {
            ObjectInfo obj = liveObjects.remove(deadObjId);
            if (obj != null) {
                // Death timestamp = current time (when we detected it's unreachable)
                deaths.add(new DeathRecord(deadObjId, obj.threadId, currentTime));
                
                // Clean up graph structures
                objectGraph.remove(deadObjId);
                reverseGraph.remove(deadObjId);
                staticRoots.remove(deadObjId);
                
                // Remove from other objects' reference lists
                for (Set<Integer> refs : objectGraph.values()) {
                    refs.remove(deadObjId);
                }
                for (Set<Integer> refs : reverseGraph.values()) {
                    refs.remove(deadObjId);
                }
            }
        }
        
        return deaths;
    }
    
    /**
     * Compute set of reachable objects from all roots using BFS
     */
    private static Set<Integer> computeReachableObjects() {
        Set<Integer> reachable = new HashSet<>();
        Queue<Integer> worklist = new LinkedList<>();
        
        // Add static roots
        for (int objId : staticRoots) {
            if (liveObjects.containsKey(objId) && !reachable.contains(objId)) {
                reachable.add(objId);
                worklist.add(objId);
            }
        }
        
        // Add stack roots from all threads
        for (Stack<MethodFrame> stack : threadStacks.values()) {
            for (MethodFrame frame : stack) {
                for (int objId : frame.localObjects) {
                    if (objId != 0 && liveObjects.containsKey(objId) && !reachable.contains(objId)) {
                        reachable.add(objId);
                        worklist.add(objId);
                    }
                }
            }
        }
        
        // BFS traversal through object graph
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
     * Final cleanup - detect all remaining deaths at program end
     */
    public static List<DeathRecord> onShutdown() {
        // Clear all stacks - everything goes out of scope
        threadStacks.clear();
        staticRoots.clear();
        
        // All remaining objects are now dead
        List<DeathRecord> deaths = new ArrayList<>();
        long shutdownTime = System.nanoTime(); // Program end time
        for (ObjectInfo obj : liveObjects.values()) {
            deaths.add(new DeathRecord(obj.objectId, obj.threadId, shutdownTime));
        }
        
        liveObjects.clear();
        objectGraph.clear();
        reverseGraph.clear();
        
        return deaths;
    }
    
    /**
     * Death record
     */
    public static class DeathRecord {
        public final int objectId;
        public final long threadId;
        public final long timestamp; // Time of death (last time alive)
        
        public DeathRecord(int objectId, long threadId, long timestamp) {
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
     * Get statistics
     */
    public static String getStatistics() {
        return String.format("Merlin: %d live objects, %d static roots, %d threads",
                           liveObjects.size(), staticRoots.size(), threadStacks.size());
    }
}
