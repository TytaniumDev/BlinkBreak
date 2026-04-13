import os
import glob

def format_file(filepath):
    with open(filepath, 'r') as f:
        content = f.read()

    content = content.replace("        }}", "        }\n    }")
    content = content.replace("    }}", "    }\n}")

    with open(filepath, 'w') as f:
        f.write(content)

for filepath in glob.glob("Packages/BlinkBreakCore/Tests/BlinkBreakCoreTests/Mocks/*.swift"):
    format_file(filepath)
