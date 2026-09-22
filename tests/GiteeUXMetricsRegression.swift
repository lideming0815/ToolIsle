import Foundation
@main struct Tests {
    static func main() {
        var checks = 0
        func check(_ ok: Bool, _ label: String) { precondition(ok, label); checks += 1 }
        for limit in [-2, 0, 1, 8, 10, 11, 999] {
            for count in [-1, 0, 1, 3, 8, 10, 20] {
                let m = GINotchMetrics(count: count, limit: limit)
                check((1...10).contains(m.limit), "bounded setting")
                check(m.visibleCount == min(max(0,count), min(10,max(1,limit))), "bounded preview")
                for screen: CGFloat in [480, 600, 800, 1200] {
                    let h = m.notchHeight(availableHeight: screen)
                    check(h <= floor(screen * 0.72), "screen-safe expansion")
                    check(h - GINotchMetrics.hostInset > GINotchMetrics.chromeHeight, "visible fixed controls")
                }
            }
        }
        check(GINotchMetrics.defaultLimit == 8, "default eight")
        let small = GINotchMetrics(count: 1, limit: 8).notchHeight(availableHeight: 1000)
        let eight = GINotchMetrics(count: 8, limit: 8).notchHeight(availableHeight: 1000)
        let twenty = GINotchMetrics(count: 20, limit: 8).notchHeight(availableHeight: 1000)
        check(small < eight && eight == twenty, "dynamic growth stops at cap")
        let cap = GINotchMetrics(count: 10, limit: 10)
        check(cap.notchHeight(availableHeight: 480) < cap.notchHeight(availableHeight: 1000), "per-screen independent cap")
        check(cap.notchHeight(availableHeight: .nan).isFinite, "invalid screen fallback")
        print("Gitee production metrics: \(checks) assertions passed")
    }
}
