# Data Safety Checklist: AI Note Helper

## Data table

| Data | Source | Why needed | Where stored | Who can see it | How to delete | Shared with third parties |
| --- | --- | --- | --- | --- | --- | --- |
| Raw note text | User input | Generate organized result | First version local device | User | Delete local note | Example does not auto-send real data |
| Generated title, summary, and actions | Organized result | Show copyable result and history | First version local device | User | Delete local note | Example does not auto-send real data |
| Created and updated timestamps | App generated | Sorting and history | First version local device | User | Delete local note | No |
| Local record ID | App generated | Find the matching note | First version local device | User | Delete local note | No |

## Data we do not collect

- Contacts.
- Location.
- Health data.
- Payment data.
- Photos, microphone, calendar, or SMS.
- Advertising tracking ID.

## Third-party services

| Service | Purpose | Data it receives | Exit plan |
| --- | --- | --- | --- |
| No real model service connected | Example stage only describes product needs | No real user data | Validate the flow with local fake data |
| User-chosen AI service later | Future note organization | Only text confirmed by the user | Keep local mode or allow AI organization to be turned off |

## Deletion and export

- How users export data: first version can start with copy result; file export can come later.
- How users delete data: delete the local note record, raw text, and organized result.
- What remains for legal or billing reasons: first version has no account or payment, so billing or identity records should not remain.
