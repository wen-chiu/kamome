import KamomeImportKit

// The scenario list, apart from the places it is built from (file length).
extension RoutePathScenarios {
    static var all: [Scenario] {
        [
            // L — ordinary road trips that pass a place twice
            Scenario(name: "L1 one hotel, a day trip each day", photos:
                visit("htl1", lisbon, hour: 0) + visit("sin", sintra, hour: 3) + visit("htl2", lisbon, hour: 10)
                + visit("cas", cascais, hour: 27) + visit("htl3", lisbon, hour: 34)
                + visit("evo", evora, hour: 51) + visit("htl4", lisbon, hour: 58), form: .local),
            Scenario(name: "L2 out and back on one road", photos:
                visit("lis", lisbon, hour: 0) + visit("coi", coimbra, hour: 4) + visit("opo", porto, hour: 26)
                + visit("coi2", coimbra, hour: 50) + visit("lis2", lisbon, hour: 54), form: .local),
            Scenario(name: "L3 a loop back to where it began", photos:
                visit("lis", lisbon, hour: 0) + visit("evo", evora, hour: 4) + visit("coi", coimbra, hour: 28)
                + visit("lis2", lisbon, hour: 50), form: .local),

            // A — a flight abroad
            Scenario(name: "A1 airport photographs only, then a drive abroad", photos:
                visit("icn", incheon, hour: 0) + visit("cts", chitose, hour: 5, count: 2)
                + visit("spk", sapporo, hour: 7) + visit("otr", otaru, hour: 28)
                + visit("fur", furano, hour: 52) + visit("asa", asahikawa, hour: 55), form: .departure),
            Scenario(name: "A2 round trip: the flight home and home photographs", photos:
                visit("icn", incheon, hour: 0) + visit("cts", chitose, hour: 5, count: 2)
                + visit("spk", sapporo, hour: 7) + visit("otr", otaru, hour: 28)
                + visit("fur", furano, hour: 52) + visit("cts2", chitose, hour: 100, count: 2)
                + visit("icn2", incheon, hour: 105, count: 2) + visit("home", seoul, hour: 107, count: 2),
                form: .departure),
            Scenario(name: "A3 a drive to the airport, then abroad", photos:
                visit("seo", seoul, hour: 0) + visit("suw", suwon, hour: 3) + visit("icn", incheon, hour: 20)
                + visit("spk", sapporo, hour: 26) + visit("otr", otaru, hour: 30) + visit("fur", furano, hour: 52),
                form: .departure),
            Scenario(name: "A4 offline export: the flight left to pace alone (5 h gap)", photos:
                visit("icn", incheon, hour: 0) + visit("cts", chitose, hour: 5, count: 2)
                + visit("spk", sapporo, hour: 7) + visit("otr", otaru, hour: 28) + visit("fur", furano, hour: 52),
                routing: Geography(offline: true)),
            Scenario(name: "A5 offline export: a 3 h flight pace can call", photos:
                visit("icn", incheon, hour: 0) + visit("cts", chitose, hour: 3, count: 2)
                + visit("spk", sapporo, hour: 5) + visit("otr", otaru, hour: 28) + visit("fur", furano, hour: 52),
                routing: Geography(offline: true), form: .departure),

            // B — connections and domestic flights
            Scenario(name: "B1 connection: one photograph at the transit airport", photos:
                visit("icn", incheon, hour: 0) + visit("hnd", haneda, hour: 4, count: 1)
                + visit("cts", chitose, hour: 8) + visit("spk", sapporo, hour: 26) + visit("otr", otaru, hour: 50)
                + visit("cts2", chitose, hour: 80, count: 2) + visit("icn2", incheon, hour: 85, count: 2),
                form: .departure),
            Scenario(name: "B2 connection: a stop at the transit airport", photos:
                visit("icn", incheon, hour: 0) + visit("hnd", haneda, hour: 4)
                + visit("cts", chitose, hour: 8) + visit("spk", sapporo, hour: 26) + visit("otr", otaru, hour: 50),
                form: .departure),
            Scenario(name: "B3 a domestic flight inside the destination, then home", photos:
                visit("icn", incheon, hour: 0) + visit("hnd", haneda, hour: 3) + visit("tky", tokyo, hour: 5)
                + visit("ykh", yokohama, hour: 26) + visit("kmk", kamakura, hour: 29)
                + visit("hnd2", haneda, hour: 50, count: 2) + visit("cts", chitose, hour: 53, count: 2)
                + visit("spk", sapporo, hour: 55) + visit("otr", otaru, hour: 76)
                + visit("cts2", chitose, hour: 120, count: 2) + visit("icn2", incheon, hour: 123, count: 2),
                form: .departure),
            Scenario(name: "B4 domestic flight, photographs 10 h apart, a car ferry exists", photos:
                visit("icn", incheon, hour: 0) + visit("tky", tokyo, hour: 3) + visit("ykh", yokohama, hour: 26)
                + visit("spk", sapporo, hour: 36) + visit("otr", otaru, hour: 50) + visit("fur", furano, hour: 74),
                routing: Geography(ferries: [["hokkaido", "honshu"]]), form: .departure),
            Scenario(name: "B5 a fast train inside the destination (2.5 h, 370 km)", photos:
                visit("icn", incheon, hour: 0) + visit("tky", tokyo, hour: 3) + visit("ykh", yokohama, hour: 26)
                + visit("kyo", kyoto, hour: 30.5) + visit("osk", osaka, hour: 50), form: .departure),

            // C — several countries
            Scenario(name: "C1 three countries by air, then home", photos:
                visit("icn", incheon, hour: 0) + visit("tky", tokyo, hour: 3) + visit("ykh", yokohama, hour: 26)
                + visit("hnd", haneda, hour: 48, count: 2) + visit("bkk", suvarnabhumi, hour: 55, count: 2)
                + visit("bkc", bangkok, hour: 57) + visit("ayu", ayutthaya, hour: 76) + visit("hua", huaHin, hour: 100)
                + visit("bkk2", suvarnabhumi, hour: 140, count: 2) + visit("icn2", incheon, hour: 146, count: 2),
                form: .departure),
            Scenario(name: "C2 a road trip through four countries", photos:
                visit("lis", lisbon, hour: 0) + visit("opo", porto, hour: 6) + visit("sal", salamanca, hour: 28)
                + visit("mad", madrid, hour: 50) + visit("zgz", zaragoza, hour: 74) + visit("bcn", barcelona, hour: 98)
                + visit("mpl", montpellier, hour: 122) + visit("nce", nice, hour: 146) + visit("gen", genoa, hour: 170)
                + visit("mil", milan, hour: 194), form: .local),
            Scenario(name: "C3 Asia, then a long-haul to Europe and a drive across the Channel", photos:
                visit("icn", incheon, hour: 0) + visit("tky", tokyo, hour: 3) + visit("ykh", yokohama, hour: 26)
                + visit("hnd", haneda, hour: 48, count: 2) + visit("lhr", heathrow, hour: 62, count: 2)
                + visit("lon", london, hour: 64) + visit("oxf", oxford, hour: 86) + visit("dov", dover, hour: 110)
                + visit("cal", calais, hour: 113) + visit("par", paris, hour: 118)
                + visit("cdg", cdg, hour: 140, count: 2) + visit("icn2", incheon, hour: 153, count: 2),
                form: .departure),
            Scenario(name: "C4 Asia, then across 180° to Hawaii and on to the mainland", photos:
                visit("icn", incheon, hour: 0) + visit("tky", tokyo, hour: 3) + visit("ykh", yokohama, hour: 26)
                + visit("hnd", haneda, hour: 48, count: 2) + visit("hnl", honolulu, hour: 56, count: 2)
                + visit("wkk", waikiki, hour: 58) + visit("nsh", northShore, hour: 80)
                + visit("hnl2", honolulu, hour: 100, count: 2) + visit("lax", lax, hour: 106, count: 2)
                + visit("smo", santaMonica, hour: 108), form: .departure),

            // D — too few photographs, too far apart
            Scenario(name: "D1 two single photographs on one road (no stop)", photos:
                visit("lis", lisbon, hour: 0, count: 1) + visit("opo", porto, hour: 4, count: 1)),
            Scenario(name: "D2 two single photographs across the sea (no stop)", photos:
                visit("seo", seoul, hour: 0, count: 1) + visit("spk", sapporo, hour: 6, count: 1)),
            Scenario(name: "D3 one stop and nothing else", photos: visit("lis", lisbon, hour: 0, count: 2)),
            Scenario(name: "D4 two photographs, same place, same second", photos:
                [ImportPhoto(assetId: "a", timestamp: epoch, lat: lisbon.lat, lon: lisbon.lon),
                 ImportPhoto(assetId: "b", timestamp: epoch, lat: lisbon.lat, lon: lisbon.lon)]),
            Scenario(name: "D4b one place, one fix, three photographs an hour apart", photos:
                (0..<3).map {
                    ImportPhoto(assetId: "s\($0)", timestamp: epoch + Double($0) * 1800, lat: lisbon.lat, lon: lisbon.lon)
                }),
            Scenario(name: "D4c two stays at one place on two days, one fix", photos:
                (0..<4).map { ImportPhoto(assetId: "h\($0)", timestamp: epoch + Double($0 / 2) * 86_400 + Double($0 % 2) * 600,
                                          lat: lisbon.lat, lon: lisbon.lon) }),
            Scenario(name: "D4d one place, photographs a metre apart", photos:
                (0..<3).map { ImportPhoto(assetId: "m\($0)", timestamp: epoch + Double($0) * 1800,
                                          lat: lisbon.lat + Double($0) * 0.000009, lon: lisbon.lon) }),
            Scenario(name: "D4e one place, photographs a centimetre apart", photos:
                (0..<3).map { ImportPhoto(assetId: "c\($0)", timestamp: epoch + Double($0) * 1800,
                                          lat: lisbon.lat + Double($0) * 0.00000009, lon: lisbon.lon) }),
            Scenario(name: "D5 a stop every three days, hundreds of km apart", photos:
                visit("lis", lisbon, hour: 0, count: 2) + visit("mad", madrid, hour: 72, count: 2)
                + visit("bcn", barcelona, hour: 144, count: 2) + visit("nce", nice, hour: 216, count: 2),
                form: .local),
            Scenario(name: "D6 single photographs only, across a flight", photos:
                visit("seo", seoul, hour: 0, count: 1) + visit("suw", suwon, hour: 2, count: 1)
                + visit("spk", sapporo, hour: 8, count: 1) + visit("otr", otaru, hour: 10, count: 1)),
            Scenario(name: "D7 offline, and the sea crossed days apart", photos:
                visit("seo", seoul, hour: 0) + visit("suw", suwon, hour: 3)
                + visit("spk", sapporo, hour: 75) + visit("otr", otaru, hour: 78),
                routing: Geography(offline: true)),
            Scenario(name: "D8 a ferry with photographs taken at sea", photos:
                visit("pus", busan, hour: 0) + visit("sea1", strait1, hour: 2, count: 2)
                + visit("sea2", strait2, hour: 4, count: 2) + visit("fuk", fukuoka, hour: 6)
                + visit("osk", osaka, hour: 30)),
            Scenario(name: "D9 one photograph at home, then the destination a day later", photos:
                visit("seo", seoul, hour: 0, count: 1) + visit("spk", sapporo, hour: 26)
                + visit("otr", otaru, hour: 30) + visit("fur", furano, hour: 52)),

            // E — the far edges of the map
            Scenario(name: "E1 across 180° and back", photos:
                visit("icn", incheon, hour: 0) + visit("hnl", honolulu, hour: 9, count: 2) + visit("wkk", waikiki, hour: 11)
                + visit("nsh", northShore, hour: 34) + visit("hnl2", honolulu, hour: 80, count: 2)
                + visit("icn2", incheon, hour: 90, count: 2), form: .departure),
            Scenario(name: "E2 southern long-haul through a transit", photos:
                visit("syd", sydney, hour: 0) + visit("dxb", dubai, hour: 14, count: 1)
                + visit("lhr", heathrow, hour: 22) + visit("lon", london, hour: 24) + visit("oxf", oxford, hour: 48),
                form: .departure),
            Scenario(name: "E3 a domestic flight to the Arctic, then a drive north", photos:
                visit("osl", oslo, hour: 0) + visit("tos", tromso, hour: 2) + visit("alt", alta, hour: 26)
                + visit("nkp", northCape, hour: 50), form: .departure),
            Scenario(name: "E4 over the top: Seoul to New York", photos:
                visit("icn", incheon, hour: 0) + visit("jfk", newYork, hour: 14) + visit("man", manhattan, hour: 16)
                + visit("bos", boston, hour: 40), form: .departure)
        ]
    }
}
