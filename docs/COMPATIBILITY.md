# Compatibility and acceptance

MNetBox 0.12.0 build 28 targets iPhone, iOS 27+, portrait, French/English and HTTPS NetBox. The current reference API is **NetBox 4.7.2**. The app-information screen reads only the `netbox-version` field from `/api/status/`; it labels other versions unverified and does not block browsing. It does not infer object permissions or write safety from a version string. VLAN-group deletion has synthetic coverage; real-server VLAN-group deletion was accepted on 2026-10-05. Authenticated media and cable trace acceptance remain pending.

| Configuration | Evidence | Remaining verification |
| --- | --- | --- |
| NetBox 4.7.2 | Version-pinned serializers/filtersets, synthetic unit/UI coverage; user accepted production milestones through 24 | Milestone 25a context writes, automatic media and restricted production accounts |
| NetBox 4.7.0 | Historical user acceptance of v1/v2 authentication | Current feature set not certified |
| Other NetBox versions/plugins | Unknown values/scopes remain readable; unknown scopes do not open an unrelated model | Full API and mutation-contract validation before claiming support |
| iOS 27.0 simulator | Dedicated synthetic tests, local Keychain signature enabled | Full historical UI suite is not rerun for every delivery |
| iOS 27.2 physical iPhone | User accepted milestones through 24; paired wireless installation verified | New lot manually tested when the user is available |
| Other iPhones/iOS builds | Adaptive native UI, iPhone deployment target | Device-specific checks before public release |

## Context semantics

Context IDs remain distinct even when names, RD labels or VLAN numbers recur. Known paths are fixed by model type. All new list pages preserve search, ordering and scope; returned rows and details are checked. Region/site-group/location inventory filters include descendants. Their returned ancestry is resolved using bounded GETs (64 levels, cycle detection); inaccessible or invalid ancestry cannot establish scope. Prefix `scope_type`/`scope_id` links use the exact selected scope. VRF, tenant, IPAM role, cluster, rack-group and site relations use their appropriate typed filters. An IPAM role never routes to a device role.

Missing object permission produces a category-local error; it does not turn another category off. A context's empty list is normal when the account has no visible objects. A read-only token suffices for these additions. Writes retain the existing review, fresh reference/ETag and NetBox-authoritative constraints.

## Manual lot 17–18 acceptance

1. Dashboard: compare all six cards with NetBox, tap their links, pull to refresh and check light/dark appearance. Home → information: compare server version with NetBox; inspect the diagnostic preview before choosing to share it. It contains no server URL, token, username, object IDs or inventory.
2. IPAM → VRFs/tenants/IPAM roles: compare IDs, RD, scoped prefixes/IPs and navigation back. Include overlapping prefixes and reused names if available.
3. Inventory → clusters/locations/regions/groups: compare hierarchy, linked sites/racks/VMs and group scope navigation from a VLAN group.
4. Try a restricted account; one refused category must leave permitted categories usable. Cancel/retry a failed read and compare after refresh.
5. Fresh install: URL is empty, both token formats selectable, existing saved connection restores normally.

No production mutations are automated. Physical acceptance is performed when the user unlocks/opens the phone; no need to leave it unlocked during development.

## Version-pinned sources

- https://github.com/netbox-community/netbox/blob/v4.7.2/netbox/ipam/api/serializers_/vrfs.py
- https://github.com/netbox-community/netbox/blob/v4.7.2/netbox/dcim/api/serializers_/sites.py
- https://github.com/netbox-community/netbox/blob/v4.7.2/netbox/dcim/api/serializers_/racks.py
- https://github.com/netbox-community/netbox/blob/v4.7.2/netbox/virtualization/api/serializers_/clusters.py
- https://github.com/netbox-community/netbox/blob/v4.7.2/netbox/dcim/filtersets.py
- https://github.com/netbox-community/netbox/blob/v4.7.2/netbox/dcim/base_filtersets.py
- https://github.com/netbox-community/netbox/blob/v4.7.2/netbox/netbox/api/views.py

Milestone 19 real-data acceptance: VLAN creation/basic field editing, assigned-MAC creation, primary designation and explicit moves/detachment must be compared on NetBox 4.7.2 using deliberately selected objects. Exact IDs distinguish reused MAC addresses/VLAN numbers. New writes do not change the claimed version matrix. See WRITES.md.

Automatic images support HTTPS same-origin /media/ raster files without cookie/token authentication. External storage/signed URLs and browser-login-protected media are unverified/unsupported. Metadata errors remain independent of browsing. No manufacturer image database is assumed.

Build 28 requires add_imageattachment and parent visibility permissions for reviewed uploads. Photos selection, normalized orientation and real-server upload acceptance remain to verify on the physical phone. Protected image visibility was accepted by the user in build 27. Passive front/rear mappings use the NetBox 4.7.2 multi-position serializer; earlier/simplified plugin schemas remain unverified.


Build 29 aligns tracing with NetBox 4.7.2 TracedCableSerializer (BaseModelSerializer raw status/length_unit) and PathEndpointMixin.trace()/model.trace() (empty [] internal/missing link). Device ports require device identity; circuit-termination, site and provider-network endpoints use exact typed URLs and display/name labels without assuming a device. This fixes schema mismatches, not server-side topology; plugin/unknown endpoints and hidden paths remain unsupported. PNG transparency and matching multipart MIME/extension are supported, with native ImageIO normalization; camera capture, SVG and device-type image mutations remain unsupported.


Build 30 uses the 4.7.2 VRF/Role native reverse-reference contracts, including role on ASN, and shared CommonInterfaceFilterSet vrf_id on physical/VM interfaces. Deletion is conservative and requires explicit count fields and exact returned filtered references. GET-only port directories cover front/rear/console/console-server/power-port/power-outlet; only the four active families plus physical interfaces use the native trace action. Passive families expose paths in NetBox and retain mapping navigation only. Real restricted-account/plugin coverage is still pending; simulator fixtures are not proof of every server extension.


Build 31's port-panel visual positions are a logical natural-name arrangement of loaded records, not device-type/manufacturer physical coordinates. Connector drawings use standard declared type strings for copper/fiber, known console/power family or generic fallback. Colors describe cable/admin metadata from NetBox and do not establish live link state. Native component collections remain separately selectable to avoid combining different models that reuse IDs. GET-only data uses the existing server/version and transport contracts.
