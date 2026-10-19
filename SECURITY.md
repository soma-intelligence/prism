# Security

## Reporting a problem

Write to **security@somalabs.me**. Please don't open a public issue, pull request or discussion for a security problem.

Tell us what you found, how to reproduce it, and what it lets someone do. A short proof of concept helps. Don't include anyone's real health data: use simulated data, as the app's own seeding tools produce.

## What happens next

- We confirm we've received your report.
- We work on a fix and keep you posted.
- We disclose 90 days after your report, or sooner when a fix has shipped. If a fix needs longer, we'll agree a date with you.

## In scope

- The app in this repository, on iPhone, iPad, Mac and Vision Pro.
- The packages in `Packages/`.
- The backend in `supabase/`: migrations, row level security, storage policies and Edge Functions.
- Soma cloud, the hosted copy of that backend, when the problem lies in this code or its configuration.

## Out of scope

- Self hosted deployments run by someone else. Report those to whoever runs them, and to us if the cause is in this code.
- Problems that need a jailbroken device or physical access to an unlocked one.
- Denial of service by sheer volume, and social engineering.

## Testing against Soma cloud

Use an account of your own and only your own data. Don't read, change or delete other people's data, and stop and write to us as soon as you see something that isn't yours. Better still, test against a project you host yourself ([docs/SELF_HOSTING.md](docs/SELF_HOSTING.md)).
