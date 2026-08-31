import Foundation

// Evolution-line completion vs. holding singles — opportunity-cost analysis.
//
// Answers: in the Gauntlet showcase, how much Aura does *completing* an evolution
// line earn, versus filling the same slots with the best singles you could have
// kept instead (the "most valuable card from each pack")?
//
// It scores every scenario through the REAL engine — `GauntletRun.aura` on real
// `CardInstance`s built from the shipped catalogue — so results match play exactly.
// Base market value only: foil (×3 @1%) and opt-in grading are proportional upside
// available to *both* strategies, so they cancel in every ratio below and only add
// noise. auraMult likewise scales everything equally; the neutral run (auraMult 1,
// evoLineBonusBonus 0) is the clean lens. A closing section adds back an
// evoLineBonusBonus (a Trainer/Catalyst evo-bonus boost) to show how it moves things.

// MARK: - Helpers

func money(_ v: Double) -> String { String(format: "%.2f", v) }
func pad(_ s: String, _ w: Int) -> String {
    s.count >= w ? s : s + String(repeating: " ", count: w - s.count)
}
func lpad(_ s: String, _ w: Int) -> String {
    s.count >= w ? s : String(repeating: " ", count: w - s.count) + s
}
func median(_ xs: [Double]) -> Double {
    guard !xs.isEmpty else { return 0 }
    let s = xs.sorted()
    let n = s.count
    return n % 2 == 1 ? s[n / 2] : (s[n / 2 - 1] + s[n / 2]) / 2
}

// Score any bag of cards through the real Aura engine at neutral mods.
func aura(_ cards: [Card], evoBonusBonus: Double = 0, auraMult: Double = 1) -> Double {
    let insts = cards.map { CardInstance(cardId: $0.id) }
    return GauntletRun.aura(insts, evoLineBonusBonus: evoBonusBonus, auraMult: auraMult)
}
func baseSum(_ cards: [Card]) -> Double { cards.reduce(0) { $0 + $1.baseValue } }

// MARK: - Per-set data

struct SetData {
    let set: Int
    let name: String
    let bonus: Double            // evoLineBonus(set:)
    let rares: [Card]            // sorted by baseValue asc (7)
    let ultras: [Card]           // sorted by baseValue asc (3)
    let threeLines: [[Card]]     // each sorted by stage (6)
    let twoLines: [[Card]]       // each sorted by stage (7)
}

func loadSet(_ s: Int) -> SetData {
    let cards = CardDatabase.cards(inSet: s)
    let rares  = cards.filter { $0.rarity == .rare  }.sorted { $0.baseValue < $1.baseValue }
    let ultras = cards.filter { $0.rarity == .ultra }.sorted { $0.baseValue < $1.baseValue }
    let lines = CardDatabase.evolutionLines.values.filter { $0.first?.set == s }
    let three = lines.filter { $0.count == 3 }.sorted { baseSum($0) < baseSum($1) }
    let two   = lines.filter { $0.count == 2 }.sorted { baseSum($0) < baseSum($1) }
    return SetData(set: s, name: CardDatabase.setName(s),
                   bonus: GauntletEconomy.evoLineBonus(set: s),
                   rares: rares, ultras: ultras, threeLines: three, twoLines: two)
}

let sets = (1...CardDatabase.setCount).map(loadSet)

// MARK: - Header

print("=====================================================================")
print(" Evolution-line completion vs. holding singles — opportunity cost")
print(" Scored via the real GauntletRun.aura engine on the shipped catalogue.")
print(" Base market value, neutral run (auraMult 1.0, evoLineBonusBonus 0).")
print(" Foil & grading are proportional upside for both sides and cancel here.")
print("=====================================================================")

// Reference: rarity value spread per set (why lines are 'cheap' to hold).
print("\n--- Typical card base value by rarity (min / median / max) ---")
print(pad("set", 20) + lpad("common", 22) + lpad("uncommon", 22) + lpad("rare", 22) + lpad("ultra", 22))
for d in sets {
    let all = CardDatabase.cards(inSet: d.set)
    func trio(_ r: Rarity) -> String {
        let v = all.filter { $0.rarity == r }.map { $0.baseValue }.sorted()
        return "\(money(v.first!)) / \(money(median(v))) / \(money(v.last!))"
    }
    print(pad("\(d.set) \(d.name)", 20)
          + lpad(trio(.common), 22) + lpad(trio(.uncommon), 22)
          + lpad(trio(.rare), 22) + lpad(trio(.ultra), 22))
}

// MARK: - 3-slot comparison (3-stage lines)

print("\n\n=====================================================================")
print(" THREE SLOTS:  a completed 3-stage line  vs  three singles")
print(" 3-stage line = common + uncommon + rare, lifted ×(1+bonus) when whole.")
print("=====================================================================")
print(pad("set", 16) + lpad("bonus×", 8)
      + lpad("line min", 11) + lpad("line med", 11) + lpad("line max", 11)
      + lpad("3 rares", 10) + lpad("2r+1u", 10) + lpad("1r+2u", 10) + lpad("3 ultras", 10))
for d in sets {
    let lineAuras = d.threeLines.map { aura($0) }
    let rrr = aura(Array(d.rares.prefix(3)))
    let rru = aura(Array(d.rares.prefix(2)) + [d.ultras[0]])
    let ruu = aura([d.rares[0]] + Array(d.ultras.prefix(2)))
    let uuu = aura(Array(d.ultras.prefix(3)))
    print(pad("\(d.set) \(d.name)", 16)
          + lpad(String(format: "%.2f", 1 + d.bonus), 8)
          + lpad(money(lineAuras.min()!), 11)
          + lpad(money(median(lineAuras)), 11)
          + lpad(money(lineAuras.max()!), 11)
          + lpad(money(rrr), 10) + lpad(money(rru), 10)
          + lpad(money(ruu), 10) + lpad(money(uuu), 10))
}
print(" (3 rares = 3 cheapest rares; 2r+1u = 2 cheapest rares + cheapest ultra;")
print("  1r+2u = cheapest rare + 2 cheapest ultras; 3 ultras = the set's 3 ultras.)")

// Ratio of the MEDIAN completed 3-stage line to each singles strategy.
print("\n--- Median completed 3-stage line ÷ singles strategy (>1 = line wins) ---")
print(pad("set", 16) + lpad("÷3 rares", 12) + lpad("÷2r+1u", 12) + lpad("÷1r+2u", 12) + lpad("÷3 ultras", 12))
for d in sets {
    let med = median(d.threeLines.map { aura($0) })
    let rrr = aura(Array(d.rares.prefix(3)))
    let rru = aura(Array(d.rares.prefix(2)) + [d.ultras[0]])
    let ruu = aura([d.rares[0]] + Array(d.ultras.prefix(2)))
    let uuu = aura(Array(d.ultras.prefix(3)))
    func r(_ x: Double) -> String { String(format: "%.2f", med / x) }
    print(pad("\(d.set) \(d.name)", 16)
          + lpad(r(rrr), 12) + lpad(r(rru), 12) + lpad(r(ruu), 12) + lpad(r(uuu), 12))
}

// MARK: - 2-slot comparison (2-stage lines)

print("\n\n=====================================================================")
print(" TWO SLOTS:  a completed 2-stage line  vs  two singles")
print(" 2-stage line = common + uncommon, lifted ×(1+bonus) when whole.")
print("=====================================================================")
print(pad("set", 16) + lpad("bonus×", 8)
      + lpad("line min", 11) + lpad("line med", 11) + lpad("line max", 11)
      + lpad("2 rares", 11) + lpad("1r+1u", 11) + lpad("2 ultras", 11))
for d in sets {
    let lineAuras = d.twoLines.map { aura($0) }
    let rr = aura(Array(d.rares.prefix(2)))
    let ru = aura([d.rares[0], d.ultras[0]])
    let uu = aura(Array(d.ultras.prefix(2)))
    print(pad("\(d.set) \(d.name)", 16)
          + lpad(String(format: "%.2f", 1 + d.bonus), 8)
          + lpad(money(lineAuras.min()!), 11)
          + lpad(money(median(lineAuras)), 11)
          + lpad(money(lineAuras.max()!), 11)
          + lpad(money(rr), 11) + lpad(money(ru), 11) + lpad(money(uu), 11))
}
print("\n--- Median completed 2-stage line ÷ singles strategy (>1 = line wins) ---")
print(pad("set", 16) + lpad("÷2 rares", 12) + lpad("÷1r+1u", 12) + lpad("÷2 ultras", 12))
for d in sets {
    let med = median(d.twoLines.map { aura($0) })
    let rr = aura(Array(d.rares.prefix(2)))
    let ru = aura([d.rares[0], d.ultras[0]])
    let uu = aura(Array(d.ultras.prefix(2)))
    func r(_ x: Double) -> String { String(format: "%.2f", med / x) }
    print(pad("\(d.set) \(d.name)", 16) + lpad(r(rr), 12) + lpad(r(ru), 12) + lpad(r(uu), 12))
}

// MARK: - Per-slot view (the real opportunity cost of one showcase slot)

print("\n\n=====================================================================")
print(" AURA PER SHOWCASE SLOT — what one slot is worth each way")
print(" A line's per-slot value = its completed Aura ÷ its stage count.")
print("=====================================================================")
print(pad("set", 16)
      + lpad("3-line/slot", 13) + lpad("2-line/slot", 13)
      + lpad("rare c/t/b", 22) + lpad("ultra c/t/b", 24))
for d in sets {
    let three = median(d.threeLines.map { aura($0) }) / 3
    let two   = median(d.twoLines.map { aura($0) }) / 2
    let rv = d.rares.map { $0.baseValue }
    let uv = d.ultras.map { $0.baseValue }
    let rTrio = "\(money(rv.first!))/\(money(median(rv)))/\(money(rv.last!))"
    let uTrio = "\(money(uv.first!))/\(money(median(uv)))/\(money(uv.last!))"
    print(pad("\(d.set) \(d.name)", 16)
          + lpad(money(three), 13) + lpad(money(two), 13)
          + lpad(rTrio, 22) + lpad(uTrio, 24))
}
print(" (rare/ultra shown cheapest / typical / best; each single fills one slot.)")

// MARK: - Sensitivity to the evolution-line bonus mod (Trainer/Catalyst boost)

print("\n\n=====================================================================")
print(" IMPACT OF THE EVOLUTION-LINE BONUS MOD (evoLineBonusBonus)")
print(" Median completed 3-stage line ÷ '3 ultras', as a flat evo-bonus boost")
print(" from a Trainer/Catalyst is added on top of every set's base bonus.")
print("=====================================================================")
let boosts = [0.0, 0.5, 1.0, 2.0]
print(pad("set", 16) + boosts.map { lpad("+\(String(format: "%.1f", $0))", 10) }.joined())
for d in sets {
    let uuu = aura(Array(d.ultras.prefix(3)))
    let cells = boosts.map { b -> String in
        let med = median(d.threeLines.map { aura($0, evoBonusBonus: b) })
        return lpad(String(format: "%.2f", med / uuu), 10)
    }.joined()
    print(pad("\(d.set) \(d.name)", 16) + cells)
}
print(" (>1.00 means a completed 3-stage line out-Auras keeping all 3 ultras.)")

// MARK: - Computed takeaways

print("\n\n=====================================================================")
print(" TAKEAWAYS (computed)")
print("=====================================================================")

func firstCrossover3(_ vsUltras: Bool) -> Int? {
    for d in sets {
        let med = median(d.threeLines.map { aura($0) })
        let cmp = vsUltras ? aura(Array(d.ultras.prefix(3)))
                           : aura(Array(d.rares.prefix(3)))
        if med >= cmp { return d.set }
    }
    return nil
}
if let x = firstCrossover3(false) {
    print(" • A median completed 3-stage line first beats 3 cheap rares at set \(x).")
} else {
    print(" • A median completed 3-stage line never beats 3 cheap rares.")
}
if let x = firstCrossover3(true) {
    print(" • A median completed 3-stage line first beats 3 ultras at set \(x).")
} else {
    print(" • A median completed 3-stage line never beats 3 ultras (all 5 sets).")
}

// Where does one line-slot overtake one ultra-slot (typical ultra)?
var slotCross: Int? = nil
for d in sets {
    let perSlot = median(d.threeLines.map { aura($0) }) / 3
    let typUltra = median(d.ultras.map { $0.baseValue })
    if perSlot >= typUltra { slotCross = d.set; break }
}
if let x = slotCross {
    print(" • Per slot, a 3-stage-line slot first beats a typical ultra slot at set \(x).")
} else {
    print(" • Per slot, a 3-stage-line slot never beats a typical ultra slot.")
}
print("")
