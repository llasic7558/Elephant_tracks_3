# Field Updates (U Records) and LotsOfAllocs Analysis

## Why Were U Records Missing?

### The Problem

Originally, we saw **0 U records** in traces despite field instrumentation code existing.

### Root Causes

1. **Silent Exception Swallowing**
   ```java
   // OLD CODE
   } catch (NotFoundException exc) {
       // EMPTY CATCH - silently fails!
   }
   ```

2. **Wrong Class Name**
   ```java
   // Used className of instrumenting class, not field's declaring class
   getFieldId(className, fieldName)  // WRONG if field from different class
   ```

3. **Primitive Fields Were Included**
   - U records are only for **object references**
   - Was trying to instrument `int x`, `float y` (primitives)
   - Should only instrument `FooClass next` (object reference)

4. **Parameter Order**
   - Call was `onPutField($1, $0, fieldId)` where $1=value, $0=this
   - But record output was backwards

### The Fix

```java
// NEW CODE - MethodInstrumenter.java
public void edit(FieldAccess expr) throws CannotCompileException {
    try {
        final String fieldName = expr.getField().getName();
        final String fieldClassName = expr.getField().getDeclaringClass().getName(); // ✅ Use field's class
        if (expr.isWriter()) {
            try {
                CtClass fieldType = expr.getField().getType();
                if (!fieldType.isPrimitive()) {  // ✅ Only instrument object refs
                    int fieldId = getFieldId(fieldClassName, fieldName);
                    expr.replace( "{ veroy.research.et2.javassist.ETProxy.onPutField($0, $1, " + fieldId + "); $_ = $proceed($$); }" );
                    // ✅ $0=receiver, $1=value
                }
            } catch (NotFoundException typeExc) {
                System.err.println("Warning: Could not get type for field " + fieldClassName + "#" + fieldName);
                // ✅ Diagnostic output instead of silent failure
            }
        }
    } catch (NotFoundException exc) {
        System.err.println("Warning: Field not found during instrumentation: " + exc.getMessage());
    }
}
```

```java
// ETProxy.java - Fixed parameter names and output
public static void onPutField(Object receiver, Object value, int fieldId) {
    int receiverId = System.identityHashCode(receiver);
    int valueId = (value == null) ? 0 : System.identityHashCode(value);  // ✅ Handle null
    
    // Buffer: receiver, fieldId, value
    firstBuffer[currPtr] = receiverId;   // Object with the field
    secondBuffer[currPtr] = fieldId;     // Field ID
    thirdBuffer[currPtr] = valueId;      // Value being assigned
    
    // Output: U <receiver> <value> <fieldId> <threadId>
    traceWriter.println("U " + 
                        firstBuffer[i] + " " +   // receiver
                        thirdBuffer[i] + " " +   // value
                        secondBuffer[i] + " " +  // fieldId
                        threadIDBuffer[i]);
}
```

### Results

**Before:**
```
Total U records: 0
FooClass fields: x (only primitive listed)
```

**After:**
```
Total U records: 1004
FooClass fields: next,15 (object reference)
U 739498517 0 15 1950409828  ← receiver.next = null
U 125130493 0 15 1950409828
...
```

---

## LotsOfAllocs Analysis: Why Do Objects Die Immediately?

### The Code

```java
class LotsOfAllocs {
    private static final int TOTAL = 1000;

    public static void main(String args[]) {
        FooClass lastFoo = null;           // ← Initialized to null
        for (int i = 0; i < TOTAL; i++) {
            FooClass foo = new FooClass(); // ← Local variable
            foo.setNext(lastFoo);          // ← Sets foo.next = null
            // ← BUG: lastFoo is NEVER updated!
        }
        // ← Loop ends, all objects died
    }
}
```

### The Bug

**`lastFoo` is never updated!**

The code should be:
```java
for (int i = 0; i < TOTAL; i++) {
    FooClass foo = new FooClass();
    foo.setNext(lastFoo);
    lastFoo = foo;  // ← MISSING! Should build linked list
}
```

### What Actually Happens

#### Iteration 0:
```
1. N 1234 ... (foo0 allocated)
2. M setNext (enter setNext method)
3. U 1234 0 15 ... (foo0.next = null, because lastFoo is null)
4. E setNext (exit setNext)
5. (end of iteration, foo0 goes out of scope)
6. E loop (method exit boundary)
7. D 1234 ... (foo0 dies! No references)
```

#### Iteration 1:
```
1. N 5678 ... (foo1 allocated)
2. M setNext
3. U 5678 0 15 ... (foo1.next = null, because lastFoo STILL null!)
4. E setNext
5. (foo1 goes out of scope)
6. E loop
7. D 5678 ... (foo1 dies! No references)
```

### Why Objects Die Immediately

**Reachability Analysis:**

```
Stack:
  main():
    lastFoo = null  ← No reference to any FooClass!
    foo = ???       ← Out of scope after iteration

Heap:
  Object 1234: { next = null }  ← No incoming references!
  Object 5678: { next = null }  ← No incoming references!
  ...
```

At each method exit:
1. **Roots**: Only `lastFoo` (null) and `foo` (out of scope)
2. **Reachable**: Nothing
3. **Dead**: All allocated FooClass objects

### The Trace Confirms This

```
=== Object Lifecycle ===
N 1068824137 32 27 136 0 1950409828    ← Object allocated (logical time 136)
U 1068824137 0 15 1950409828           ← foo.next = null
D 1068824137 1950409828 383            ← Object died (logical time 383)

Time difference: 383 - 136 = 247 logical time units
≈ 247 method entries/exits (very short lifetime!)
```

### Expected Behavior (If Fixed)

```java
// FIXED CODE
FooClass lastFoo = null;
for (int i = 0; i < TOTAL; i++) {
    FooClass foo = new FooClass();
    foo.setNext(lastFoo);
    lastFoo = foo;  // ✅ BUILD LINKED LIST
}
// Now lastFoo points to foo999
// foo999.next → foo998 → foo997 → ... → foo0 → null
// ALL 1000 objects are reachable through lastFoo!
```

**With fix, deaths would be:**
```
E main (method exit, lastFoo goes out of scope)
D foo999 (unreachable)
D foo998 (unreachable)
...
D foo0 (unreachable)
```

All 1000 objects would die at program end, not during the loop!

---

## Answer to Original Question

> "Why does var1 die despite being referenced by all objects in the loop?"

**ANSWER: It's NOT referenced by other objects!**

1. **No linked list is built** - `lastFoo` is never updated
2. **Each object's `next` field is null** - because `lastFoo` is always null
3. **Objects don't reference each other** - they all have `next = null`
4. **Each object dies immediately** - no stack or heap references

### The Trace Shows This Clearly

```bash
# All U records show: object.next = 0 (null)
$ grep "^U.*15" trace | head -5
U 739498517 0 15 1950409828  ← .next = null
U 125130493 0 15 1950409828  ← .next = null
U 914504136 0 15 1950409828  ← .next = null
U 166239592 0 15 1950409828  ← .next = null
U 991505714 0 15 1950409828  ← .next = null
```

**Every single U record has value=0 (null)!**

### Merlin is Correct

✅ **Objects die immediately** - they are truly unreachable  
✅ **Death timing makes sense** - at method exit boundaries  
✅ **No false positives** - Merlin correctly identifies unreachable objects  

The "surprising" behavior is actually correct! The test code has a bug.

---

## U Record Format

### Correct Format

```
U <receiver-id> <value-id> <field-id> <thread-id>
```

For assignment: `receiver.field = value`

### Example

```java
foo.next = bar;  // foo=1234, bar=5678, next=field 15

U 1234 5678 15 1950409828
  │    │    │
  │    │    └─ Field ID (next)
  │    └────── Value being assigned (bar)
  └─────────── Receiver object (foo)
```

### Null References

```java
foo.next = null;  // foo=1234, null=0, next=15

U 1234 0 15 1950409828
       │
       └─ 0 represents null
```

---

## Witness Records (Case 8)

**Not currently used in ET3/Merlin.** These were for field *reads* (get field):

```
W <object-id> <class-id> <thread-id>
```

Could be added to track when objects are "witnessed alive" by field reads, but not necessary for Merlin's reachability analysis.

---

## Summary

### Fixed Issues:
✅ **U records now generated** - 1004 records for LotsOfAllocs  
✅ **Only object references tracked** - primitives excluded  
✅ **Correct field class used** - no more NotFoundException  
✅ **Proper parameter order** - receiver, value, fieldId  
✅ **Null handling** - value=0 for null references  

### LotsOfAllocs Behavior:
✅ **Objects die immediately** - this is CORRECT!  
✅ **No linked list built** - `lastFoo` never updated (bug in test)  
✅ **All `next` fields = null** - no inter-object references  
✅ **Merlin is working perfectly** - detecting truly unreachable objects  

The test code needs `lastFoo = foo;` to build an actual linked list.
