# Xcode project static review

Reviewed on 2026-11-08 in a Linux workspace without Swift or Xcode. This is a source/configuration review, not evidence of compilation, signing, simulator execution, or upload validation.

## Verified structure

The generated OpenStep project was parsed independently, and all object references and shared-scheme blueprint references resolved. Configuration Info plists and entitlements parsed as XML property lists. The local package manifest declares Swift tools 5.9 and macOS 14 / iOS 17, matching the project’s deployment settings.

| Area | Static finding |
| --- | --- |
| App sources | Both app targets include the same 16 shared Swift files. |
| Core package | Both apps reference the local `Packages/PearlsCore` package product in their dependency and framework phases. No remote package is required. |
| Share target | `PearlsShare` compiles `AppPaths.swift` and `ShareViewController.swift`, sets `APPLICATION_EXTENSION_API_ONLY=YES`, and skips independent installation. |
| Embedding | The iPhone app has an explicit dependency on `PearlsShare` and copies `PearlsShare.appex` into the PlugIns destination. |
| Principal class | The extension Info plist names `$(PRODUCT_MODULE_NAME).ShareViewController`; its module is `PearlsShare`, matching the controller source. |
| App Group | The iPhone app and extension both declare `$(PEARLS_APP_GROUP)` in entitlements and their Info values. The group holds only the shared capture inbox; the main library stays in the app’s own `Application Support/Pearls` directory. The group still requires registration and matching team profiles. |
| Shared settings | Project-level `Shared.xcconfig` supplies version/build, bundle ID base, group, and automatic signing; the optional local config supplies the real developer team. |
| Resources | Each app includes the asset catalog, three bundled fonts, and the privacy manifest. The extension includes the privacy manifest. |
| Icons | App targets choose `AppIcon-Mac` and `AppIcon-iOS`. The asset-packaging phase precedes their source/framework/resource phases. The Mac Info override that incorrectly named `AppIcon` has been removed. |
| Archive type | Both platform Info plists advertise `.pearlsarchive` and the legacy `.pearls` alias; the app’s import routing recognizes both. |
| Schemes | `Pearls-Mac` and `Pearls-iOS` identify the intended `Pearls.app` products and use Release for Archive. Package tests run through `scripts/validate-apple.sh`; the app schemes contain no separate UI-test target. |

## Findings corrected during review

The generator originally validated only object references, allowing a project to be emitted while the share controller was absent. The generator now rejects missing source/resource paths, and the controller exists.

The icon phase originally omitted the helper shell script from its inputs, and the helper’s cache could skip regeneration when JSON existed but generated PNGs were missing. The generator now includes the helper input and runs the preflight each build; the helper verifies all expected PNG sizes before using its cache.

The project was regenerated after these fixes, and the final emitted file includes the updated icon phases and references the now-present share controller. Regenerate again with `python3 BuildSupport/generate-project.py` when source/configuration membership changes. The independent project parse verifies the emitted file’s structure; it does not establish that Xcode accepts every build setting or that Swift type checking succeeds.

## Remaining Apple checks

No additional concrete target or configuration blocker was established by this static review. Build the Mac app and iOS Simulator app, run the package tests, inspect the produced icon/Info resources, and exercise the share sheet on Apple platforms. Then verify archive signing, provisioning, version/build alignment, extension embedding, entitlements, and privacy resources before TestFlight upload. Registered Apple identifiers, an authorized team, and successful Apple-side processing remain release prerequisites.
