# Workflow Templates

This directory contains reusable GitHub Actions workflow templates for building, deploying, and maintaining applications.

## Directory Structure

```
workflows/
├── common/                  # Common workflows required by all project types
│   ├── cleanup-artifacts.yml
│   └── reusable-lpk-package.yml
├── docker-lpk/             # Workflows for projects with Docker images + LPK packages
│   ├── cleanup-docker-tags.yml
│   ├── docker-image.yml                # Trigger layer (copied on init)
│   ├── lpk-package.yml
│   └── reusable-docker-image.yml       # Reusable logic (synced on update)
└── lpk-only/               # Workflows for projects with only LPK packages
    └── lpk-package.yml
```

## Common Workflows (Required for All Types)

These workflows provide essential maintenance tasks and should be used by all project types.

### cleanup-artifacts.yml

**Purpose:** Automatically clean up old GitHub Actions artifacts to manage storage quota.

**Triggers:**
- Scheduled: Every Sunday at 3:00 AM UTC
- Manual: `workflow_dispatch` with customizable options

**Features:**
- Configurable retention period (default: 15 days)
- Always keeps the most recent N artifacts (default: 3)
- Dry run mode for testing
- Detailed cleanup summary with size calculations

**Configuration:**
- No secrets required (uses built-in `GITHUB_TOKEN`)
- Customize via manual trigger inputs or modify cron schedule

**Usage:** Copy to `.github/workflows/cleanup-artifacts.yml`

---

## Docker + LPK Workflows

Use these workflows for projects that need to build Docker images and then package them into Lazycat LPK packages.

### 1. docker-image.yml + reusable-docker-image.yml

**Purpose:** Build and push Docker images to Docker Hub.

**Triggers:**
- Push to `main` or `main-lazycat` branches
- Pull requests to `main` or `main-lazycat`
- Tag pushes (e.g., `v1.0.0`)
- Manual trigger with custom parameters

**Features:**
- Multi-platform build support via Docker Buildx
- Optional Go tests before building
- Automatic image tagging:
  - Branch: `main` tag
  - Tag: Version tag (e.g., `v1.0.0`)
  - Commit: SHA-based tag (e.g., `sha-1234567`)
- Skip CI support: Add `[skip ci]`, `[ci skip]`, or `[no ci]` to commit message

**Configuration:**
```yaml
# Required secrets:
DOCKERHUB_USERNAME  # Docker Hub username
DOCKERHUB_TOKEN     # Docker Hub access token

# Optional repository variables (can also use workflow_dispatch inputs):
DOCKER_CONTEXT      # Build context path (default: ./backend)
DOCKERFILE_PATH     # Dockerfile path (default: ./backend/Dockerfile)
DOCKER_TARGET       # Build target stage (default: prod)
ENABLE_GO_TESTS     # Enable Go tests (default: false)
GO_VERSION          # Go version (default: latest)
GO_TEST_DIR         # Test directory (default: ./backend)
```

**Usage:**
- Trigger layer (`docker-image.yml`) is copied during project initialization so teams can freely modify `on` conditions or notifications.
- Reusable layer (`reusable-docker-image.yml`) lives in the same directory for clarity and is copied into `.github/workflows/reusable-docker-image.yml`; it stays up to date whenever you run `scripts/lazycli.sh --sync`.

### 2. lpk-package.yml (Docker-LPK version)

**Purpose:** Build Lazycat LPK packages after Docker images are built successfully.

**Triggers:**
- Automatically triggered when `docker-image.yml` workflow completes successfully
- Manual trigger with custom Docker image tag

**Key Differences from LPK-Only version:**
- **Trigger:** Runs after Docker workflow via `workflow_run` event
- **Additional Steps:**
  - Determines Docker image name and tag
  - Copies Docker image from Docker Hub to Lazycat registry
  - Updates manifest with Lazycat image URL
- **Input:** Accepts `image_tag` parameter for manual runs

**Features:**
- Automatic version management:
  - Tag push: Uses version from tag (e.g., `v1.0.0` → `1.0.0`)
  - Branch push: Uses alpha version with commit SHA
  - Manual: Custom version or specified tag
- Only publishes to App Store for release versions (semantic versioning)
- Uploads LPK as GitHub artifact for all builds
- Uses caching for npm packages and system dependencies

**Configuration:**
```yaml
# Required secrets:
DOCKERHUB_USERNAME    # Docker Hub username (for image copy)
DOCKERHUB_TOKEN       # Docker Hub token (for image copy)
LAZYCAT_USERNAME      # Lazycat platform username
LAZYCAT_PASSWORD      # Lazycat platform password
```

**Usage:** Trigger layer copied to `.github/workflows/lpk-package.yml`; the shared logic lives in `.github/workflows/reusable-lpk-package.yml` and is synced automatically.

### 3. cleanup-docker-tags.yml

**Purpose:** Clean up old Docker Hub SHA-based tags to manage registry storage.

**Triggers:**
- Scheduled: Every Sunday at 2:00 AM UTC
- Manual: `workflow_dispatch` with configurable keep count

**Features:**
- Only removes SHA-based tags (e.g., `sha-1234567`)
- Keeps the most recent N tags (default: 10)
- Preserves named tags (e.g., `main`, `v1.0.0`)
- Pagination support for large tag lists
- Security: Only runs on main repository, not forks

**Configuration:**
```yaml
# Required secrets:
DOCKERHUB_USERNAME  # Docker Hub username
DOCKERHUB_TOKEN     # Docker Hub access token

# Required repository settings:
# Update line 21: repository_owner == 'your-org-name'
```

**Usage:** Copy to `.github/workflows/cleanup-docker-tags.yml`

---

## LPK-Only Workflows

Use these workflows for projects that only need Lazycat LPK packages without Docker images.

### lpk-package.yml (LPK-Only version)

**Purpose:** Build Lazycat LPK packages directly without Docker image dependency.

**Triggers:**
- Push to `main` or `main-lazycat` branches
- Pull requests
- Tag pushes (e.g., `v1.0.0`)
- Manual trigger with custom version

**Key Differences from Docker-LPK version:**
- **Trigger:** Direct trigger from push/PR/tag events (no `workflow_run`)
- **No Docker Steps:** Skips Docker image copying and manifest updating
- **Simpler Flow:** Directly builds LPK from source code

**Features:**
- Same version management as Docker-LPK version
- Same publishing logic (only release versions)
- Same caching and optimization strategies
- Skip CI support: Add `[skip ci]` to commit message

**Configuration:**
```yaml
# Required secrets:
LAZYCAT_USERNAME  # Lazycat platform username
LAZYCAT_PASSWORD  # Lazycat platform password
```

**Usage:** Trigger layer copied to `.github/workflows/lpk-package.yml`; it calls `.github/workflows/reusable-lpk-package.yml` for the shared packaging steps.

---

## Choosing the Right Workflow Type

### Use Docker-LPK (`docker-lpk/`) when:
- Your project needs to be containerized
- You deploy to environments that run Docker containers
- Your LPK package references Docker images
- Example: Web backends, microservices, API servers

### Use LPK-Only (`lpk-only/`) when:
- Your project doesn't need containerization
- You only package static files or scripts
- Your LPK package is self-contained
- Example: Static websites, CLI tools, documentation sites

### Always Include:
- `common/cleanup-artifacts.yml` - Essential for all projects to manage GitHub storage

---

## Quick Start

1. **Identify your project type:**
   - Does it need Docker? → Use `docker-lpk/`
   - No Docker needed? → Use `lpk-only/`

2. **Copy required workflows to `.github/workflows/`:**
   ```bash
   # For Docker + LPK projects:
   cp workflows/docker-lpk/*.yml .github/workflows/
   cp workflows/common/*.yml .github/workflows/

   # For LPK-only projects:
   cp workflows/lpk-only/*.yml .github/workflows/
   cp workflows/common/*.yml .github/workflows/
   ```

3. **Configure GitHub secrets:**
   - Go to Settings → Secrets and variables → Actions
   - Add required secrets based on workflow type (see Configuration sections above)

4. **Adjust workflow parameters if needed:**
   - Modify default values in workflow files
   - Or set repository variables for dynamic configuration

5. **Test with a commit:**
   ```bash
   git add .github/workflows/
   git commit -m "feat: add GitHub Actions workflows"
   git push
   ```

---

## Skip CI Support

All workflows support Skip CI markers in commit messages:

- **Supported markers:** `[skip ci]`, `[ci skip]`, `[no ci]`, `[skip actions]`, `[actions skip]`
- **Works for:** Push and PR events
- **Does NOT work for:** Tag pushes (always build releases)

**Examples:**
```bash
git commit -m "docs: update README [skip ci]"
git commit -m "[ci skip] fix typo"
```

---

## Troubleshooting

### Docker image workflow fails
- Verify `DOCKERHUB_USERNAME` and `DOCKERHUB_TOKEN` secrets
- Check Dockerfile path in workflow configuration
- Review build logs for compilation errors

### LPK package workflow fails
- Verify `LAZYCAT_USERNAME` and `LAZYCAT_PASSWORD` secrets
- Ensure `lzc-manifest.yml` exists in repository root
- Check Lazycat CLI authentication logs

### Cleanup workflows don't run
- Verify cron schedule syntax
- Check if workflows are enabled in repository settings
- For Docker cleanup: Verify `repository_owner` matches your org

---

## References

- [Lazycat LPK Package Guidelines](https://lazycat.cloud/playground/guideline/572)
- [GitHub Actions Documentation](https://docs.github.com/en/actions)
- [Docker Build Push Action](https://github.com/docker/build-push-action)
