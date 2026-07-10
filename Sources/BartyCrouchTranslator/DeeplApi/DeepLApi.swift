import Foundation
import Microya

// Documentation can be found here: https://www.deepl.com/ja/docs-api/

enum DeepLApi {
  case translate(texts: [String], from: Language, to: Language, apiKey: String)

  static let maximumTextsPerRequest: Int = 25
  static let maximumTextsLengthPerRequest: Int = 5_000

  static func textBatches(forTexts texts: [String]) -> [[String]] {
    var batches: [[String]] = []
    var currentBatch: [String] = []
    var currentBatchTotalLength: Int = 0

    for text in texts {
      if currentBatch.count < maximumTextsPerRequest
          && text.count + currentBatchTotalLength < maximumTextsLengthPerRequest
      {
        currentBatch.append(text)
        currentBatchTotalLength += text.count
      }
      else {
        batches.append(currentBatch)

        currentBatch = [text]
        currentBatchTotalLength = text.count
      }
    }

    return batches
  }
}

extension DeepLApi: Endpoint {
  typealias ClientErrorType = DeepLTranslateErrorResponse

  enum ApiType {
    case free
    case pro
  }

  var decoder: JSONDecoder {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    return decoder
  }

  var subpath: String {
    switch self {
    case .translate:
      return "/v2/translate"
    }
  }

  var method: HttpMethod {
    switch self {
    case .translate(let texts, let sourceLanguage, let targetLanguage, _):
      
      let textItems = texts.map { URLQueryItem(name: "text", value: $0) }
      let targetLangItem = URLQueryItem(name: "target_lang", value: targetLanguage.deepLParameterValue)
      let sourceLangItem = URLQueryItem(name: "source_lang", value: sourceLanguage.deepLParameterValue)
      let formalityItem = URLQueryItem(name: "formality", value: "prefer_less")
      let tagHandlingItem = URLQueryItem(name: "tag_handling", value: "xml")
      let ignoreTagsItem = URLQueryItem(name: "ignore_tags", value: "x")
      
      var queryItems = [targetLangItem, sourceLangItem, formalityItem, tagHandlingItem, ignoreTagsItem]
      if let glossaryId = ProcessInfo.processInfo.environment["DEEPL_GLOSSARY_ID"], !glossaryId.isEmpty {
        queryItems.append(URLQueryItem(name: "glossary_id", value: glossaryId))
      }
      queryItems += textItems

      var components = URLComponents()
      components.queryItems = queryItems
      
      guard var queryItemsString = components.string else {
          fatalError("Invalid arguments.")
      }
      // queryItemsString starts with a ? but post API expects the query string without leading ?
      if queryItemsString.hasPrefix("?") {
        queryItemsString.removeFirst()
      }
                
      return .post(body: queryItemsString.data(using: .utf8)!)
    }
  }

  var headers: [String: String] {
    switch self {
    case .translate(_, _, _, let authKey):
      return [
        "Content-Type": "application/x-www-form-urlencoded",
        // DeepL deprecated form-body/query auth (Nov 2025); the key must be sent as a header.
        "Authorization": "DeepL-Auth-Key \(authKey)",
      ]
    }
  }

  static func baseUrl(for apiType: ApiType) -> URL {
    switch apiType {
    case .free:
      return URL(string: "https://api-free.deepl.com")!

    case .pro:
      return URL(string: "https://api.deepl.com")!
    }
  }
}

private extension Language {
  var deepLParameterValue: String {
    switch self {
    case .chineseSimplified:
      return "ZH"

    default:
      return rawValue.uppercased()
    }
  }
}
