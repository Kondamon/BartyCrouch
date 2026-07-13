import Foundation
import Microya
import MungoHealer

private enum DeepLPlaceholderProtector {
    static let pattern = "%(?:\\d+\\$)?[-+ 0#]*\\d*(?:\\.\\d+)?(?:hh|h|ll|l|q|z|t|j|L)?[@dDiuUxXoObeEfgGaAcsSpn%]"

    static func wrap(_ text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return escapeXML(text) }
        let fullRange = NSRange(text.startIndex..., in: text)
        var result = ""
        var cursor = text.startIndex
        for match in regex.matches(in: text, range: fullRange) {
            guard let range = Range(match.range, in: text) else { continue }
            let token = String(text[range])
            result += escapeXML(String(text[cursor..<range.lowerBound]))
            result += token == "%%" ? escapeXML(token) : "<x>\(token)</x>"
            cursor = range.upperBound
        }
        result += escapeXML(String(text[cursor...]))
        return result
    }

    static func unwrap(_ text: String) -> String {
        let stripped = text.replacingOccurrences(of: "<x>", with: "").replacingOccurrences(of: "</x>", with: "")
        return unescapeXML(stripped)
    }

    private static func escapeXML(_ value: String) -> String {
        value.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private static func unescapeXML(_ value: String) -> String {
        value.replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&amp;", with: "&")
    }
}

/// Groups DeepL translation sources by the context that should accompany them.
///
/// DeepL's `context` is one value *per request*, not per text. To support both a
/// project-wide context (Option A) and per-key context from a string's own comment
/// (Option B, the default), sources are bucketed by their effective context so keys
/// that share a context still batch together — only keys carrying their own comment
/// split into separate requests.
private enum DeepLContextGrouper {
    /// Merges the project-wide context with a key's own comment. Both are optional;
    /// when both are present the comment refines the global context. Returns `nil`
    /// when neither yields any text, so no `context` parameter is sent.
    static func effectiveContext(global: String, comment: String?) -> String? {
        let parts = [global, comment ?? ""]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: " — ")
    }

    /// Buckets sources by their effective context, preserving first-seen order so
    /// output stays deterministic. Each returned group becomes one context value.
    static func groups(
        for sources: [BartyCrouchTranslator.TranslationSource],
        globalContext: String
    ) -> [(context: String?, sources: [BartyCrouchTranslator.TranslationSource])] {
        var order: [String] = []
        var bucketed: [String: [BartyCrouchTranslator.TranslationSource]] = [:]
        var contextForKey: [String: String?] = [:]

        for source in sources {
            let context = effectiveContext(global: globalContext, comment: source.comment)
            let bucketKey = context ?? ""
            if bucketed[bucketKey] == nil {
                order.append(bucketKey)
                contextForKey[bucketKey] = context
            }
            bucketed[bucketKey, default: []].append(source)
        }

        return order.map { (context: contextForKey[$0] ?? nil, sources: bucketed[$0] ?? []) }
    }
}

/// Translator service to translate texts from one language to another.
///
/// NOTE: Currently only supports Microsoft Translator Text API using a subscription key.
public final class BartyCrouchTranslator {
    public typealias Translation = (language: Language, translatedText: String, key: String)

    /// The supported translation services.
    public enum TranslationService {
        /// The Microsoft Translator Text API.
        /// Website: https://docs.microsoft.com/en-us/azure/cognitive-services/translator/translator-info-overview
        ///
        /// - Parameters:
        ///   - subscriptionKey: The `Ocp-Apim-Subscription-Key`, also called "Azure secret key" in the docs.
        case microsoft(subscriptionKey: String)
        case deepL(apiKey: String, context: String)
        case openAI(apiKey: String, context: String)
    }

    public struct TranslationSource {
        /// Key in source file
        var key: String
        /// Text to be translated
        var text: String
        /// User provided comment
        var comment: String?

        public init(key: String, text: String, comment: String? = nil) {
            self.key = key
            self.text = text
            self.comment = comment
        }
    }

    private let microsoftProvider = ApiProvider<MicrosoftTranslatorApi>(baseUrl: MicrosoftTranslatorApi.baseUrl)
    private let deepLProvider: ApiProvider<DeepLApi>
    private let openAIProvider = ApiProvider<OpenAIApi>(baseUrl: OpenAIApi.baseUrl())

    private let translationService: TranslationService

    /// Creates a new translator object configured to use the specified translation service.
    public init(
        translationService: TranslationService
    ) {
        self.translationService = translationService

        let deepLApiType: DeepLApi.ApiType
        if case let .deepL(apiKey, _) = translationService {
            deepLApiType = apiKey.hasSuffix(":fx") ? .free : .pro
        } else {
            deepLApiType = .pro
        }

        deepLProvider = ApiProvider<DeepLApi>(baseUrl: DeepLApi.baseUrl(for: deepLApiType))
    }

    /// Translates the given text from a given language to one or multiple given other languages.
    ///
    /// - Parameters:
    ///   - sources: The texts to be translated and keys, comments
    ///   - targetLanguages: An array of other languages to be translated to.
    ///   - comment: Comment provided by user in the source language
    /// - Returns: A `Result` wrapper containing an array of translations if the request was successful, else the related error.
    public func translate(
        sources: [TranslationSource],
        from sourceLanguage: Language,
        to targetLanguages: [Language]
    ) -> Result<[Translation], MungoError> {
        guard sources.count > 0 else { return .success([]) }
        switch translationService {

        // Microsoft Translation
        case let .microsoft(subscriptionKey):
            let endpoint = MicrosoftTranslatorApi.translate(
                texts: sources.map({ $0.text }),
                from: sourceLanguage,
                to: targetLanguages,
                microsoftSubscriptionKey: subscriptionKey
            )

            switch microsoftProvider.performRequestAndWait(on: endpoint, decodeBodyTo: [TranslateResponse].self) {
            case let .success(translateResponses):
                if let translations: [Translation] = translateResponses.first?.translations.enumerated().map({ iterator in
                    return Translation(
                        language: Language.with(locale: iterator.element.to)!,
                        translatedText: iterator.element.text,
                        key: sources[iterator.offset].key)
                }) {
                    return .success(translations)
                } else {
                    return .failure(
                        MungoError(source: .internalInconsistency, message: "Could not fetch translation(s) for '\(sources.map { $0.text })'.")
                    )
                }

            case let .failure(failure):
                return .failure(MungoError(source: .internalInconsistency, message: failure.localizedDescription))
            }

        // DeepL Translation
        case let .deepL(apiKey, context):
            var allTranslations: [Translation] = []
            for targetLanguage in targetLanguages {
                allTranslations += deepLTranslations(
                    sources: sources,
                    from: sourceLanguage,
                    to: targetLanguage,
                    globalContext: context,
                    apiKey: apiKey
                )
            }
            return .success(allTranslations)

        // OpenAI Translation
        case let .openAI(apiKey, context):
            var allTranslations: [Translation] = []

            // Chunk large inputs so big batches don't time out; small batches stay a single request.
            for targetLanguage in targetLanguages {
                for batch in OpenAIApi.sourceBatches(forSources: sources) {
                    let endpoint = OpenAIApi.translate(
                        sources: batch,
                        from: sourceLanguage,
                        to: targetLanguage,
                        context: context,
                        apiKey: apiKey
                    )
                    switch openAIProvider.performRequestAndWait(on: endpoint, decodeBodyTo: OpenAITranslateResponse.self) {
                    case let .success(translateResponses):
                        let translations =
                            translateResponses.choices.first?.message.content.translations.enumerated().compactMap { iterator in
                                return Translation(
                                    language: targetLanguage,
                                    translatedText: iterator.element.text,
                                    key: batch[iterator.offset].key)
                            } ?? [Translation]()
                        allTranslations.append(contentsOf: translations)

                    case let .failure(failure):
                        return .failure(MungoError(source: .internalInconsistency, message: failure.localizedDescription))
                    }
                }
            }
            return .success(allTranslations)
        }
    }

    /// Translates all sources into one target language, grouping keys by their effective
    /// context so each DeepL request carries a single `context` value, then size-batching
    /// within each group. Returns whatever was gathered; an unsupported/failed target stops early.
    private func deepLTranslations(
        sources: [TranslationSource],
        from sourceLanguage: Language,
        to targetLanguage: Language,
        globalContext: String,
        apiKey: String
    ) -> [Translation] {
        var translations: [Translation] = []
        for group in DeepLContextGrouper.groups(for: sources, globalContext: globalContext) {
            for batch in DeepLApi.sourceBatches(forSources: group.sources) {
                guard
                    let batchTranslations = deepLBatchTranslations(
                        batch: batch,
                        from: sourceLanguage,
                        to: targetLanguage,
                        context: group.context,
                        apiKey: apiKey
                    )
                else {
                    return translations
                }
                translations += batchTranslations
            }
        }
        return translations
    }

    /// Performs one DeepL request for a single batch sharing one `context`.
    /// Returns `nil` when the request fails (e.g. unsupported target language).
    private func deepLBatchTranslations(
        batch: [TranslationSource],
        from sourceLanguage: Language,
        to targetLanguage: Language,
        context: String?,
        apiKey: String
    ) -> [Translation]? {
        let endpoint = DeepLApi.translate(
            texts: batch.map { DeepLPlaceholderProtector.wrap($0.text) },
            from: sourceLanguage,
            to: targetLanguage,
            context: context,
            apiKey: apiKey
        )
        switch deepLProvider.performRequestAndWait(on: endpoint, decodeBodyTo: DeepLTranslateResponse.self) {
        case let .success(response):
            return response.translations.enumerated().map { iterator in
                Translation(
                    language: targetLanguage,
                    translatedText: DeepLPlaceholderProtector.unwrap(iterator.element.text),
                    key: batch[iterator.offset].key
                )
            }

        case let .failure(failure):
            let warning = "warning: DeepL skipped unsupported/failed target \(targetLanguage.rawValue) (\(failure.localizedDescription))\n"
            FileHandle.standardError.write(Data(warning.utf8))
            return nil
        }
    }
}
