import re

filepath = "Packages/BlinkBreakCore/Tests/BlinkBreakCoreTests/SessionControllerTests.swift"

with open(filepath, "r") as f:
    content = f.read()

content = content.replace("lock.withLock {\n                return storage\n            }", "lock.withLock { return storage }")
content = content.replace("lock.withLock {\n                storage = newValue\n            }", "lock.withLock { storage = newValue }")

with open(filepath, "w") as f:
    f.write(content)
