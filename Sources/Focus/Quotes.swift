struct Quote {
    let text: String
    let author: String
}

enum Quotes {
    static let all: [Quote] = [
        // 中文
        Quote(text: "不积跬步，无以至千里；不积小流，无以成江海。", author: "荀子"),
        Quote(text: "锲而舍之，朽木不折；锲而不舍，金石可镂。", author: "荀子"),
        Quote(text: "业精于勤，荒于嬉；行成于思，毁于随。", author: "韩愈"),
        Quote(text: "黑发不知勤学早，白首方悔读书迟。", author: "颜真卿"),
        Quote(text: "宝剑锋从磨砺出，梅花香自苦寒来。", author: "《警世贤文》"),
        Quote(text: "千里之行，始于足下。", author: "老子"),
        Quote(text: "合抱之木，生于毫末；九层之台，起于累土。", author: "老子"),
        Quote(text: "天下难事，必作于易；天下大事，必作于细。", author: "老子"),
        Quote(text: "学而不思则罔，思而不学则殆。", author: "孔子"),
        Quote(text: "博学之，审问之，慎思之，明辨之，笃行之。", author: "《中庸》"),
        Quote(text: "路漫漫其修远兮，吾将上下而求索。", author: "屈原"),
        Quote(text: "纸上得来终觉浅，绝知此事要躬行。", author: "陆游"),
        Quote(text: "盛年不重来，一日难再晨。及时当勉励，岁月不待人。", author: "陶渊明"),
        Quote(text: "屏幕里没有你要的答案，答案在草稿纸上。", author: "Focus"),
        Quote(text: "现在多做一道题，考场上就少慌一分。", author: "Focus"),
        Quote(text: "放下鼠标，拿起笔。这道题做完再说。", author: "Focus"),

        // English
        Quote(text: "It does not matter how slowly you go as long as you do not stop.", author: "Confucius"),
        Quote(text: "Well begun is half done.", author: "Aristotle"),
        Quote(text: "We are what we repeatedly do. Excellence, then, is not an act, but a habit.", author: "Will Durant"),
        Quote(text: "Success is the sum of small efforts, repeated day in and day out.", author: "Robert Collier"),
        Quote(text: "Concentrate all your thoughts upon the work at hand. The sun's rays do not burn until brought to a focus.", author: "Alexander Graham Bell"),
        Quote(text: "Don't watch the clock; do what it does. Keep going.", author: "Sam Levenson"),
        Quote(text: "The expert in anything was once a beginner.", author: "Helen Hayes"),
        Quote(text: "Learning never exhausts the mind.", author: "Leonardo da Vinci"),
        Quote(text: "You don't have to see the whole staircase, just take the first step.", author: "Martin Luther King Jr."),
        Quote(text: "The screen can wait. Your future can't.", author: "Focus"),
        Quote(text: "Focus on the problem in front of you, not the tab behind you.", author: "Focus"),
    ]

    static func random(excluding current: Quote? = nil) -> Quote {
        let pool = all.filter { $0.text != current?.text }
        return pool.randomElement() ?? all[0]
    }
}
