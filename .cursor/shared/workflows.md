# Workflows and checks

- Keep workflow definitions in `.github/workflows/*.yml`.
- Pin action versions and avoid unnecessary matrix complexity.
- Keep CI aligned with `.pre-commit-config.yaml` tools:
  - `shellcheck`
  - `shfmt`
  - `stylua`
  - basic hygiene hooks
- Keep PyMOL submodule automation isolated in `update-pymolscripts-submodule.yml`.
- If CI behavior affects contributors, update `README.md` in the same change.
