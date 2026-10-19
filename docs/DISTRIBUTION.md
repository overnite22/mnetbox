# Distribution preparation — draft, not uploaded

The current Personal Team remains configured for development. No App Store/TestFlight upload, account change or bundle-identifier change has been performed. Release compilation verifies packaging, not App Store approval. Confirm the final support/contact/policy URLs and distribution identity before publishing.

## Product metadata draft

| Field | English | French |
| --- | --- | --- |
| Name | MNetBox | MNetBox |
| Subtitle | Browse and manage NetBox | Consultez et gérez NetBox |
| Category proposal | Utilities | Utilitaires |
| Short description | A native iPhone client for your own HTTPS NetBox server. Browse inventory, racks, IPAM, VLANs, MAC addresses and linked contexts. Review supported changes before confirming them. | Un client iPhone natif pour votre serveur NetBox HTTPS. Consultez l’inventaire, les baies, l’IPAM, les VLAN, les adresses MAC et leurs périmètres liés. Vérifiez les modifications prises en charge avant de les confirmer. |

Requires iOS 27+, a reachable HTTPS NetBox instance, an API token and the relevant NetBox permissions. Compatibility reference: 4.7.2; do not claim all NetBox versions are supported. MNetBox is an independent client; no endorsement by NetBox is claimed. No favorites, tracking, advertising or analytics SDKs are implemented.

## Privacy review facts

`PrivacyInfo.xcprivacy` is packaged as an app resource. It declares no tracking domains, tracking, developer collection or required-reason API usage in the current app. Source audit found no UserDefaults, file-time, disk-space or uptime APIs in app code, and no third-party SDKs. Review this declaration again when adding dependencies/features. NetBox connections and reviewed writes transmit credentials/data to the server chosen by the user; server operators can retain logs/change records. App Store privacy answers must reflect the final developer/server relationships, not merely the absence of analytics. See PRIVACY.md for factual policy text to finalize.

The optional technical report is explicitly previewed/shared by the user. Only numeric app/build/iOS/NetBox versions and a reference-version label are included. There is no telemetry endpoint or automatic upload.

## Before public distribution

- Configure the intended distribution team/membership and final app identifier. Current Personal Team is a development setup.
- Supply an owned public support URL, privacy-policy URL and contact. No placeholders have been uploaded or embedded as working links in the app.
- Prepare a dedicated synthetic/demo NetBox instance and review access without using production credentials. Review credentials are not committed here.
- Capture marketing screenshots on supported iPhone sizes using synthetic data; current UI test attachments are verification artifacts, not final App Store assets.
- Verify the support matrix in COMPATIBILITY.md, restricted accounts, fresh install/restore/logout, cancellations/conflicts and negative write cases. Confirm app icon and French/English metadata.
- Answer encryption/export and App Store privacy questions against the actual release. The app uses platform HTTPS/Keychain and no custom cryptographic implementation.
- Produce/validate a signed distribution archive in Xcode, then explicitly authorize the selected TestFlight/App Store submission.

Apple references: https://developer.apple.com/app-store/app-privacy-details/ and https://developer.apple.com/documentation/bundleresources/privacy-manifest-files
