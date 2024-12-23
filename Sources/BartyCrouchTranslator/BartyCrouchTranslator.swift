import Foundation
import Microya
import MungoHealer

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
    case deepL(apiKey: String)
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
    if case let .deepL(apiKey) = translationService {
      deepLApiType = apiKey.hasSuffix(":fx") ? .free : .pro
    }
    else {
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
              return Translation(language: Language.with(locale: iterator.element.to)!,
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
      case let .deepL(apiKey):
          var allTranslations: [Translation] = []
          for targetLanguage in targetLanguages {
              let endpoint = DeepLApi.translate(
                  texts: sources.map({ $0.text }),
                  from: sourceLanguage,
                  to: targetLanguage,
                  apiKey: apiKey
              )
              switch deepLProvider.performRequestAndWait(on: endpoint, decodeBodyTo: DeepLTranslateResponse.self) {
              case let .success(translateResponse):
                  let translations: [Translation] = translateResponse.translations.enumerated().map { iterator in
                    return Translation(language: targetLanguage,
                                       translatedText: iterator.element.text,
                                       key: sources[iterator.offset].key)
                  }
                  allTranslations.append(contentsOf: translations)

              case let .failure(failure):
                  return .failure(MungoError(source: .internalInconsistency, message: failure.localizedDescription))
              }
          }
          return .success(allTranslations)

      // OpenAI Translation
      case let .openAI(apiKey, context):
          var allTranslations: [Translation] = []
        
       
          for targetLanguage in targetLanguages {
              let endpoint = OpenAIApi.translate(
                  sources: sources,
                  from: sourceLanguage,
                  to: targetLanguage,
                  context: context,
                  apiKey: apiKey
              )
              switch openAIProvider.performRequestAndWait(on: endpoint, decodeBodyTo: OpenAITranslateResponse.self) {
              case let .success(translateResponses):
                  let translations = translateResponses.choices.first?.message.content.translations.enumerated().compactMap { iterator in
                    return Translation(language: targetLanguage,
                                       translatedText: iterator.element.text,
                                       key: sources[iterator.offset].key)
                  } ?? [Translation]()
                  allTranslations.append(contentsOf: translations)

              case let .failure(failure):
                  return .failure(MungoError(source: .internalInconsistency, message: failure.localizedDescription))
              }
          }
          return .success(allTranslations)
      }
  }
}
