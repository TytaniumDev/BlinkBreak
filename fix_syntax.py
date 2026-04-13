import os
import glob

def format_file(filepath):
    with open(filepath, 'r') as f:
        content = f.read()

    content = content.replace("        disarmedCycleIds.removeAll()\n+        }\n", "            disarmedCycleIds.removeAll()\n        }\n")
    content = content.replace("        disarmedCycleIds.removeAll()\n        }", "            disarmedCycleIds.removeAll()\n        }")
    content = content.replace("        activateCount = 0\n        }", "            activateCount = 0\n        }")
    content = content.replace("        activateCount = 0\n+        }", "            activateCount = 0\n        }")

    with open(filepath, 'w') as f:
        f.write(content)

for filepath in glob.glob("Packages/BlinkBreakCore/Tests/BlinkBreakCoreTests/Mocks/*.swift"):
    format_file(filepath)
