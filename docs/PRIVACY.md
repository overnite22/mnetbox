# Privacy information — factual draft

MNetBox is an iPhone client for a NetBox HTTPS server selected by the user. This document describes the current implementation. Before publication, the distributor must add its identity, support contact and public policy URL and verify its actual server/data relationships.

- The server address, token and token format are stored together in this device’s Keychain, available only while unlocked and not migrated to another device. They are not stored in UserDefaults, repository files or diagnostic reports.
- Authenticated HTTPS requests send the token to the selected NetBox server. Redirects are refused; platform certificate validation is used. Network sessions have no disk cache or cookie store.
- Inventory data and unsaved drafts are used in memory. Supported mutations send the reviewed fields to NetBox only after explicit confirmation. The chosen server may retain access logs, data and change history under its operator’s policy.
- MNetBox includes no advertising, analytics SDK, developer telemetry service or automatic diagnostic upload. It does not request camera, microphone, photo-library, contacts or location access for these features.
- A user can preview and share a technical report through the native share sheet. It contains app/build, iOS and numeric NetBox versions and the reference compatibility label. It excludes server URLs, tokens, account names and inventory. The user chooses the recipient/application.
- Disconnect/Forget saved connection cancels the session and removes the saved Keychain record when secure storage is available. This does not revoke the token or delete NetBox data; token revocation is managed on the selected NetBox server.

This draft has not been published or submitted as App Store privacy answers. NetBox server policy and app-distributor responsibilities must be finalized for the actual release configuration.

Automatic NetBox images use only metadata from the selected user's NetBox server. Image bytes are requested from the same HTTPS origin's configured /media/ path without the API token, cookies or redirects. Images are held in memory with ephemeral transport; no persistent image cache, public image search, analytics or upload is introduced. Private/external media may be unavailable. This extends the existing user-server communication only; distribution declarations remain pending review against the actual release.

Build 27 update: protected native images use the existing token exclusively on validated HTTPS same-origin NetBox image directories; no browser cookies, redirects, external image service or persistent media cache. This replaces the earlier credentialless media transport limitation. Cable trace retrieves inventory path data from the configured server only.

Build 28: a user-selected Photos asset can be uploaded only after an in-app target/image review and confirmation. PhotosPicker gives access to that selected asset; the app does not enumerate the library or access the camera. The original stays in Photos. Source location/EXIF metadata and original filename are not copied into the normalized <=2048-pixel JPEG. Image draft stays in memory and is sent to the configured NetBox server as an attachment; that server stores it according to its own retention policy. No local export, analytics, public image provider or automatic upload. This supersedes earlier statements that image upload was unsupported.


Build 29 requests current PhotosPicker encoding and preserves PNG alpha while re-encoding image pixels without source location metadata. Transparent backgrounds use local native drawing. Deleting a photo sends one explicit attachment DELETE only after user review and exact-ID confirmation; no other Photos asset or server object is removed. Images remain in memory; no persistent image cache, tracking or external image catalog.


Build 30 reads additional native device port metadata and trace paths through the configured NetBox server. VRF/IPAM-role deletion sends one explicit confirmed DELETE after review and dependency checks. No external service, persistent media cache, full Photos-library access or credential export is added. Automated tests remain synthetic.


Build 31 uses only existing native device component metadata for a local graphical port grid. Connector drawings and state counters are generated locally; no monitoring probe, image catalog, analytics or third-party service is added. The panel is read-only and does not scan network devices.
