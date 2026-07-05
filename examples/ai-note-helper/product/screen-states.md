# Screen States: AI Note Helper

Fill this for every screen. Do not only define the happy path.

| Screen | User goal | Loading | Empty | Error | Permission denied | Success |
| --- | --- | --- | --- | --- | --- | --- |
| Home | See recent notes and start a new note | Show recent notes loading | Say "No notes yet" and show a new-note button | Show read failure and retry | No system permission needed | Show recent notes and new-note entry |
| New Note | Enter a messy thought | Prevent duplicate save taps | Disable organize button when input is empty | Keep the raw text and show retry | No system permission needed | Save note and open organized result |
| Organized Result | Read title, summary, and actions | Show "Organizing" while keeping the raw note visible | If no result exists, offer organize again | Explain AI failure and allow copying raw note | No system permission needed | Show title, summary, actions, and copy button |
| History | Reopen recent organized notes | Show loading state | Say there is no history yet | Show retry on read failure | No system permission needed | Open detail when a record is selected |
| Settings | Read data notes and version info | No long loading expected | Show explanation when there is no config | Show retry when config read fails | No system permission needed | User can see local storage and deletion notes |

## Acceptance

- First-time users understand the next step.
- No data does not crash the app.
- Errors explain the next step.
- Important actions are not hidden.
- Result screen must support copy, not only display.
