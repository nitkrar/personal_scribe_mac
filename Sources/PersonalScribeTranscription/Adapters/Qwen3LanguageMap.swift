import FluidAudio
import Foundation

enum Qwen3LanguageMap {
    static let bcp47ToQwen: [String: Qwen3AsrConfig.Language] = [
        "ar": .arabic,
        "cs": .czech,
        "da": .danish,
        "de": .german,
        "el": .greek,
        "en": .english,
        "es": .spanish,
        "fa": .persian,
        "fi": .finnish,
        "fil": .filipino,
        "fr": .french,
        "hi": .hindi,
        "hu": .hungarian,
        "id": .indonesian,
        "it": .italian,
        "ja": .japanese,
        "ko": .korean,
        "mk": .macedonian,
        "ms": .malay,
        "nl": .dutch,
        "pl": .polish,
        "pt": .portuguese,
        "ro": .romanian,
        "ru": .russian,
        "sv": .swedish,
        "th": .thai,
        "tr": .turkish,
        "vi": .vietnamese,
        "yue": .cantonese,
        "zh": .chinese,
    ]
}
