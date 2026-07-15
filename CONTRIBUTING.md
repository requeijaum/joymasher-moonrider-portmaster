# Contributing

Thanks for helping test and improve the Moonrider PortMaster port.

## Ground rules

- Never commit or upload commercial Moonrider assets, including `data.js`, media, images, videos, executables or `app.asar`.
- Use a legitimate desktop/Electron game copy only on your own machine.
- Keep device-specific credentials, LAN addresses and private backup paths out of commits and logs.
- Do not claim compatibility without naming the exact handheld, SoC, firmware and version tested.
- Preserve the BYO-assets model.

## Development flow

1. Fork the repository and branch from `main`.
2. Keep experimental engines and diagnostics on separate branches.
3. Add or update a test before changing behavior.
4. Run the public gates:

```sh
scripts/verify-public-release.sh
scripts/verify-playable-contract.sh
```

5. Run any component-specific test named in the changed file or report.
6. Open a pull request describing the device, firmware, observed behavior and verification output.

## Bug reports

Use the bug-report issue form. Include:

- device and SoC;
- firmware and exact version;
- engine selection, if known;
- reproduction steps;
- expected and actual behavior;
- sanitized logs;
- whether video, audio, gamepad and frontend restoration still work.

Do not attach game assets or logs containing credentials/private paths.

## Code style

- Shell scripts must be valid POSIX shell unless explicitly documented otherwise.
- Native code is C11 and should build cleanly with `-Wall -Wextra -Werror` where the local harness supports it.
- Keep public documentation in English. Dated engineering reports may be in Portuguese.
- Prefer deterministic transforms and verifiable manifests over manual file edits.

## Scope

This is an unofficial compatibility project. Contributions must concern original port code, build glue, testing or documentation. Requests to distribute copyrighted game content will be closed.
