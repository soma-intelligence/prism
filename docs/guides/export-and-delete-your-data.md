# How do I export or delete my data in Prism?

Settings, Data, Export my data builds one ZIP on the device with a JSON file per record table and one NDJSON file per Apple Health type, then opens the share sheet (a save panel on a Mac). It works without an account. To delete, use Settings, Data, Delete my data when signed in, or Erase data on this iPhone in local mode. Prism never deletes anything from Apple Health.

## What the export holds

Built by `App/Prism/Core/Cloud/DataExport.swift`:

| File | Content |
|---|---|
| `README.txt` | What each file is |
| `profile.json`, `profile.jpg` | Your profile, and its photo if you set one |
| `journal_days.json`, `check_in_answers.json`, `mood_logs.json`, `mind_check_ins.json`, `track_logs.json`, `lab_results.json`, `scores_daily.json`, `notification_inbox.json`, `provider_connections.json`, `ask_conversations.json` | One JSON file per record table, in the shape the cloud stores it |
| `health/<identifier>.ndjson` | One file per Apple Health type, one sample a line with its source |

Not in the export yet: rituals, the quick add order, mood notes, Explore's interest log, sleep places and the Longevity snapshot. They stay on the device.

When signed in, you can also keep a copy in your private storage on the project.

## Reading the files

NDJSON is one JSON object per line, so standard tools read it:

```bash
unzip soma-export-*.zip -d export
head -n 3 export/health/HKQuantityTypeIdentifierHeartRate.ndjson
```

The archive is named `soma-export-<day>.zip`. The file names in `health/` are the HealthKit identifiers, such as `HKQuantityTypeIdentifierRestingHeartRate`.

## Delete

**Signed in.** Settings, Data, Delete my data. The `delete-account` function removes your files from both storage buckets, then your account and every row stored with it. The app signs out and erases its local sync database, sleep places, rituals and the Longevity snapshot.

**Local mode.** Settings, Data, Erase data on this iPhone. It erases the journal, track logs, Mind data, sleep places, rituals, Explore's interest log and the Longevity snapshot. Profile, evening check-ins, tool answers and lab results stay until you delete the app.

**Apple Health.** Untouched in both cases. To take back Prism's access: Health app, your picture, Apps.

## Related

- [Use Prism without an account](use-prism-without-an-account.md)
- [PRIVACY.md](../../PRIVACY.md)
- [An open source Apple Health dashboard](open-source-apple-health-dashboard.md)
- [README](../../README.md)
