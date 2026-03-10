#!/bin/bash
# ============================================
# setup_test_data.sh
# Creates sample notebook folders and PDFs
# for testing Cozy Home in the KOReader emulator.
#
# Run from WSL:
#   bash /mnt/c/projects/"Koreader Plugins"/cozyhome.koplugin/setup_test_data.sh
#
# This creates test data in the emulator's fake "onboard" storage.
# Adjust KOREADER_DIR if your emulator uses a different path.
# ============================================

set -e

# KOReader emulator stores its fake device files here
KOREADER_DIR="$HOME/projects/koreader"
ONBOARD_DIR="$KOREADER_DIR/spec/unit/data"

# If the emulator uses a different home_dir, try this:
# ONBOARD_DIR="$KOREADER_DIR"

NOTEBOOKS_DIR="$ONBOARD_DIR/notebooks"

echo "Creating test notebook data in: $NOTEBOOKS_DIR"

# Create class folders
mkdir -p "$NOTEBOOKS_DIR/Biology 101"
mkdir -p "$NOTEBOOKS_DIR/History"
mkdir -p "$NOTEBOOKS_DIR/Français"

# Generate minimal valid PDFs (1-page blank)
# This is the smallest valid PDF that KOReader can open
generate_pdf() {
    local filepath="$1"
    cat > "$filepath" << 'PDF'
%PDF-1.4
1 0 obj
<<
  /Type /Catalog
  /Pages 2 0 R
>>
endobj

2 0 obj
<<
  /Type /Pages
  /Kids [3 0 R]
  /Count 1
>>
endobj

3 0 obj
<<
  /Type /Page
  /Parent 2 0 R
  /MediaBox [0 0 595 842]
  /Contents 4 0 R
  /Resources << /ProcSet [/PDF] >>
>>
endobj

4 0 obj
<<
  /Length 0
>>
stream

endstream
endobj

xref
0 5
0000000000 65535 f 
0000000009 00000 n 
0000000058 00000 n 
0000000115 00000 n 
0000000266 00000 n 

trailer
<<
  /Size 5
  /Root 1 0 R
>>
startxref
316
%%EOF
PDF
    echo "  Created: $filepath"
}

# Create sample notebooks in each class
generate_pdf "$NOTEBOOKS_DIR/Biology 101/Lecture Notes.pdf"
generate_pdf "$NOTEBOOKS_DIR/Biology 101/Lab Drawings.pdf"
generate_pdf "$NOTEBOOKS_DIR/History/Timeline.pdf"
generate_pdf "$NOTEBOOKS_DIR/Français/Vocabulaire.pdf"

# Also create one in the root (edge case: should still be found by recursive scan)
generate_pdf "$NOTEBOOKS_DIR/Scratch Pad.pdf"

echo ""
echo "Done! Test notebooks created:"
find "$NOTEBOOKS_DIR" -name "*.pdf" | sort
echo ""
echo "Now symlink the plugins and run the emulator:"
echo "  cd ~/projects/koreader"
echo "  ln -sf /mnt/c/projects/\"Koreader Plugins\"/cozyhome.koplugin plugins/cozyhome.koplugin"
echo "  ./kodev run"
