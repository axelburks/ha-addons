# Development / Adding an Add-on

## Add a new add-on

1. Create a directory `<addon>/` under the repo root (the directory name is the add-on identifier; use hyphens, e.g. `foo-bar`).

2. Add the following files:

   | File | Required | Notes |
   |------|----------|-------|
   | `config.yaml` | Yes | Add-on manifest. See required fields below |
   | `Dockerfile` | Yes | Image build |
   | `run.sh` | Yes | Container entrypoint |
   | `README.md` | Yes | The add-on's options, usage and caveats (put all details here) |
   | `build.yaml` | Optional | Only for HA local-build add-ons; this repo uses prebuilt `image:`, so it can be omitted |

3. Required `config.yaml` fields (relied on by both CI and HA):

   ```yaml
   name: "Foo Bar"
   version: "1.0.0"                                  # addon version = image tag (bump it to trigger a release)
   slug: foo_bar
   arch: [amd64, aarch64]
   image: "ghcr.io/axelburks/{arch}-foo-bar"         # image name, must contain the {arch} placeholder
   ```

   - `{arch}` in `image` is HA's placeholder, replaced with `amd64` / `aarch64` at runtime.
   - CI parses the image name from `image` and pushes to `ghcr.io/axelburks/<arch>-foo-bar` and `docker.io/axelburks/<arch>-foo-bar`.

4. Add a row to the "Add-ons" list in the root [README.md](../README.md).

5. Build locally to verify (no push):

   ```bash
   ./dev/build-local.sh <addon> amd64
   ./dev/build-local.sh <addon> aarch64
   ```

## Release / update (automated by CI)

Just change an add-on and push to `main`:

```bash
# To upgrade an add-on: bump its config.yaml version (and its Dockerfile ARG if bumping the underlying software)
git commit -am "foo-bar 1.0.1"
git push
```

`.github/workflows/build.yml` will:

1. Iterate over all add-ons, parsing each one's `version` and `image`.
2. Use `docker manifest inspect` to check whether that version's image already exists -- **skip if it does** (idempotent; editing README etc. won't rebuild).
3. For unpublished ones: multi-arch build, push to ghcr + dockerhub (tag = `version`).
4. On success, create and push a `<addon>-v<version>` tag for archival.

> Note: CI decides by "whether the image already exists", so **you must bump `version` whenever you change code**, otherwise the same version won't produce a new image.

## Notes for first-time publishing of a new image repo

- The repo Secrets must contain `DOCKERHUB_TOKEN` (ghcr uses the built-in `GITHUB_TOKEN`, no setup needed).
- After the first push, the ghcr package is private by default; set it to **public** on its GitHub package page, otherwise HA can't pull it.
