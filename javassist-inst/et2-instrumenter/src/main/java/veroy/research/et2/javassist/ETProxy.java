package veroy.research.et2.javassist;

import java.lang.Thread;
import java.lang.instrument.Instrumentation;
import java.lang.reflect.Array;
import java.util.concurrent.atomic.AtomicInteger;
import java.io.PrintWriter;
import java.util.concurrent.locks.ReentrantLock;
// TODO: import org.apache.log4j.Logger;


public class ETProxy {
    
    public static PrintWriter traceWriter = null;
    public static Instrumentation inst;

    // Thread local boolean w/ default value false
    private static final InstrumentFlag inInstrumentMethod = new InstrumentFlag();
    private static ReentrantLock mx = new ReentrantLock();
    private static volatile boolean isShuttingDown = false;

    // TODO: private static Logger et2Logger = Logger.getLogger(ETProxy.class);

    // Buffers:
    private static final int BUFMAX = 10000;
    private static int[] eventTypeBuffer = new int[BUFMAX+1];
    private static int[] firstBuffer = new int[BUFMAX+1];
    private static int[] secondBuffer = new int[BUFMAX+1];
    private static int[] thirdBuffer = new int[BUFMAX+1];
    private static long[] fourthBuffer = new long[BUFMAX+1];
    private static int[] fifthBuffer = new int[BUFMAX+1];

    private static long[] timestampBuffer = new long[BUFMAX];
    private static long[] threadIDBuffer = new long[BUFMAX];

    private static AtomicInteger ptr = new AtomicInteger();
    
    // Logical clock: increments at method entry/exit 
    private static AtomicInteger logicalClock = new AtomicInteger(0);
    
    /**
     * Get current logical time (for Merlin death timestamps)
     */
    public static long getLogicalTime() {
        return logicalClock.get();
    }
    /*


    // TRACING EVENTS
    // Method entry = 1,
    // method exit = 2,
    // object allocation = 3
    // object array allocation = 4
    // 2D array allocation = 6,
    // put field = 7
    // get field = 8

    private static PrintWriter traceWriter;


    static {
        try {
            traceWriter = new PrintWriter("trace");
        } catch (Exception e) {
            System.err.println("FNF");
        }
    }

    */

    
    // I hope no one ever creates a 2 gigabyte object
    // TODO: private static native int getObjectSize(Object obj);
    
    public static void debugCall(String message) {
        System.err.println("XXX: " + message);
    }

    public static void onEntry(int methodId, Object receiver) {
        // Logical clock ticks at method entry
        long timestamp = logicalClock.incrementAndGet();
        if (inInstrumentMethod.get()) {
            return;
        } else {
            inInstrumentMethod.set(true);
        }
        
        int receiverHash = (receiver == null) ? 0 : System.identityHashCode(receiver);
        long threadId = System.identityHashCode(Thread.currentThread());
        
        mx.lock();
        try {
            synchronized(ptr) {
                if (ptr.get() >= BUFMAX) {
                    flushBuffer();
                    assert(ptr.get() == 0);
                }
                // wait on ptr to prevent overflow
                int currPtr = ptr.getAndIncrement();
                firstBuffer[currPtr] = methodId;
                secondBuffer[currPtr] = receiverHash;
                eventTypeBuffer[currPtr] = 1; // TODO: Make into constants.
                timestampBuffer[currPtr] = timestamp; // TODO: Not really useful
                threadIDBuffer[currPtr] = threadId;
            }
            
            // Merlin: Track method entry for reachability analysis
            MerlinTracker.onMethodEntry(methodId, receiverHash, threadId);
        } finally {
            mx.unlock();
        }
        inInstrumentMethod.set(false);
    }

    public static void onExit(int methodId)
    {
        // Logical clock ticks at method exit
        long timestamp = logicalClock.incrementAndGet();
        if (inInstrumentMethod.get()) {
            return;
        } else {
            inInstrumentMethod.set(true);
        }
        
        long threadId = System.identityHashCode(Thread.currentThread());
        
        mx.lock();
        try {
            synchronized(ptr) {
                if (ptr.get() >= BUFMAX) {
                    flushBuffer();
                    assert(ptr.get() == 0);
                }
                int currPtr = ptr.getAndIncrement();
                firstBuffer[currPtr] = methodId;
                eventTypeBuffer[currPtr] = 2;
                timestampBuffer[currPtr] = timestamp;
                threadIDBuffer[currPtr] = threadId;
            }
            
            // CRITICAL: Flush buffer BEFORE detecting deaths
            // This ensures E record is written before D records
            flushBuffer();
            
            // Merlin: Track method exit and check for deaths
            // Deaths are detected at method boundaries for accuracy
            java.util.List<MerlinTracker.DeathRecord> deaths = MerlinTracker.onMethodExit(methodId, threadId);
            
            // Write death records immediately after the method exit
            if (!isShuttingDown && traceWriter != null) {
                for (MerlinTracker.DeathRecord death : deaths) {
                    traceWriter.println(death.toString());
                }
            }
        } finally {
            mx.unlock();
        }
        inInstrumentMethod.set(false);
    }

    public static void onObjectAlloc(Object obj, int allocdClassID, int allocSiteID) {
        // Use current logical time (no tick for allocation)
        long timestamp = logicalClock.get();
        if (inInstrumentMethod.get()) {
            return;
        } else {
            inInstrumentMethod.set(true);
        }
        
        int objectId = System.identityHashCode(obj);
        long threadId = System.identityHashCode(Thread.currentThread());
        
        mx.lock();
        try {
            synchronized(ptr) {
                if (ptr.get() >= BUFMAX) {
                    flushBuffer();
                    assert(ptr.get() == 0);
                }
                int currPtr = ptr.getAndIncrement();
                firstBuffer[currPtr] = objectId;
                eventTypeBuffer[currPtr] = 3; // TODO: Create a constant for this.
                secondBuffer[currPtr] = allocdClassID;
                thirdBuffer[currPtr] = allocSiteID;
                fourthBuffer[currPtr] = inst.getObjectSize(obj);
                timestampBuffer[currPtr] = timestamp;
                threadIDBuffer[currPtr] = threadId;
            }
            
            // Merlin: Track object allocation
            MerlinTracker.onObjectAlloc(objectId, threadId, timestamp);
        } finally {
            mx.unlock();
        }
        inInstrumentMethod.set(false);
    }
            
    // ET1 looked like this:
    //       U <old-target> <object> <new-target> <field> <thread>
    // ET2/ET3 format:
    //       U  <source-obj-id> <target-obj-id> <field-id> <thread-id>
    // For assignment: receiver.field = value
    //       U  <receiver-id> <value-id> <field-id> <thread-id>
    public static void onPutField(Object receiver, Object value, int fieldId)
    {
        // Use current logical time (no tick for field update)
        long timestamp = logicalClock.get();
        if (inInstrumentMethod.get()) {
            return;
        } else {
            inInstrumentMethod.set(true);
        }
        
        int receiverId = System.identityHashCode(receiver);
        int valueId = (value == null) ? 0 : System.identityHashCode(value);
        long threadId = System.identityHashCode(Thread.currentThread());
        
        mx.lock();
        try {
            synchronized(ptr) {
                if (ptr.get() >= BUFMAX) {
                    flushBuffer();
                    assert(ptr.get() == 0);
                } else {
                    int currPtr = ptr.getAndIncrement();
                    eventTypeBuffer[currPtr] = 7;
                    firstBuffer[currPtr] = receiverId;    // Object with the field
                    secondBuffer[currPtr] = fieldId;       // Field ID
                    thirdBuffer[currPtr] = valueId;        // Value being assigned
                    timestampBuffer[currPtr] = timestamp;
                    threadIDBuffer[currPtr] = threadId;
                }
            }
            
            // Merlin: Track field update for object graph (receiver -> value edge)
            MerlinTracker.onFieldUpdate(receiverId, valueId, threadId);
        } finally {
            mx.unlock();
        }
        inInstrumentMethod.set(false);
    }

    public static void onArrayAlloc( Object arrayObj,
                                     int typeId,
                                     int allocSiteId )
    {
        // Use current logical time (no tick for array allocation)
        long timestamp = logicalClock.get();
        if (inInstrumentMethod.get()) {
            return;
        } else {
            inInstrumentMethod.set(true);
        }
        
        int objectId = System.identityHashCode(arrayObj);
        long threadId = System.identityHashCode(Thread.currentThread());

        mx.lock();
        try {
            synchronized(ptr) {
                if (ptr.get() >= BUFMAX) {
                    flushBuffer();
                    assert(ptr.get() == 0);
                } else {
                    int currPtr = ptr.getAndIncrement();
                    eventTypeBuffer[currPtr] = 4;
                    firstBuffer[currPtr] = objectId;
                    secondBuffer[currPtr] = typeId;
                    try {
                        thirdBuffer[currPtr] = Array.getLength(arrayObj);
                    } catch (IllegalArgumentException exc) {
                        thirdBuffer[currPtr] = 0;
                    }
                    fourthBuffer[currPtr] = inst.getObjectSize(arrayObj);
                    fifthBuffer[currPtr] = allocSiteId;
                    timestampBuffer[currPtr] = timestamp;
                    threadIDBuffer[currPtr] = threadId;
                }
            }
            
            // Merlin: Track array allocation
            MerlinTracker.onObjectAlloc(objectId, threadId, timestamp);
        } finally {
            mx.unlock();
        }
        inInstrumentMethod.set(false);
    }

    /*
    public static void onMultiArrayAlloc( int dims,
                                          int allocdClassID,
                                          Object[] allocdArray,
                                          int allocSiteID )
    {
        if (!atMain) {
            return;
        }
        
        // Use current logical time (no tick for allocation)
        long timestamp = logicalClock.get();
        
        // TODO: if (inInstrumentMethod.get()) {
        // TODO:     return;
        // TODO: } else {
        // TODO:     inInstrumentMethod.set(true);
        // TODO: }

        mx.lock();

        try {
            while (true) {
                if (ptr.get() < BUFMAX) {
                    // wait on ptr to prevent overflow
                    int currPtr;
                    synchronized(ptr) {
                        currPtr = ptr.getAndIncrement();
                    }
                    firstBuffer[currPtr] = System.identityHashCode(allocdArray);
                    eventTypeBuffer[currPtr] = 6;
                    secondBuffer[currPtr] = allocdClassID;
                    thirdBuffer[currPtr] = allocdArray.length;
                    // TODO: fourthBuffer[currPtr] = allocSiteID;
                    fifthBuffer[currPtr] = getObjectSize(allocdArray);
                    timestampBuffer[currPtr] = timestamp;
                    threadIDBuffer[currPtr] = System.identityHashCode(Thread.currentThread());

                    if (dims > 2) {
                        for (int i = 0; i < allocdArray.length; ++i) {
                            onMultiArrayAlloc(dims - 1, allocdClassID, (Object[]) allocdArray[i], allocSiteID);
                        }
                    } else { // dims == 2
                        for (int i = 0; i < allocdArray.length; ++i) {
                            onArrayAlloc(allocdClassID, 0, allocdArray[i], allocSiteID);
                        }
                    }
                    break;
                } else {
                    synchronized(ptr) {
                        if (ptr.get() >= BUFMAX) {
                            flushBuffer();
                        }
                    }
                }
            }
        } finally {
            mx.unlock();
        }
        
        // TODO: inInstrumentMethod.set(false);
    }

    public static void witnessObjectAlive( Object aliveObject,
                                           int classID )
    {
        if (!atMain) {
            return;
        }
        
        // Use current logical time (no tick for witness)
        long timestamp = logicalClock.get();
        
        // TODO: if (inInstrumentMethod.get()) {
        // TODO:     return;
        // TODO: } else {
        // TODO:     inInstrumentMethod.set(true);
        // TODO: }

        mx.lock();

        try {
            while (true) {
                if (ptr.get() < BUFMAX) {
                    // wait on ptr to prevent overflow
                    int currPtr;
                    synchronized(ptr) {
                        currPtr = ptr.getAndIncrement();
                    }

                    // System.err.println("Seems like problem is here...");
                    // System.err.println("Class being instrumented here (ID): " + classID);

                    firstBuffer[currPtr] = System.identityHashCode(aliveObject);

                    // System.err.println("gets here");
                    eventTypeBuffer[currPtr] = 8;
                    secondBuffer[currPtr] = classID;
                    timestampBuffer[currPtr] = timestamp;

                    threadIDBuffer[currPtr] = System.identityHashCode(Thread.currentThread());
                    break;
                } else {
                    synchronized(ptr) {
                        if (ptr.get() >= BUFMAX) {
                            flushBuffer();
                        }
                    }
                }
            }
        } finally {
            mx.unlock();
        }
        
        // TODO: inInstrumentMethod.set(false);
    }
    
    public static void onInvokeMethod(Object allocdObject, int allocdClassID, int allocSiteID)
    {
        if (!atMain) {
            return;
        }
        // Use current logical time (no tick for invoke)
        long timestamp = logicalClock.get();
        // TODO: if (inInstrumentMethod.get()) {
        // TODO:     return;
        // TODO: } else {
        // TODO:     inInstrumentMethod.set(true);
        // TODO: }
        mx.lock();
        try {
            while (true) {
                if (ptr.get() < BUFMAX) {
                    // wait on ptr to prevent overflow
                    int currPtr;
                    synchronized(ptr) {
                        currPtr = ptr.getAndIncrement();
                    }
                    firstBuffer[currPtr] = System.identityHashCode(allocdObject);
                    eventTypeBuffer[currPtr] = 3;
                    secondBuffer[currPtr] = allocdClassID;
                    thirdBuffer[currPtr] = allocSiteID;
                    // I hope no one ever wants a 2 gigabyte (shallow size!) object
                    // some problem here...
                    // System.err.println("Class ID: " + allocdClassID);
                    fourthBuffer[currPtr] = (int) getObjectSize(allocdObject);
                    timestampBuffer[currPtr] = timestamp;
                    threadIDBuffer[currPtr] = System.identityHashCode(Thread.currentThread());
                    break;
                } else {
                    synchronized(ptr) {
                        if (ptr.get() >= BUFMAX) {
                            flushBuffer();
                        }
                    }
                }
            }
        } finally {
            mx.unlock();
        }
        // TODO: inInstrumentMethod.set(false);
    }
    */

    public static void flushBuffer()
    {
        if (isShuttingDown || traceWriter == null) {
            return;
        }
        try {
            mx.lock();
            int bufSize = ptr.get();
            
            for (int i = 0; i < bufSize; i++) {
                switch (eventTypeBuffer[i]) {
                    case 1: // method entry
                        // M <method-id> <receiver-object-id> <thread-id>
                        traceWriter.println( "M " +
                                    firstBuffer[i] + " " +
                                    secondBuffer[i] + " " +
                                    threadIDBuffer[i] );
                        // TODO: et2Logger.info( "M " +
                        // TODO:                 firstBuffer[i] + " " +
                        // TODO:                 secondBuffer[i] + " " +
                        // TODO:                 threadIDBuffer[i] );
                        break;
                    case 2: // method exit
                        // E <method-id> <thread-id>
                        traceWriter.println( "E " +
                                    firstBuffer[i] + " " +
                                    threadIDBuffer[i] );
                        break;
                    case 3: // object allocation
                        // N <object-id> <size> <type-id> <site-id> <length (0)> <thread-id>
                        // 1st buffer = object ID (hash)
                        // 2nd buffer = class ID
                        // 3rd buffer = allocation site (method ID)
                        traceWriter.println( "N " +
                                    firstBuffer[i] + " " +
                                    fourthBuffer[i] + " " +
                                    secondBuffer[i] + " " +
                                    thirdBuffer[i] + " "
                                    + 0 + " " // Always zero because this isn't an array.
                                    + threadIDBuffer[i] );
                        break;
                    case 4: // object array allocation
                    case 5: // primitive array allocation
                        // 5 now removed so nothing should come out of it
                        // A <object-id> <size> <type-id> <site-id> <length> <thread-id>
                        traceWriter.println( "A " +
                                    firstBuffer[i] + " " + // objectId
                                    fourthBuffer[i] + " " + // size
                                    secondBuffer[i] + " " + // typedId
                                    fifthBuffer[i] + " " + // siteId
                                    thirdBuffer[i] + " " + // length
                                    threadIDBuffer[i] ); // threadId
                        break;
                    case 6: // 2D array allocation
                        // TODO: Conflicting documention: 2018-1112
                        // 6, arrayHash, arrayClassID, size1, size2, timestamp
                        // A <object-id> <size> <type-id> <site-id> <length> <thread-id>
                        traceWriter.println( "A " +
                                    firstBuffer[i] + " " +
                                    fifthBuffer[i] + " " +
                                    secondBuffer[i] + " " +
                                    fourthBuffer[i] + " " +
                                    thirdBuffer[i] + " " +
                                    threadIDBuffer[i] );
                        break;
                    case 7: // object update
                        // U <receiver-id> <value-id> <field-id> <thread-id>
                        // For: receiver.field = value
                        traceWriter.println( "U " +
                                    firstBuffer[i] + " " +  // receiver (object with field)
                                    thirdBuffer[i] + " " +  // value (being assigned)
                                    secondBuffer[i] + " " +  // fieldId
                                    threadIDBuffer[i] );     // threadId
                        break;
                    case 8: // witness with get field
                        // 8, aliveObjectHash, classID, timestamp
                        traceWriter.println( "W" + " " +
                                    firstBuffer[i] + " " +
                                    secondBuffer[i] + " " +
                                    threadIDBuffer[i] );
                        break;
                    default:
                        throw new IllegalStateException("Unexpected event: " + eventTypeBuffer[i]);
                }
            }
            ptr.set(0);
            traceWriter.flush();
        } finally {
            mx.unlock();
        }
    }
    
    /**
     * Shutdown hook to finalize trace and write remaining death records
     */
    public static void onShutdown() {
        try {
            mx.lock();
            
            System.err.println("ET3 shutting down, finalizing trace...");
            
            // Flush any remaining buffered events BEFORE setting shutdown flag
            flushBuffer();
            
            // Now set shutdown flag to prevent further writes
            isShuttingDown = true;
            
            // Merlin: Final death detection for all remaining objects
            // This may be slow for large benchmarks
            long startTime = System.currentTimeMillis();
            java.util.List<MerlinTracker.DeathRecord> deaths = MerlinTracker.onShutdown();
            long elapsed = System.currentTimeMillis() - startTime;
            
            System.err.println("Merlin final analysis: " + deaths.size() + " deaths in " + elapsed + "ms");
            
            // Write final death records
            for (MerlinTracker.DeathRecord death : deaths) {
                traceWriter.println(death.toString());
            }
            
            // Close trace writer
            if (traceWriter != null) {
                traceWriter.flush();
                traceWriter.close();
            }
            
            System.err.println("ET3 trace complete with Merlin death tracking");
        } catch (Exception e) {
            System.err.println("Error during ET3 shutdown: " + e.getMessage());
            e.printStackTrace();
        } finally {
            try {
                mx.unlock();
            } catch (Exception e) {
                // Ignore unlock errors during shutdown
            }
        }
    }
    
}
