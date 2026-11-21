# setup-ward

Install [ward](https://github.com/br4zz4/ward) in a GitHub Actions job and export
the values of its scopes to the steps that follow, masked.

```yaml
- uses: actions/checkout@v6
- uses: br4zz4/setup-ward@v1
  with:
    vault: has_warranty
    key: ${{ secrets.WARD_KEY_HAS_WARRANTY }}
    scopes: |
      has_warranty:secrets.ci.staging
      has_warranty:secrets.core.infra.staging
```

| input | meaning |
|---|---|
| `vault` | project namespace of the vaults |
| `key` | key of the default vault; exported as `WARD_KEY_<NAMESPACE>` |
| `restricted-key` | key of the restricted vault; exported as `WARD_KEY_<NAMESPACE>_RESTRICTED`; empty skips it |
| `scopes` | scopes to export, one per line, already qualified with the vault |
| `export-key` | `true` (default) exports the keys; `false` masks them but keeps `WARD_KEY_*` out of the job environment, for jobs that run code that must not reach the vault. The scope values are exported either way |
| `version` | ward release to install, default `0.5.1`; the download is verified against the release `checksums.txt` |
| `directory` | directory with `.ward/config.yaml`, default the workspace root |

What it does:

- installs the ward release for the runner's OS and architecture and puts it on `PATH`;
- exports the keys, so later steps can run `ward exec` on other scopes;
- for each scope, runs `ward secrets --json <scope>`, masks every value line by line
  and writes it to `GITHUB_ENV` with a random delimiter, so a multi-line value cannot
  inject another variable;
- a scope with no values is a notice, not an error.

The job needs the repository checked out (the vault is committed encrypted).
Values never reach the log, but a step that prints an exported variable after
transforming it (`base64`, for instance) is not masked: treat the job as trusted
code.
