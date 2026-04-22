#!/bin/zsh
set -euo pipefail

SCRIPT_DIR=${0:A:h}
OUTPUT_FILE="$SCRIPT_DIR/2026-04-22-042-ax-sdk-dump.txt"

SDKROOT="$(xcrun --show-sdk-path)"
AX_DIR="$SDKROOT/System/Library/Frameworks/ApplicationServices.framework/Frameworks/HIServices.framework/Headers"

{
  echo "# SDKROOT"
  echo "$SDKROOT"
  echo

  echo "# AXUIElement.h:368-386"
  nl -ba "$AX_DIR/AXUIElement.h" | sed -n '368,386p'
  echo

  echo "# AXAttributeConstants.h:497-511"
  nl -ba "$AX_DIR/AXAttributeConstants.h" | sed -n '497,511p'
  echo

  echo "# AXAttributeConstants.h:684-806"
  nl -ba "$AX_DIR/AXAttributeConstants.h" | sed -n '684,806p'
  echo

  echo "# AXRoleConstants.h:128-140"
  nl -ba "$AX_DIR/AXRoleConstants.h" | sed -n '128,140p'
  echo

  echo "# AXRoleConstants.h:344-362"
  nl -ba "$AX_DIR/AXRoleConstants.h" | sed -n '344,362p'
} > "$OUTPUT_FILE"

echo "$OUTPUT_FILE"
