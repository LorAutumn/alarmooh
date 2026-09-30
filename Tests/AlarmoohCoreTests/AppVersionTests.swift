import Testing
@testable import AlarmoohCore

@Test func taggedBuildShowsVersionAndBuildOnly() {
    #expect(
        AppVersion.display(shortVersion: "0.2.0", build: "57", gitDescription: "v0.2.0")
            == "Version 0.2.0 (Build 57)"
    )
}

/// Drei Commits nach dem Tag muss man es sehen koennen, sonst saehe der Stand
/// aus wie das Release.
@Test func buildAfterTagAppendsGitDescription() {
    #expect(
        AppVersion.display(shortVersion: "0.2.0", build: "60", gitDescription: "v0.2.0-3-gabc1234-dirty")
            == "Version 0.2.0 (Build 60) · v0.2.0-3-gabc1234-dirty"
    )
}

@Test func missingVersionIsReportedAsUnknown() {
    #expect(AppVersion.display(shortVersion: nil, build: nil, gitDescription: nil) == "Version unbekannt")
    #expect(AppVersion.display(shortVersion: "", build: "1", gitDescription: nil) == "Version unbekannt")
}

/// Gebaut ausserhalb von Git: nur die Werte aus dem Info.plist.
@Test func missingGitDescriptionShowsPlistValues() {
    #expect(AppVersion.display(shortVersion: "0.0.0", build: "0", gitDescription: nil) == "Version 0.0.0 (Build 0)")
}
