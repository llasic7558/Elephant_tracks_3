#!/bin/bash
# Convert ET3 metadata format to ET2 simulator format
# Usage: ./convert_metadata.sh <trace_directory>

if [ $# -eq 0 ]; then
    echo "Usage: $0 <trace_directory>"
    echo "Example: $0 test_traces_online/HelloWorld"
    exit 1
fi

TRACE_DIR=$1

if [ ! -d "$TRACE_DIR" ]; then
    echo "Error: Directory $TRACE_DIR does not exist"
    exit 1
fi

if [ ! -f "$TRACE_DIR/classs.list" ] || [ ! -f "$TRACE_DIR/fields.list" ] || [ ! -f "$TRACE_DIR/methods.list" ]; then
    echo "Error: Missing metadata files in $TRACE_DIR"
    echo "Required files: classs.list, fields.list, methods.list"
    exit 1
fi

echo "Converting metadata files in $TRACE_DIR..."

# Convert classes: "ClassName,ID" -> "ID ClassName"
cat "$TRACE_DIR/classs.list" | grep -v '^$' | awk -F',' '{print $2, $1}' > "$TRACE_DIR/classes.txt"
echo "  ✓ Created classes.txt ($(wc -l < "$TRACE_DIR/classes.txt") entries)"

# Convert fields: "ClassName#fieldName,ID" -> "ID ClassName fieldName"
cat "$TRACE_DIR/fields.list" | grep -v '^$' | awk -F',' '{
    split($1, parts, "#");
    print $2, parts[1], parts[2]
}' > "$TRACE_DIR/fields.txt"
echo "  ✓ Created fields.txt ($(wc -l < "$TRACE_DIR/fields.txt") entries)"

# Convert methods: "ClassName#methodName,ID" -> "ID ClassName methodName"
cat "$TRACE_DIR/methods.list" | grep -v '^$' | awk -F',' '{
    split($1, parts, "#");
    print $2, parts[1], parts[2]
}' > "$TRACE_DIR/methods.txt"
echo "  ✓ Created methods.txt ($(wc -l < "$TRACE_DIR/methods.txt") entries)"

echo "Conversion complete!"
echo ""
echo "To run the simulator, use:"
echo "  cat $TRACE_DIR/trace | simulator/build/simulator SIM \\"
echo "    $TRACE_DIR/classes.txt \\"
echo "    $TRACE_DIR/fields.txt \\"
echo "    $TRACE_DIR/methods.txt \\"
echo "    output_$(basename $TRACE_DIR) \\"
echo "    NOCYCLE NOOBJDEBUG \\"
echo "    MainClassName main"
