import Foundation

/// A pre-reader starts at letter sounds and works up to paragraphs.
/// Items are keyed `kind:text` and stored in NCB `item_progress.item_key`.
enum ItemKind: String, Codable {
    case letter, digraph
    case phonicsWord = "phonics_word"
    case sightWord = "sight_word"
    case sentence, passage
}

struct Item: Identifiable, Hashable {
    var id: String { key }
    let key: String
    let kind: ItemKind
    let stage: Int
    let text: String      // what is shown
    let say: String       // what text-to-speech reads (sounds need coaxing)
    var emoji: String? = nil
    var hint: String? = nil
    var title: String? = nil // passages only

    var isSound: Bool { kind == .letter || kind == .digraph }
    var isWord: Bool { kind == .phonicsWord || kind == .sightWord }
}

struct Stage: Identifiable, Hashable {
    let id: Int
    let title: String
    let blurb: String
    let emoji: String
}

enum Curriculum {
    static let stages: [Stage] = [
        Stage(id: 1, title: "Letter Sounds", blurb: "Hear it, say it: the sounds letters make", emoji: "🔤"),
        Stage(id: 2, title: "Digraphs", blurb: "Two letters, one sound: sh, ch, th…", emoji: "🤝"),
        Stage(id: 3, title: "Sound It Out", blurb: "Blend sounds into short words", emoji: "🧩"),
        Stage(id: 4, title: "Digraph Words", blurb: "Words with sh, ch, th, ck, ng", emoji: "🐑"),
        Stage(id: 5, title: "First Sight Words", blurb: "Words that show up everywhere", emoji: "👀"),
        Stage(id: 6, title: "More Sight Words", blurb: "Level up your word collection", emoji: "🌟"),
        Stage(id: 7, title: "Sentences", blurb: "Put words together", emoji: "💬"),
        Stage(id: 8, title: "Stories", blurb: "Read whole paragraphs", emoji: "📖"),
    ]

    // MARK: Stage 1 — letter sounds (SATPIN-style order so words unlock early)
    private static let letterData: [(String, String, String)] = [
        ("s", "sss", "🐍"), ("a", "aa", "🍎"), ("t", "tuh", "🐯"), ("p", "puh", "🐧"), ("i", "ih", "🦎"), ("n", "nnn", "🌙"),
        ("m", "mmm", "🌛"), ("d", "duh", "🐶"), ("o", "ah", "🐙"), ("g", "guh", "🐐"), ("c", "kuh", "🐱"), ("k", "kuh", "🔑"),
        ("e", "eh", "🥚"), ("u", "uh", "☂️"), ("r", "rrr", "🌈"), ("h", "huh", "🎩"), ("b", "buh", "🐻"), ("f", "fff", "🐟"),
        ("l", "lll", "🦁"), ("j", "juh", "🧃"), ("v", "vvv", "🎻"), ("w", "wuh", "🐋"), ("x", "ks", "🦊"), ("y", "yuh", "🪀"),
        ("z", "zzz", "🦓"), ("q", "kwuh", "👸"),
    ]
    // MARK: Stage 2 — digraphs and vowel teams
    private static let digraphData: [(String, String, String, String)] = [
        ("sh", "shhh", "🤫", "as in ship"), ("ch", "chuh", "🚂", "as in chip"), ("th", "thh", "👍", "as in thin"),
        ("wh", "wuh", "🐳", "as in whale"), ("ck", "kuh", "🦆", "as in duck"), ("ng", "nggg", "💍", "as in ring"),
        ("qu", "kwuh", "👑", "as in queen"), ("ee", "eee", "🐝", "as in bee"), ("ai", "ayy", "🚆", "as in train"),
        ("oa", "ohh", "🐐", "as in goat"), ("oo", "oooo", "🌝", "as in moon"), ("ar", "arr", "⭐", "as in star"),
    ]
    private static let cvc = [
        "sat", "mat", "pat", "tap", "map", "nap", "cat", "man", "can", "pan", "dad", "mad",
        "sit", "pit", "tin", "pin", "dip", "sip", "pig", "big", "dig", "kid", "lip", "hit",
        "dog", "log", "pot", "hot", "mop", "top", "box", "fox", "rod", "job", "cob", "got",
        "bed", "pet", "net", "red", "ten", "hen", "leg", "web", "jet", "get", "yes", "men",
        "sun", "bus", "cup", "mud", "bug", "hug", "run", "fun", "nut", "cut", "jug", "tub",
    ]
    private static let digraphWords = [
        "ship", "shop", "shed", "fish", "dish", "wish", "chip", "chop", "chin", "chat", "much", "rich",
        "thin", "this", "that", "them", "then", "with", "bath", "moth", "whip", "when", "what", "whiz",
        "duck", "back", "sock", "pack", "neck", "kick", "king", "ring", "song", "long", "sing", "wing",
        "queen", "quit", "quiz", "feet", "tree", "see", "rain", "tail", "boat", "coat", "moon", "spoon", "car", "star",
    ]
    // MARK: Stages 5–6 — Dolch sight words
    private static let prePrimer = [
        "a", "and", "away", "big", "blue", "can", "come", "down", "find", "for", "funny", "go", "help", "here", "I",
        "in", "is", "it", "jump", "little", "look", "make", "me", "my", "not", "one", "play", "red", "run", "said",
        "see", "the", "three", "to", "two", "up", "we", "where", "yellow", "you",
    ]
    private static let primer = [
        "all", "am", "are", "at", "ate", "be", "black", "brown", "but", "came", "did", "do", "eat", "four", "get", "good",
        "have", "he", "into", "like", "must", "new", "no", "now", "on", "our", "out", "please", "pretty", "ran", "ride",
        "saw", "say", "she", "so", "soon", "that", "there", "they", "this", "too", "under", "want", "was", "well", "went",
        "what", "white", "who", "will", "with", "yes",
    ]
    private static let grade1 = [
        "after", "again", "an", "any", "as", "ask", "by", "could", "every", "fly", "from", "give", "going", "had", "has",
        "her", "him", "his", "how", "just", "know", "let", "live", "may", "of", "old", "once", "open", "over", "put",
        "round", "some", "stop", "take", "thank", "them", "then", "think", "walk", "were", "when",
    ]
    // MARK: Stage 7 — sentences
    private static let sentenceData = [
        "I can see a cat.", "The dog is big.", "We go up.", "Look at me run!", "I like to play.", "The sun is hot.",
        "She has a red hat.", "He said, I can help.", "A fish is in the dish.", "The ship is on the sea.",
        "Can you see the red bus?", "We are going to the shop.", "My dad has a big box.", "Look, the pig is in the mud!",
        "They ran down the hill.", "I will get a hug.", "That duck can swim.", "What is in the bag?",
    ]
    // MARK: Stage 8 — paragraphs
    static let passageData: [(String, String)] = [
        ("The Cat", "A cat sat on a mat. The cat is big. The cat can nap. A man had a hat. The cat sat on the hat!"),
        ("The Red Hen", "I see a red hen. The hen is in a pen. She can run and she can sit. The hen has ten eggs. Look at the eggs! They are in the sun."),
        ("Fish and Ship", "Tim and Dan go to the sea. They see a ship. The ship is big. Tim has a fish in his dish. Dan said, I wish I had a fish. Then Tim said, you can have this one."),
        ("The Duck", "A duck sat on a log. The duck went quack, quack. A frog came to play. They had fun. Then the rain came down. The duck and the frog ran to the shed."),
        ("My Day", "I get up. I see the sun. We eat and then we play. Mom said, please help me, and I did. We went to the park and we saw a big dog. It was a good day."),
    ]

    static let all: [Item] = {
        var items: [Item] = []
        items += letterData.map {
            Item(key: "letter:\($0.0)", kind: .letter, stage: 1, text: $0.0, say: $0.1, emoji: $0.2,
                 hint: "Say the sound “\($0.1)”, not the letter name.")
        }
        items += digraphData.map {
            Item(key: "digraph:\($0.0)", kind: .digraph, stage: 2, text: $0.0, say: $0.1, emoji: $0.2, hint: $0.3)
        }
        items += cvc.map { Item(key: "phonics_word:\($0)", kind: .phonicsWord, stage: 3, text: $0, say: $0) }
        items += digraphWords.map { Item(key: "phonics_word:\($0)", kind: .phonicsWord, stage: 4, text: $0, say: $0) }
        items += prePrimer.map { Item(key: "sight_word:\($0)", kind: .sightWord, stage: 5, text: $0, say: $0, hint: "Say it, spell it, say it again.") }
        items += (primer + grade1).map { Item(key: "sight_word:\($0)", kind: .sightWord, stage: 6, text: $0, say: $0) }
        items += sentenceData.map { Item(key: "sentence:\($0)", kind: .sentence, stage: 7, text: $0, say: $0) }
        items += passageData.map {
            Item(key: "passage:\($0.0)", kind: .passage, stage: 8, text: $0.1, say: $0.1, title: $0.0)
        }
        // De-dupe by key (a few words appear in several lists) keeping the earliest stage.
        var seen = Set<String>()
        return items.filter { seen.insert($0.key).inserted }
    }()

    static let byKey: [String: Item] = Dictionary(uniqueKeysWithValues: all.map { ($0.key, $0) })
    static func items(inStage stage: Int) -> [Item] { all.filter { $0.stage == stage } }
    static let passages: [Item] = all.filter { $0.kind == .passage }

    /// Words a child can already read; used to constrain AI-written stories.
    static let alwaysAllowed = ["the", "a", "is", "and", "I", "can", "see", "to", "my", "we", "it", "in", "on", "was", "he", "she"]

    /// Item for a custom word a parent added ("custom:word").
    static func customItem(_ w: CustomWord) -> Item {
        Item(key: "custom:\(w.word.lowercased())", kind: .sightWord, stage: 0, text: w.word, say: w.word,
             hint: w.note ?? w.sentence)
    }
}
