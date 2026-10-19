# Roadmap

This is the work we know about, read from the code as it stands. None of it has a date. If you want to pick something up, open an issue first so two people don't build the same thing.

## Next

- **Direct Oura, Whoop and Withings connections.** The sign in flows are written (`App/Prism/Core/Providers`) and switched off in this build: `ProviderConfig.clientIDs` is empty, so Settings, Health access shows them as "Soon". Turning them on means registering Prism with each service and filling in those ids. Until then, Prism reads these brands through Apple Health wherever their apps write there.
- **Email sign in.** The email and password screens, and the recovery screen, are written but hidden: `OnboardingSignInOptions.offersEmail` in `App/Prism/Features/Onboarding/OnboardingSignIn.swift` is off, because no account service can sign anyone in with an address and password yet. Until it lands, Sign in with Apple is the only sign in, and "Not now" keeps everything on the device.
- **Restoring a new phone.** Signing in on a new phone pulls your records into the sync database, but the journal, track and mind stores don't read them back yet (`supabase/README.md`, "Not done yet").
- **Weather for the sun and skin tools.** Sun Budget and Skin Forecast have no weather source yet and show a dash (`App/Prism/Features/Tools/ToolWeather.swift`). The Environment card's Open-Meteo reader could feed them.
- **Pages marked "not wired".** A few destinations open a placeholder that says so, among them parts of Ask, training sessions and visit results. Search for `NotWiredPage(` to find them.

## In progress

- An Android version is in development.

## Also open

- Push notifications. The `devices.push_token` column is waiting for APNs.

## Not in this build

- An Apple Watch app.
- A web version.
- Medical features. Prism is a wellness app and makes no diagnostic or treatment claims.
