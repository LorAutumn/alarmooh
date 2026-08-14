import AppKit

/// Das Menueleisten-Symbol von alarmooh: eine japanische Tempelglocke (bonsho),
/// als Template-Bild in Code gezeichnet — genau wie der Alarmton in Code
/// erzeugt wird, damit die App ohne Asset-Dateien auskommt.
///
/// Alles entsteht in einem NORMIERTEN Koordinatensystem:
///     x in [-0.5, +0.5]  (0 = senkrechte Mittelachse)
///     y in [ 0.0,  1.0]  (0 = Unterkante, y waechst nach oben)
/// Die CTM bildet das auf ein Quadrat von S x S Punkten ab; die Geometrie ist
/// damit aufloesungsunabhaengig. Von der Skalierung haengt nur das Einrasten
/// (Snapping) waagerechter Kanten und Strichbreiten auf ganze Geraetepixel ab.
///
/// ACHTUNG, das ist keine Mikro-Optimierung, sondern der Grund, warum das Bild
/// bei 18 pt ueberhaupt lesbar ist: ohne das Einrasten der Wandstaerke sinkt die
/// Deckung pro Zeile von 6,0 auf 5,2 Pixel und der Anteil weicher Zwischentoene
/// steigt von 9 % auf ~11 %; die beiden 2-px-Linien des Bandes verschmelzen zu
/// einem einzigen Balken, und das Loch in der Aufhaengung faellt der
/// Kantenglaettung zum Opfer. Wer die `snap...`-Aufrufe oder die auf ganze
/// Pixel gerundeten Strichbreiten "aufraeumt", zerstoert das Symbol.
enum BellIcon {

    // ─────────────────────────────────────────────────────────────── Geometrie

    /// Alle Masse normiert. Die Kommentare halten fest, WARUM ein Wert so ist —
    /// sie sind das Ergebnis einer Abstimmung am 36-px-Rendering.
    private struct Geom {
        var stroke: CGFloat = 0.072   // normierte Strichbreite

        // Rand (koma-no-tsume): ein massiver, leicht ueberbreiter Balken — das
        // ist der Hinweis auf den "flachen Rand" der Tempelglocke.
        var rimBottom: CGFloat = 0.065
        var rimTop: CGFloat = 0.145
        var rimHalf: CGFloat = 0.378      // halbe Breite ganz unten
        var rimHalfTop: CGFloat = 0.359   // halbe Breite, wo der Rand die Wand trifft

        // Koerper: fast senkrechte Wand mit nur leichter Ausstellung — DAS ist
        // das Merkmal, das eine bonsho von einer europaeischen Handglocke
        // unterscheidet (die hat einen geschwungenen Rock).
        var bodyBotHalf: CGFloat = 0.322   // Wandmitte am Rand
        var bodyTopHalf: CGFloat = 0.272   // Wandmitte an der Schulter
        var shoulderY: CGFloat = 0.620

        // Haube (kasagata): breit und flach, kein eingeschnuerter Pilz.
        var domeTopY: CGFloat = 0.842
        var domeFlat: CGFloat = 0.140   // x-Bereich, ueber den die Haube abflacht
        var domeRise: CGFloat = 0.58    // wie spaet die Schulter einzudrehen beginnt

        // Aufhaengung (ryuzu)
        var loopHalf: CGFloat = 0.082
        var loopStroke: CGFloat = 0.056   // bewusst duenner, damit das Loch offen bleibt
        var loopTopY: CGFloat = 0.980
        var loopSink: CGFloat = 0.018     // wie tief die Schenkel in der Haube stecken

        // Waagerechtes Band ueber dem Rand
        var bandY: CGFloat = 0.300      // Mitte des Bandes
        var bandPitch: CGFloat = 0.112  // Abstand der beiden Bandlinien

        /// Die Zeichnung reicht von y 0,048 bis 0,980, sitzt also hoch im
        /// Quadrat. Um ganze Geraetepixel nach unten schieben, damit sie mittig
        /// sitzt — um ganze Pixel, sonst verwaschen alle waagerechten Kanten.
        var yNudge: CGFloat = -0.022

        // Schlagbuckel (tsuki-za)
        var bossR: CGFloat = 0.058
    }

    /// Zwei parallele Linien im Band. Mehr Linien ueberleben 18 pt nicht.
    private static let bandLines = 2

    /// Halbe Koerperbreite auf Hoehe `y` (lineare Ausstellung).
    private static func bodyHalf(_ y: CGFloat, _ g: Geom) -> CGFloat {
        let t = max(0, min(1, (y - g.rimTop) / (g.shoulderY - g.rimTop)))
        return g.bodyBotHalf + (g.bodyTopHalf - g.bodyBotHalf) * t
    }

    // ──────────────────────────────────────────────── Einrasten auf Pixelraster

    /// Rastet die MITTELLINIE eines waagerechten Strichs so ein, dass seine
    /// Kanten auf ganzen Geraetepixeln landen. `u` ist ein Geraetepixel,
    /// ausgedrueckt in normierten Einheiten.
    private static func snapLine(_ y: CGFloat, width: CGFloat, u: CGFloat) -> CGFloat {
        let wpx = width / u
        let n = max(1.0, wpx.rounded())
        let yp = y / u
        // gerade Breite -> Mitte auf eine Pixelgrenze; ungerade -> auf halbes Pixel
        let target = n.truncatingRemainder(dividingBy: 2) == 0
            ? yp.rounded()
            : (yp - 0.5).rounded() + 0.5
        return target * u
    }

    /// Rastet eine Kante (keine Mittellinie) auf das Pixelraster ein.
    private static func snapEdge(_ y: CGFloat, u: CGFloat) -> CGFloat { (y / u).rounded() * u }

    // ──────────────────────────────────────────────────────────────── Konturen

    /// Wand und Haube als EIN offener Pfad: rechte Wand hoch, ueber die Haube,
    /// linke Wand hinunter. Unten schliesst der massive Randbalken statt einer
    /// Linie ab.
    private static func bellOutline(_ g: Geom) -> NSBezierPath {
        let p = NSBezierPath()
        let c1y = g.shoulderY + (g.domeTopY - g.shoulderY) * g.domeRise

        // Die Wand laeuft ein Stueck IN den Randbalken hinein, damit nach dem
        // Einrasten keine Ein-Pixel-Naht zwischen beiden stehen bleibt.
        p.move(to: CGPoint(x: g.bodyBotHalf, y: g.rimTop - g.stroke))
        p.line(to: CGPoint(x: g.bodyTopHalf, y: g.shoulderY))
        p.curve(
            to: CGPoint(x: 0, y: g.domeTopY),
            controlPoint1: CGPoint(x: g.bodyTopHalf, y: c1y),
            controlPoint2: CGPoint(x: g.domeFlat, y: g.domeTopY)
        )
        p.curve(
            to: CGPoint(x: -g.bodyTopHalf, y: g.shoulderY),
            controlPoint1: CGPoint(x: -g.domeFlat, y: g.domeTopY),
            controlPoint2: CGPoint(x: -g.bodyTopHalf, y: c1y)
        )
        p.line(to: CGPoint(x: -g.bodyBotHalf, y: g.rimTop - g.stroke))
        return p
    }

    /// Massiver, leicht ueberbreiter Balken am Fuss. Gefuellt statt umrandet:
    /// bei 36 px liefe eine Umrandung ohnehin voll, und eine Fuellung ist in
    /// jeder Groesse scharf.
    private static func rimPath(_ g: Geom) -> NSBezierPath {
        let p = NSBezierPath()
        p.move(to: CGPoint(x: -g.rimHalf, y: g.rimBottom))
        p.line(to: CGPoint(x: g.rimHalf, y: g.rimBottom))
        p.line(to: CGPoint(x: g.rimHalfTop, y: g.rimTop))
        p.line(to: CGPoint(x: -g.rimHalfTop, y: g.rimTop))
        p.close()
        return p
    }

    private static func loopPath(_ g: Geom) -> NSBezierPath {
        let p = NSBezierPath()
        let cy = g.loopTopY - g.loopHalf
        let base = g.domeTopY - g.loopSink
        p.move(to: CGPoint(x: -g.loopHalf, y: base))
        p.line(to: CGPoint(x: -g.loopHalf, y: cy))
        p.appendArc(
            withCenter: CGPoint(x: 0, y: cy), radius: g.loopHalf,
            startAngle: 180, endAngle: 0, clockwise: true
        )
        p.line(to: CGPoint(x: g.loopHalf, y: base))
        return p
    }

    /// Die beiden Bandlinien. Ihre Mitten werden EINZELN eingerastet — nur so
    /// bleibt bei 18 pt @2x zwischen zwei 2-px-Linien eine 2-px-Luecke stehen;
    /// ungerastet verschmelzen sie zu einem Balken.
    private static func bandPaths(_ g: Geom, width w: CGFloat, u: CGFloat) -> NSBezierPath {
        let p = NSBezierPath()
        for i in 0..<bandLines {
            let off = (CGFloat(i) - CGFloat(bandLines - 1) / 2) * g.bandPitch
            let y = snapLine(g.bandY + off, width: w, u: u)
            let h = bodyHalf(y, g) + g.stroke / 2   // bis in die Waende hinein
            p.move(to: CGPoint(x: -h, y: y))
            p.line(to: CGPoint(x: h, y: y))
        }
        return p
    }

    // ──────────────────────────────────────────────────────────── Maske zeichnen

    /// Zeichnet die ALPHAMASKE des Symbols (deckendes Weiss auf durchsichtig) —
    /// mehr ist ein macOS-Template-Bild nicht.
    ///
    /// `side` ist die Kantenlaenge in Punkten, `scale` der Backing-Faktor des
    /// Bildschirms. Beides zusammen ergibt die Pixelgroesse UND das Raster, auf
    /// das eingerastet wird; deshalb muss fuer jede Skalierung neu gezeichnet
    /// werden, statt ein Bild zu skalieren.
    private static func renderMask(side: CGFloat, scale: CGFloat, paused: Bool) -> NSBitmapImageRep {
        let px = Int((side * scale).rounded())
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
            isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0
        )!

        let g = Geom()
        let u = 1.0 / (side * scale)   // ein Geraetepixel in normierten Einheiten

        let ctx = NSGraphicsContext(bitmapImageRep: rep)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ctx
        let cg = ctx.cgContext
        cg.setShouldAntialias(true)
        cg.saveGState()
        cg.translateBy(x: side * scale / 2, y: 0)
        cg.scaleBy(x: side * scale, y: side * scale)
        cg.translateBy(x: 0, y: (g.yNudge / u).rounded() * u)   // nur ganze Pixel

        NSColor.white.setStroke()
        NSColor.white.setFill()

        func stroked(
            _ p: NSBezierPath, _ w: CGFloat = g.stroke,
            cap: NSBezierPath.LineCapStyle = .round,
            join: NSBezierPath.LineJoinStyle = .round
        ) {
            p.lineWidth = w
            p.lineCapStyle = cap
            p.lineJoinStyle = join
            p.stroke()
        }

        // 1. Rand — massiver Balken, beide Kanten auf ganze Geraetepixel gerastet
        var gg = g
        gg.rimBottom = snapEdge(g.rimBottom, u: u)
        gg.rimTop = max(gg.rimBottom + 2 * u, snapEdge(g.rimTop, u: u))
        rimPath(gg).fill()

        // 2. Wand und Haube. Die Waende stehen fast senkrecht; eine gebrochene
        //    Strichbreite laesst sie dauerhaft weich aussehen. Die Breite auf
        //    ganze Geraetepixel runden (klassisches Hinting) bringt bei 36 px
        //    die Deckung pro Zeile von 5,2 auf 6,0 Pixel.
        let wallW = max(1 * u, (g.stroke / u).rounded() * u)
        stroked(bellOutline(gg), wallW, cap: .butt, join: .round)

        // 3. Aufhaengung — Strichbreite ebenfalls auf ganze Geraetepixel, damit
        //    das kleine Loch im Bogen nicht von der Kantenglaettung
        //    zugeschmiert wird.
        stroked(loopPath(g), max(1 * u, (g.loopStroke / u).rounded() * u))

        // 4. Band
        let bandW = max(1 * u, (g.stroke * 0.90 / u).rounded() * u)
        stroked(bandPaths(g, width: bandW, u: u), bandW, cap: .butt)

        // 5. Schlagbuckel — aus dem Band ausgestanzt, damit er ein RUNDES
        //    Ereignis bleibt und kein Klumpen, der an einer Geraden klebt.
        let gap = max(1.0 * u, g.stroke * 0.30)
        let r = g.bossR + gap
        cg.setBlendMode(.clear)
        NSBezierPath(ovalIn: CGRect(x: -r, y: g.bandY - r, width: 2 * r, height: 2 * r)).fill()
        cg.setBlendMode(.normal)
        NSColor.white.setFill()
        NSColor.white.setStroke()
        NSBezierPath(ovalIn: CGRect(
            x: -g.bossR, y: g.bandY - g.bossR,
            width: g.bossR * 2, height: g.bossR * 2
        )).fill()

        // 6. Pausiert: erst eine durchsichtige Schneise ausstanzen, dann den
        //    Balken hineinlegen — sonst klebt er an Wand und Haube fest.
        if paused {
            // Richtung wie bei SF Symbols `.slash` (nachgemessen: faellt von
            // links nach rechts).
            let a = CGPoint(x: -0.400, y: 0.945)
            let b = CGPoint(x: 0.400, y: 0.055)
            let slash = NSBezierPath()
            slash.move(to: a)
            slash.line(to: b)

            let air = max(g.stroke * 0.65, 2.0 * u)   // mindestens 2 Geraetepixel Luft je Seite
            cg.setBlendMode(.clear)
            slash.lineWidth = wallW + air * 2
            slash.lineCapStyle = .round
            slash.stroke()
            cg.setBlendMode(.normal)

            NSColor.white.setStroke()
            stroked(slash, wallW)
        }

        cg.restoreGState()
        NSGraphicsContext.restoreGraphicsState()

        // Erst JETZT die Punktgroesse eintragen. Sie ist die Angabe, aus der
        // NSImage den Backing-Faktor der Repraesentation ableitet (Pixel geteilt
        // durch Punkte). Vorher gesetzt wuerde sie den Zeichenkontext selbst
        // skalieren und unsere Rechnung in Geraetepixeln verdoppeln.
        rep.size = NSSize(width: side, height: side)
        return rep
    }

    // ───────────────────────────────────────────────────────────────── Ausgabe

    /// Backing-Faktoren, fuer die eine eigene Bitmap entsteht. macOS meldet
    /// heute nur 1 und 2 — auch skalierte Aufloesungen ("sieht aus wie
    /// 1440x900") rendern mit Faktor 2 und werden erst vom Compositor
    /// verkleinert. 3 liegt fuer den Fall bei, dass doch einmal ein Bildschirm
    /// mit Faktor 3 auftaucht; sonst waere er der einzige, der ein
    /// hochskaliertes 2x-Bild und damit weiche Kanten bekaeme.
    private static let scales: [CGFloat] = [1, 2, 3]

    /// Das fertige Template-Bild fuer die Menueleiste.
    ///
    /// Bewusst KEIN `NSImage(size:flipped:drawingHandler:)`: der Handler wuerde
    /// in Punkten zeichnen, und AppKit rasterte das Ergebnis mit einem Faktor,
    /// den die Zeichnung nicht kennt — das Einrasten wuerde also auf das
    /// falsche Raster rechnen. Stattdessen traegt das Bild fuer jeden
    /// Backing-Faktor eine eigene, fuer genau dieses Raster gezeichnete Bitmap;
    /// AppKit sucht sich daraus die passende aus.
    static func statusItemImage(paused: Bool, pointSize: CGFloat = 18) -> NSImage {
        let image = NSImage(size: NSSize(width: pointSize, height: pointSize))
        for scale in scales {
            image.addRepresentation(renderMask(side: pointSize, scale: scale, paused: paused))
        }
        // Template: macOS wirft die Farben weg und faerbt allein nach Alpha —
        // hell oder dunkel je nach Menueleiste, rot waehrend eines Alarms.
        image.isTemplate = true
        image.accessibilityDescription = paused
            ? "alarmooh: Alarme pausiert"
            : "alarmooh: Alarme aktiv"
        return image
    }
}
