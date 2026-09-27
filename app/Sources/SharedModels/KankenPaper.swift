/// The official layout of a 漢検 paper at one 級: every 大問 in paper order with
/// its question count and points, the total, the pass mark and the sitting
/// length. Transcribed from the 2026年度第1回 papers and 標準解答 published on
/// kanken.or.jp (問題例), where each 大問 prints its 配点 — e.g. "(40) 2×20".
///
/// A 大問 is answered with the app's closest section (`sectionID`, one of the
/// ids in `ExamType.kankenSections`); a paper may use the same section more
/// than once, as 10級 does for its three reading 大問.
public struct KankenPaper: Equatable, Sendable {
    public struct Part: Equatable, Sendable, Identifiable {
        public var id: Int { index }
        public let index: Int
        /// The 大問 as the paper names it.
        public let title: String
        public let sectionID: String
        public let count: Int
        public let points: Int
        public var maxPoints: Int { count * points }
    }

    public let level: String
    public let total: Int
    public let pass: Int
    public let minutes: Int
    public let parts: [Part]

    public var questionCount: Int { parts.reduce(0) { $0 + $1.count } }

    init(_ level: String, total: Int, pass: Int, minutes: Int,
         _ parts: [(String, String, Int, Int)]) {
        self.level = level
        self.total = total
        self.pass = pass
        self.minutes = minutes
        self.parts = parts.enumerated().map { i, p in
            Part(index: i, title: p.0, sectionID: p.1, count: p.2, points: p.3)
        }
    }

    public static func official(for level: String) -> KankenPaper? { papers[level] }

    /// The 大問 marker printed on the paper: 一, 二, … 十一.
    public static func numeral(_ index: Int) -> String {
        let kanji = ["一", "二", "三", "四", "五", "六", "七", "八", "九", "十", "十一", "十二"]
        return index < kanji.count ? kanji[index] : "\(index + 1)"
    }

    private static let upper: [(String, String, Int, Int)] = [
        ("読み", "reading", 30, 1),
        ("音訓読み", "onkun", 10, 1),
        ("熟語の構成", "kousei", 10, 2),
        ("四字熟語", "yoji", 15, 2),
        ("対義語・類義語", "taigirui", 10, 2),
        ("同音・同訓異字", "doonkun", 10, 2),
        ("誤字訂正", "goji", 5, 2),
        ("漢字と送りがな", "okuri", 5, 2),
        ("書き取り", "writing", 25, 2),
    ]
    private static let middle: [(String, String, Int, Int)] = [
        ("読み", "reading", 30, 1),
        ("同音・同訓異字", "doonkun", 15, 2),
        ("漢字識別", "shikibetsu", 5, 2),
        ("熟語の構成", "kousei", 10, 2),
        ("部首", "radical", 10, 1),
        ("対義語・類義語", "taigirui", 10, 2),
        ("漢字と送りがな", "okuri", 5, 2),
        ("四字熟語", "yoji", 10, 2),
        ("誤字訂正", "goji", 5, 2),
        ("書き取り", "writing", 20, 2),
    ]

    private static let papers: [String: KankenPaper] = {
        let list: [KankenPaper] = [
            KankenPaper("10級", total: 150, pass: 120, minutes: 40, [
                ("読み", "reading", 20, 2),
                ("筆順", "hitsujun", 12, 1),
                ("同じ字の読み", "reading", 8, 2),
                ("読みを選ぶ", "reading", 5, 2),
                ("ひらがな一字", "okuri", 6, 2),
                ("反対の意味", "hantai", 10, 2),
                ("書き取り", "writing", 20, 2),
            ]),
            KankenPaper("9級", total: 150, pass: 120, minutes: 40, [
                ("読み", "reading", 26, 1),
                ("筆順", "hitsujun", 10, 1),
                ("ひらがな一字", "okuri", 8, 1),
                ("同じ字の読み", "reading", 10, 1),
                ("どちらが正しい", "writing", 6, 1),
                ("なかまの漢字", "writing", 10, 2),
                ("反対の意味", "hantai", 10, 2),
                ("書き取り", "writing", 25, 2),
            ]),
            KankenPaper("8級", total: 150, pass: 120, minutes: 40, [
                ("読み", "reading", 30, 1),
                ("筆順", "hitsujun", 10, 1),
                ("対義語", "taigi", 5, 2),
                ("部首のなかま", "radical", 10, 2),
                ("同音異字", "doonkun", 10, 2),
                ("送りがな", "okuri", 5, 2),
                ("同じ字の読み", "reading", 10, 1),
                ("書き取り", "writing", 20, 2),
            ]),
            KankenPaper("7級", total: 200, pass: 140, minutes: 60, [
                ("読み", "reading", 30, 1),
                ("漢字えらび", "doonkun", 10, 2),
                ("画数", "strokes", 10, 1),
                ("音読み・訓読み", "onkun", 10, 2),
                ("対義語", "taigi", 5, 2),
                ("漢字と送りがな", "okuri", 7, 2),
                ("同じ部首の漢字", "radical", 10, 2),
                ("同じ読みの漢字", "doonkun", 8, 2),
                ("じゅく語作り", "sanji", 10, 2),
                ("書き取り", "writing", 20, 2),
            ]),
            KankenPaper("6級", total: 200, pass: 140, minutes: 60, [
                ("読み", "reading", 20, 1),
                ("漢字と送りがな", "okuri", 5, 2),
                ("部首名と部首", "radical", 10, 1),
                ("画数", "strokes", 10, 1),
                ("じゅく語の構成", "kousei", 10, 2),
                ("三字のじゅく語", "sanji", 10, 2),
                ("対義語・類義語", "taigirui", 10, 2),
                ("じゅく語作り", "tsukuri", 6, 2),
                ("音と訓", "onkun", 10, 2),
                ("同じ読みの漢字", "doonkun", 9, 2),
                ("書き取り", "writing", 20, 2),
            ]),
            KankenPaper("5級", total: 200, pass: 140, minutes: 60, [
                ("読み", "reading", 20, 1),
                ("部首と部首名", "radical", 10, 1),
                ("画数", "strokes", 10, 1),
                ("漢字と送りがな", "okuri", 5, 2),
                ("音と訓", "onkun", 10, 2),
                ("四字の熟語", "yoji", 10, 2),
                ("対義語・類義語", "taigirui", 10, 2),
                ("熟語作り", "tsukuri", 5, 2),
                ("熟語の構成", "kousei", 10, 2),
                ("同じ読みの漢字", "doonkun", 10, 2),
                ("書き取り", "writing", 20, 2),
            ]),
            KankenPaper("4級", total: 200, pass: 140, minutes: 60, middle),
            KankenPaper("3級", total: 200, pass: 140, minutes: 60, middle),
            KankenPaper("準2級", total: 200, pass: 140, minutes: 60, upper),
            KankenPaper("2級", total: 200, pass: 160, minutes: 60, upper),
            KankenPaper("準1級", total: 200, pass: 160, minutes: 60, [
                ("読み", "reading", 30, 1),
                ("表外の読み", "hyogai-reading", 10, 1),
                ("熟語と一字訓の読み", "jukugo-reading", 10, 1),
                ("共通の漢字", "common-kanji", 5, 2),
                ("書き取り", "writing", 20, 2),
                ("誤字訂正", "goji", 5, 2),
                ("四字熟語", "yoji", 15, 2),
                ("対義語・類義語", "taigirui", 10, 2),
                ("故事・諺", "koji-kotowaza", 10, 2),
                ("文章題（書き取り）", "writing", 5, 2),
                ("文章題（読み）", "passage", 10, 1),
            ]),
            KankenPaper("1級", total: 200, pass: 160, minutes: 60, [
                ("読み", "reading", 30, 1),
                ("書き取り", "writing", 20, 2),
                ("語選択", "word-selection", 5, 2),
                ("四字熟語", "yoji", 15, 2),
                ("熟字訓・当て字", "jukujikun-ateji", 10, 1),
                ("熟語と一字訓の読み", "jukugo-reading", 10, 1),
                ("対義語・類義語", "taigirui", 10, 2),
                ("故事・諺", "koji-kotowaza", 10, 2),
                ("文章題（書き取り）", "writing", 10, 2),
                ("文章題（読み）", "passage", 10, 1),
            ]),
        ]
        return Dictionary(uniqueKeysWithValues: list.map { ($0.level, $0) })
    }()
}
