#!/bin/bash

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

ALIVE_PATH="/bitbucket/plobo/alive2.git/byte-type/build"
LLVM_PATH="/bitbucket/plobo/llvm-project.git/byte-type/build/bin"

OUTPUT_FILE="reduced.ll"
VERBOSE=false

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

if [[ $# -lt 3 ]]; then
  echo -e "${RED}Usage: $0 [-o|--output output_file] [-v|--verbose] <bitcode_file> <function_name> <optimization_pass>${NC}"
  exit 1
fi

BITCODE_FILE="$1"
FUNCTION_NAME="$2"
OPT_PASS="$3"

# Check if bitcode file exists
if [[ ! -f "${BITCODE_FILE}" ]]; then
  echo -e "${RED}Error: Bitcode file '${BITCODE_FILE}' not found${NC}"
  exit 1
fi

[ "$VERBOSE" = true ] && REDIRECT="" || REDIRECT=">/dev/null 2>&1"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
EXTRACTED_IR="${FUNCTION_NAME}_${TIMESTAMP}.ll"

# Extract the function from bitcode
echo -e "${BLUE}Step 1: Extracting function '${FUNCTION_NAME}' from bitcode...${NC}"
eval "$LLVM_PATH/llvm-extract -func=\"$FUNCTION_NAME\" \"$BITCODE_FILE\" -S -o \"$EXTRACTED_IR\"" $REDIRECT
if [[ ! -f "$EXTRACTED_IR" ]]; then
  echo -e "${RED}Error: Failed to extract function '$FUNCTION_NAME' from bitcode${NC}"
  exit 1
fi

TEMP_TEST=$(mktemp)
cat > "$TEMP_TEST" << EOF
#!/bin/bash
"$ALIVE_PATH/alive-tv" --passes=$OPT_PASS --quiet --disable-undef-input --func=$FUNCTION_NAME "\$1" \\
  | grep -Ei "1 (incorrect|failed-to-prove) transformations"
EOF
chmod +x "$TEMP_TEST"

# Run llvm-reduce
echo -e "${BLUE}Step 2: Running llvm-reduce...${NC}"
"$LLVM_PATH/llvm-reduce" --test "$TEMP_TEST" "$EXTRACTED_IR" -o "$OUTPUT_FILE" $REDIRECT

# If the reduction failed, copy the extracted IR as output
if [[ ! -f "$OUTPUT_FILE" ]]; then
  echo -e "${YELLOW}Warning: Reduction failed. Copying extracted function to output file.${NC}"
  cp "$EXTRACTED_IR" "$OUTPUT_FILE"
fi

rm -f "$EXTRACTED_IR" "$TEMP_TEST"

echo -e "${GREEN}Reduction complete. Check ${OUTPUT_FILE} for the minimized test case.${NC}"
