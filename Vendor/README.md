# Third-party code

[AppleSiliconDDC](https://github.com/waydabber/AppleSiliconDDC) by @waydabber,
vendored from commit `67ff964ab8123d9d35fadf7d8e1a7c677d31da14`.
Its Swift library and Objective-C bridge are included; its CLI and dependencies are not.
License: MIT, reproduced in `AppleSiliconDDC-LICENSE`.

Local changes in `AppleSiliconDDC.swift`:

- Do not report a successful read when the I2C request write succeeds but the reply read fails.
- Validate Get VCP reply headers, status and echoed command, in addition to checksum.
- Release iterated IOKit registry entries and deallocate the display-path buffer.
- Use the macOS 12+ `kIOMainPortDefault` constant.

The IOAVService and CoreDisplay APIs are private macOS APIs. OS updates may break
them; this app is not intended for the Mac App Store.
