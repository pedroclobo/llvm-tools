#!/bin/bash

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Default output file
OUTPUT_FILE="reduced.ll"
VERBOSE=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -o|--output)
            OUTPUT_FILE="$2"
            shift 2
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        *)
            break
            ;;
    esac
done

# Get the command from arguments
[ $# -eq 0 ] && echo -e "${RED}Usage: $0 [-o|--output output_file] [-v|--verbose] <compile command>${NC}" && exit 1

# Generate unique timestamp for intermediate files
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
UNOPTIMIZED_IR="unoptimized_${TIMESTAMP}.ll"
BEFORE_CRASH_RAW="before-crash-raw_${TIMESTAMP}.ll"
BEFORE_CRASH="before-crash_${TIMESTAMP}.ll"
REDUCE_TEST="reduce_test_${TIMESTAMP}.sh"

# Reconstruct the full command
COMMAND="$*"

# Extract the compiler path and the source file
COMPILER_PATH=$(echo "$COMMAND" | awk '{print $1}')
COMPILER_DIR=$(dirname "$COMPILER_PATH")
SOURCE_FILE=$(echo "$COMMAND" | grep -oE '[^ ]+\.(c|cpp)\>' | tail -n 1)

# Extract all compiler flags (everything between compiler and source file)
FLAGS=$(echo "$COMMAND" | sed "s|$COMPILER_PATH||" | sed "s|$SOURCE_FILE||")

# Set up output redirection based on verbose mode
if [ "$VERBOSE" = true ]; then
    REDIRECT=""
else
    REDIRECT=">/dev/null 2>&1"
fi

echo -e "${BLUE}Step 1: Verifying crash...${NC}"
if ! eval "$COMMAND" $REDIRECT; then
    echo -e "${GREEN}Confirmed: Command crashes as expected${NC}"
else
    echo -e "${RED}Error: Command did not crash${NC}"
    exit 1
fi

echo -e "${BLUE}Step 2: Extracting unoptimized IR...${NC}"
# Generate unoptimized IR while preserving optimization flags
eval "$COMPILER_PATH" $FLAGS -Xclang -disable-llvm-optzns -emit-llvm -S "$SOURCE_FILE" -o "$UNOPTIMIZED_IR" $REDIRECT

echo -e "${BLUE}Step 3: Getting IR before crash...${NC}"
# Run opt to get IR before crash
eval "$COMPILER_DIR/opt" -print-on-crash -print-module-scope -verify-each -S -O3 "$UNOPTIMIZED_IR" 2> "$BEFORE_CRASH_RAW" $REDIRECT

# Clean up the output to keep only valid IR and remove the core dump line
sed -n '/^; ModuleID/,$p' "$BEFORE_CRASH_RAW" | sed '$d' > "$BEFORE_CRASH"
rm "$BEFORE_CRASH_RAW"

echo -e "${BLUE}Step 4: Running llvm-reduce...${NC}"
# Create reduction test script
cat > "$REDUCE_TEST" << EOF
#!/bin/bash
! "$COMPILER_DIR/opt" -disable-output -O3 < "\$1"
EOF
chmod +x "$REDUCE_TEST"

# Run llvm-reduce
eval "$COMPILER_DIR/llvm-reduce" --test "$REDUCE_TEST" "$BEFORE_CRASH" -o "$OUTPUT_FILE" $REDIRECT

# Cleanup intermediate files
# rm "$UNOPTIMIZED_IR" "$BEFORE_CRASH" "$REDUCE_TEST"

echo -e "${GREEN}Reduction complete. Check ${OUTPUT_FILE} for the minimized test case.${NC}"