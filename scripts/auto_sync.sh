#!/bin/bash
cd /root/audithound_new

# Auto-commit any uncommitted changes
if ! git diff --quiet || ! git diff --cached --quiet || [ -n "$(git ls-files --others --exclude-standard)" ]; then
    git add -A
    git commit -m "auto sync: $(date +%Y-%m-%d_%H:%M:%S)" --allow-empty
fi

# Push to remote
git push origin main 2>&1 || echo "push failed, will retry next cycle"
