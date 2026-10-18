import CoreLocation
import Foundation

/// A city that can be added as a place.
struct City: Identifiable, Hashable {
    let name: String
    let country: String
    let zone: String
    let short: String
    var aliases: [String] = []
    var id: String { name + "|" + zone }
}

/// "San Francisco" → "SF", "Tokyo" → "TOK".
func shortLabel(_ name: String) -> String {
    let words = name.split { $0 == " " || $0 == "-" }.filter { $0.first?.isUppercase == true }
    if words.count > 1 { return String(words.prefix(3).compactMap(\.first)).uppercased() }
    return String(name.prefix(3)).uppercased()
}

enum Cities {
    /// Name | country | IANA zone | short label | other names. Offline and instant; the zone list
    /// and Apple Maps cover everywhere else.
    private static let table = """
    Bangalore|India|Asia/Kolkata|BLR|Bengaluru
    Mumbai|India|Asia/Kolkata|BOM|Bombay
    Delhi|India|Asia/Kolkata|DEL|New Delhi
    Gurgaon|India|Asia/Kolkata|GGN|Gurugram
    Chennai|India|Asia/Kolkata|MAA|Madras
    Kolkata|India|Asia/Kolkata|CCU|Calcutta
    Hyderabad|India|Asia/Kolkata|HYD
    Pune|India|Asia/Kolkata|PNQ
    Ahmedabad|India|Asia/Kolkata|AMD
    Kochi|India|Asia/Kolkata|COK|Cochin
    Goa|India|Asia/Kolkata|GOI
    Karachi|Pakistan|Asia/Karachi|KHI
    Lahore|Pakistan|Asia/Karachi|LHE
    Islamabad|Pakistan|Asia/Karachi|ISB
    Dhaka|Bangladesh|Asia/Dhaka|DAC
    Colombo|Sri Lanka|Asia/Colombo|CMB
    Kathmandu|Nepal|Asia/Kathmandu|KTM
    Thimphu|Bhutan|Asia/Thimphu|THI
    Malé|Maldives|Indian/Maldives|MLE|Male
    Singapore|Singapore|Asia/Singapore|SIN
    Kuala Lumpur|Malaysia|Asia/Kuala_Lumpur|KL
    Jakarta|Indonesia|Asia/Jakarta|JKT
    Bali|Indonesia|Asia/Makassar|DPS|Denpasar
    Bangkok|Thailand|Asia/Bangkok|BKK
    Ho Chi Minh City|Vietnam|Asia/Ho_Chi_Minh|SGN|Saigon
    Hanoi|Vietnam|Asia/Ho_Chi_Minh|HAN
    Manila|Philippines|Asia/Manila|MNL
    Yangon|Myanmar|Asia/Yangon|RGN|Rangoon
    Phnom Penh|Cambodia|Asia/Phnom_Penh|PNH
    Hong Kong|China|Asia/Hong_Kong|HK
    Shanghai|China|Asia/Shanghai|SHA
    Beijing|China|Asia/Shanghai|BJS|Peking
    Shenzhen|China|Asia/Shanghai|SZX
    Taipei|Taiwan|Asia/Taipei|TPE
    Seoul|South Korea|Asia/Seoul|SEL
    Tokyo|Japan|Asia/Tokyo|TYO
    Osaka|Japan|Asia/Tokyo|OSA
    Ulaanbaatar|Mongolia|Asia/Ulaanbaatar|ULN
    Almaty|Kazakhstan|Asia/Almaty|ALA
    Tashkent|Uzbekistan|Asia/Tashkent|TAS
    Dubai|United Arab Emirates|Asia/Dubai|DXB
    Abu Dhabi|United Arab Emirates|Asia/Dubai|AUH
    Doha|Qatar|Asia/Qatar|DOH
    Riyadh|Saudi Arabia|Asia/Riyadh|RUH
    Jeddah|Saudi Arabia|Asia/Riyadh|JED
    Muscat|Oman|Asia/Muscat|MCT
    Kuwait City|Kuwait|Asia/Kuwait|KWI
    Manama|Bahrain|Asia/Bahrain|BAH|Bahrain
    Tel Aviv|Israel|Asia/Jerusalem|TLV
    Jerusalem|Israel|Asia/Jerusalem|JRS
    Amman|Jordan|Asia/Amman|AMM
    Beirut|Lebanon|Asia/Beirut|BEY
    Tehran|Iran|Asia/Tehran|THR
    Istanbul|Türkiye|Europe/Istanbul|IST
    London|United Kingdom|Europe/London|LON
    Edinburgh|United Kingdom|Europe/London|EDI
    Manchester|United Kingdom|Europe/London|MAN
    Dublin|Ireland|Europe/Dublin|DUB
    Paris|France|Europe/Paris|PAR
    Brussels|Belgium|Europe/Brussels|BRU
    Amsterdam|Netherlands|Europe/Amsterdam|AMS
    The Hague|Netherlands|Europe/Amsterdam|HAG
    Luxembourg|Luxembourg|Europe/Luxembourg|LUX
    Berlin|Germany|Europe/Berlin|BER
    Frankfurt|Germany|Europe/Berlin|FRA
    Munich|Germany|Europe/Berlin|MUC
    Zurich|Switzerland|Europe/Zurich|ZRH
    Geneva|Switzerland|Europe/Zurich|GVA
    Vienna|Austria|Europe/Vienna|VIE
    Rome|Italy|Europe/Rome|ROM
    Milan|Italy|Europe/Rome|MIL
    Madrid|Spain|Europe/Madrid|MAD
    Barcelona|Spain|Europe/Madrid|BCN
    Lisbon|Portugal|Europe/Lisbon|LIS
    Copenhagen|Denmark|Europe/Copenhagen|CPH
    Stockholm|Sweden|Europe/Stockholm|STO
    Oslo|Norway|Europe/Oslo|OSL
    Helsinki|Finland|Europe/Helsinki|HEL
    Tallinn|Estonia|Europe/Tallinn|TLL
    Warsaw|Poland|Europe/Warsaw|WAW
    Prague|Czechia|Europe/Prague|PRG
    Budapest|Hungary|Europe/Budapest|BUD
    Athens|Greece|Europe/Athens|ATH
    Bucharest|Romania|Europe/Bucharest|BUH
    Kyiv|Ukraine|Europe/Kyiv|KYV|Kiev
    Moscow|Russia|Europe/Moscow|MOW
    Reykjavik|Iceland|Atlantic/Reykjavik|REK
    Cairo|Egypt|Africa/Cairo|CAI
    Lagos|Nigeria|Africa/Lagos|LOS
    Accra|Ghana|Africa/Accra|ACC
    Nairobi|Kenya|Africa/Nairobi|NBO
    Addis Ababa|Ethiopia|Africa/Addis_Ababa|ADD
    Kigali|Rwanda|Africa/Kigali|KGL
    Johannesburg|South Africa|Africa/Johannesburg|JNB
    Cape Town|South Africa|Africa/Johannesburg|CPT
    Casablanca|Morocco|Africa/Casablanca|CAS
    Port Louis|Mauritius|Indian/Mauritius|MRU|Mauritius
    New York|United States|America/New_York|NYC|NY|Manhattan
    Boston|United States|America/New_York|BOS
    Washington, DC|United States|America/New_York|DC|Washington
    Philadelphia|United States|America/New_York|PHL
    Atlanta|United States|America/New_York|ATL
    Miami|United States|America/New_York|MIA
    Cleveland|United States|America/New_York|CLE
    Pittsburgh|United States|America/New_York|PIT
    Detroit|United States|America/Detroit|DTW
    Toronto|Canada|America/Toronto|YYZ
    Montreal|Canada|America/Toronto|YUL
    Ottawa|Canada|America/Toronto|YOW
    Halifax|Canada|America/Halifax|YHZ
    St. John's|Canada|America/St_Johns|YYT
    Chicago|United States|America/Chicago|CHI
    Dallas|United States|America/Chicago|DFW
    Houston|United States|America/Chicago|HOU
    Austin|United States|America/Chicago|AUS
    Minneapolis|United States|America/Chicago|MSP
    Denver|United States|America/Denver|DEN
    Salt Lake City|United States|America/Denver|SLC
    Calgary|Canada|America/Edmonton|YYC
    Phoenix|United States|America/Phoenix|PHX
    Los Angeles|United States|America/Los_Angeles|LA
    San Francisco|United States|America/Los_Angeles|SF|Silicon Valley
    San Jose|United States|America/Los_Angeles|SJC
    Seattle|United States|America/Los_Angeles|SEA
    Portland|United States|America/Los_Angeles|PDX
    Las Vegas|United States|America/Los_Angeles|LAS
    Vancouver|Canada|America/Vancouver|YVR
    Anchorage|United States|America/Anchorage|ANC
    Honolulu|United States|Pacific/Honolulu|HNL|Hawaii
    Mexico City|Mexico|America/Mexico_City|MEX
    Panama City|Panama|America/Panama|PTY
    Bogotá|Colombia|America/Bogota|BOG|Bogota
    Lima|Peru|America/Lima|LIM
    Caracas|Venezuela|America/Caracas|CCS
    Santiago|Chile|America/Santiago|SCL
    Buenos Aires|Argentina|America/Argentina/Buenos_Aires|BUE
    São Paulo|Brazil|America/Sao_Paulo|SAO|Sao Paulo
    Rio de Janeiro|Brazil|America/Sao_Paulo|RIO
    Sydney|Australia|Australia/Sydney|SYD
    Canberra|Australia|Australia/Sydney|CBR
    Melbourne|Australia|Australia/Melbourne|MEL
    Brisbane|Australia|Australia/Brisbane|BNE
    Adelaide|Australia|Australia/Adelaide|ADL
    Perth|Australia|Australia/Perth|PER
    Auckland|New Zealand|Pacific/Auckland|AKL
    Wellington|New Zealand|Pacific/Auckland|WLG
    Fiji|Fiji|Pacific/Fiji|SUV|Suva
    """

    static let curated: [City] = table.split(separator: "\n").compactMap { line in
        let f = line.trimmingCharacters(in: .whitespaces).split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        guard f.count >= 4, TimeZone(identifier: f[2]) != nil else { return nil }
        return City(name: f[0], country: f[1], zone: f[2], short: f[3], aliases: Array(f.dropFirst(4)))
    }

    /// Every zone macOS knows, named after its city ("America/Argentina/Cordoba" → Cordoba).
    static let zones: [City] = TimeZone.knownTimeZoneIdentifiers.compactMap { id in
        let parts = id.split(separator: "/")
        guard parts.count >= 2, !["Etc", "SystemV", "US", "Canada", "Brazil", "Chile", "Mexico"].contains(String(parts[0])) else { return nil }
        let name = parts.last!.replacingOccurrences(of: "_", with: " ")
        return City(name: name, country: String(parts[0]), zone: id, short: shortLabel(name))
    }

    /// Curated cities first (name, then other names, then country), then the zone list.
    static func search(_ q: String) -> [City] {
        let q = q.trimmingCharacters(in: .whitespaces).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        guard !q.isEmpty else { return [] }
        func fold(_ s: String) -> String { s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil) }
        func words(_ s: String) -> Bool { fold(s).split(separator: " ").contains { $0.hasPrefix(q) } || fold(s).hasPrefix(q) }
        var out: [City] = []
        out += curated.filter { words($0.name) }
        out += curated.filter { c in !out.contains(c) && c.aliases.contains(where: words) }
        out += curated.filter { c in !out.contains(c) && fold(c.country).hasPrefix(q) }
        let names = Set(out.map { fold($0.name) })
        out += zones.filter { !names.contains(fold($0.name)) && words($0.name) }
        return out
    }

    /// Anywhere else: Apple's geocoder knows the time zone of almost any town. Sends the
    /// typed text to Apple; used only when he asks.
    static func lookUp(_ q: String) async -> [City] {
        let marks = (try? await CLGeocoder().geocodeAddressString(q)) ?? []
        return marks.compactMap { m in
            guard let tz = m.timeZone else { return nil }
            let name = m.locality ?? m.name ?? q
            return City(name: name, country: m.country ?? "", zone: tz.identifier, short: shortLabel(name))
        }
    }
}
