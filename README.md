# unitcheck

Statically score the sandboxing of a systemd service unit.

`systemd-analyze security` grades a unit — but only one that is already installed
on a running systemd host. unitcheck reads a `.service` **file** and reports the
same kind of thing with no systemd and no dependencies, so it runs in CI, on the
unit files you keep in a repo, on any machine.

It is the audit counterpart to [unitforge](https://github.com/vtino17/unitforge),
which *generates* hardened units — a unit unitforge writes scores 100/100 here.

## Usage

```sh
unitcheck myapp.service
unitcheck /etc/systemd/system/*.service
unitcheck --min-score 80 deploy/*.service      # gate in CI
```

Example on a typical hand-written unit:

```
$ unitcheck myapp.service
== myapp.service ==
  HIGH     no User= set: the service runs as root
  HIGH     missing NoNewPrivileges: processes can gain privileges
  HIGH     missing SystemCallFilter: no syscall filter
  HIGH     missing ProtectSystem: filesystem is writable (ProtectSystem not strict/full)
  MEDIUM   missing PrivateTmp: shares /tmp with the rest of the system
  ...
  score: 0/100 (weak)
```

## What it scores

unitcheck weighs the standard sandboxing directives — `NoNewPrivileges`,
`ProtectSystem`, `ProtectHome`, `PrivateTmp`, `PrivateDevices`, the whole
`ProtectKernel*` / `Protect*` family, `RestrictNamespaces`, `RestrictRealtime`,
`RestrictSUIDSGID`, `LockPersonality`, `MemoryDenyWriteExecute`,
`SystemCallFilter`, `SystemCallArchitectures`, `RestrictAddressFamilies` and
`CapabilityBoundingSet` — into a 0-100 score, and separately flags the actively
dangerous settings:

- **`User=root`** (or no `User=` at all) — the service runs as root.
- **`NoNewPrivileges=no`**, **`PrivateTmp=no`**, `ProtectSystem` not strict/full.
- **Dangerous capabilities** kept or granted — `CAP_SYS_ADMIN`, `CAP_SYS_MODULE`,
  `CAP_SYS_PTRACE`, `CAP_DAC_READ_SEARCH`.

Exit status is non-zero if any HIGH finding is present or the score is below
`--min-score` (default 50).

## Caveat

A high score means the sandbox directives are present, not that the service is
correct — a directive can also break a service that genuinely needs what it
removes. Generate with unitforge, check with unitcheck, then deploy and confirm
the service still runs. This reads the file; it does not run `systemd-analyze` on
a live unit.

## Tests

```sh
./tests/run.sh
```

Builds a bare unit, a fully hardened unit and a deliberately dangerous one, and
asserts the scores and findings. No systemd needed.

## License

MIT. See `LICENSE`.
