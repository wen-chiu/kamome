# The boarding pass names its countries from Apple's answer for the stops, not a table

**Status:** Decided (Chiu, 2026-10-03)
**Supersedes:** ledger entries "2026-09-02" and "2026-09-04 (b)" §5, only where they take the boarding pass's and the flight-end marks' country names from `CountryExtent`

## Context

A Taiwan → Vietnam film flew its plane with no boarding pass. Its diagnostics
said *"journey card: no country extent covers the `<private>` end of the
crossing — drawing no card"* (VERIFIED, Chiu's export of 2026-10-03). The pass
named both ends from `CountryExtent`, a built-in table of six countries (TW, IS,
FI, NZ, JP, AU), so any other country got no pass. The log line's
`<private>` was the default redaction hiding the one word it was there for.
The departing stop in that film sits at sea (INFERRED from the screenshot: a
photograph taken from the aircraft), where no country can be named.

Stop naming already asks Apple about every stop (the §0 exception of 2026-09-17),
and `CLPlacemark.isoCountryCode` came back with every answer and was dropped.

## Decision

Chiu: *「就直接去問 apple 停留點國名就好，內建的表不合理，改好」*.

- **A stop keeps its country**: schema v16 `stop.country_code`, from the same
  lookup that names it. NULL = never asked (back-filled on the trip's next open,
  like v9's towns); "" = asked, none (open sea). Nothing new leaves the phone.
- **A crossing's two countries are the nearest stops *with* a country**: the
  last reached before the crossing began, the first reached after. A stop at sea
  is skipped, not printed (`RecapComposer.crossingCountryCodes`).
- The pass and the flight-end marks print them; the words are the system's
  (`Locale.localizedString(forRegionCode:)`), English first. An end with no
  country still draws no pass, and says which end, in clear.

## Rejected

- Add VN (and every next country) to `CountryExtent` — one row per trip that
  surprises us, and a box is a poor answer to "which country is this point in".
- A new country-only lookup at export — a second request per stop when the one
  already sent answers it.

## Consequences

- `CountryExtent` stays, **for the opening's framing only**: that needs a
  country's *extent*, which Apple does not give. Its other gap — a trip outside
  the six rows opens on its own bounds — is unchanged.
- A trip named before v16 gets its countries when Trip Detail is next opened;
  an export before that finishes draws no pass and logs it.
- The hermetic desk harness stands in for Apple with `CountryExtent`'s boxes
  (`RecapDemoFilmTests.stampCountries`); `KAMOME_GEOCODE_STOPS=1` asks Apple.
