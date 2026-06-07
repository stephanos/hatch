#!/usr/bin/env sh
# See hook docs: https://github.com/stephanos/hatch/blob/main/README.md#hooks

# Write agent instruction forwarding files.
# Shared instructions for all tasks in this project.
printf '@../AGENTS.md\n' > AGENTS.md
printf '@AGENTS.md\n' > CLAUDE.md

# Customize project setup.
# Add custom project setup commands below.
