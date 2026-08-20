# Validation

Package build validation performed on the two exact uploaded canonical LaTeX sources:

- `canonical/ai-applied-canonical.tex` -> compiled successfully -> 1 page.
- `canonical/backend-platform-canonical.tex` -> compiled successfully -> 1 page.

Canonical SHA-256 hashes are recorded in `canonical/SHA256SUMS.txt` and enforced by `scripts/verify-canonical.ps1`.

The PowerShell workflow is intended for the user's Windows/OpenCode/MiKTeX environment. The canonical LaTeX sources were additionally compiled in the build environment with `latexmk`/`pdflatex` to confirm syntax and page count.
