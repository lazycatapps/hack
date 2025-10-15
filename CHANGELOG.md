# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] - 2025-10-15

### Added
- Initial repository setup
- Base Makefile (base.mk) for common build targets and rules
- Project initialization script (scripts/lazycli.sh) with interactive mode
- Workflow templates for different project types:
  - lpk-only: For projects building LPK packages only
  - docker-lpk: For projects building Docker images and LPK packages
- Common workflow templates (cleanup-artifacts.yml, cleanup-docker-tags.yml)
- Common configuration files (.gitignore, .editorconfig)
- Comprehensive documentation (README.md)

[Unreleased]: https://github.com/lazycatapps/hack/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/lazycatapps/hack/releases/tag/v0.1.0
