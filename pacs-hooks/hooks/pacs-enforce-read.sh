#!/bin/bash
# Kept so existing settings.json entries keep working; the logic is in pacs-gate.sh.
exec /bin/bash "$(dirname "${BASH_SOURCE[0]}")/pacs-gate.sh" enforce
