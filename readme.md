# AutoInvite
Auto invite on whisper keyword, raid kick buttons, auto-promote assistants.
---
`/autoinvite` or `/ai` for in-game options.

### Auto Invite
* Whispers (and guild chat) whose first word matches your keyword trigger an automatic group/raid invite to the sender.
* Defaults to **off, raid mode, keyword "+"** at every session — turn on explicitly with `/ai on` so it doesn't keep running on alts you forgot about.
* `/ai on|off` — enable / disable the listener.
* `/ai party|raid` — Party (5-man only) or Raid (auto-converts party to raid on the 6th invite).
* `/ai <anything else>` — sets the trigger keyword. Case-insensitive.

### Kick All
* **Kick All** on the Raid tab of the social ('o') panel prompts before kicking everyone in your party/raid. Enabled only while you're in a group.

### Save / Restore Groups
* **Save Groups** snapshots the raid's subgroup arrangement (persists across reloads).
* **Restore Groups** moves members back. Newcomers take a departed member's slot by class; others fill free spots. Needs leader or assist.

### AutoPromote
* Right-click any raid member in the 'o' menu and pick **AutoPromote** to toggle the watch list.
* Watched players auto-promote to assistant whenever they join your raid and you're the leader. Already-assistant members are skipped, so it doesn't spam.
* The menu entry shows a check when the player is on the list.
* Watch list is account-wide and persists across sessions.

___
* Made by and for `Weird Vibes`
