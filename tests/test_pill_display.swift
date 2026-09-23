import Foundation

@main
struct PillDisplayTests {
    static func main() {
        let primary = PillDisplay(identifier: "built-in", frame: CGRect(x: 0, y: 0, width: 1440, height: 900))
        let external = PillDisplay(identifier: "external", frame: CGRect(x: 1440, y: 0, width: 1920, height: 1080))

        func select(_ id: String?, _ origin: CGPoint?, _ displays: [PillDisplay], fallback: Int = 0) -> Int? {
            PillDisplayRestoration.screenIndex(savedIdentifier: id, savedOrigin: origin, displays: displays, fallbackIndex: fallback)
        }

        // Existing preferences have coordinates and a snap target but no display UUID.
        assert(select(nil, CGPoint(x: 1452, y: 500), [primary, external]) == 1)

        // Reordering display arrays or moving a monitor must preserve display identity.
        assert(select("external", CGPoint(x: 1452, y: 500), [external, primary]) == 0)
        let movedExternal = PillDisplay(identifier: "external", frame: CGRect(x: -1920, y: 0, width: 1920, height: 1080))
        assert(select("external", CGPoint(x: 1452, y: 500), [primary, movedExternal]) == 1)
        assert(select(nil, CGPoint(x: -1908, y: 500), [primary, movedExternal]) == 1)

        // A stale or disconnected monitor falls back to a currently visible screen.
        assert(select("external", CGPoint(x: 1452, y: 500), [primary]) == 0)
        assert(select(nil, nil, [primary, external], fallback: 1) == 1)
        assert(select(nil, CGPoint(x: CGFloat.nan, y: 10), [primary]) == 0)
        assert(select(nil, nil, [primary], fallback: 99) == 0)
        assert(select(nil, nil, []) == nil)

        print("Pill display restoration: 9 regression checks passed")
    }
}
