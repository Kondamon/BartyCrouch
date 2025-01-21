import Foundation
import Microya

// Documentation can be found here: https://www.deepl.com/ja/docs-api/

import Microya
import Foundation

/// Enum representing your API calls to OpenAI.
/// Uses the approach described in the OpenAI Cookbook for data extraction / transformation.
enum OpenAIApi {
  
  struct TranslationText {
    var text: String
    var comment: String?
  }
  /// This case instructs the OpenAI model to translate the text from `from` to `to`,
  /// then package the response in a JSON structure.
  /// - Parameters:
  ///   - texts: The texts to be translated or otherwise transformed.
  ///   - from: Source language.
  ///   - to: Target language.
  ///   - context: Context about the translations, e.g. app,... for more accurate translation results.
  ///   - apiKey: Your OpenAI API key.
  case translate(sources: [BartyCrouchTranslator.TranslationSource], from: Language, to: Language, context: String, apiKey: String)
  
  /// Maximum number of texts to include per request batch.
  static let maximumTextsPerRequest: Int = 25
  
  /// Maximum total character length for all texts in a single request.
  static let maximumTextsLengthPerRequest: Int = 1_000
  
  /// Utility function that splits a list of texts into batches,
  /// ensuring the total texts per batch and total character lengths
  /// are within defined limits.
  /// - Parameter texts: An array of strings to be processed.
  /// - Returns: A two-dimensional array where each sub-array represents a batch of texts.
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
      } else {
        batches.append(currentBatch)
        currentBatch = [text]
        currentBatchTotalLength = text.count
      }
    }
    
    // Don’t forget to add the last batch if it’s non-empty
    if !currentBatch.isEmpty {
      batches.append(currentBatch)
    }
    
    return batches
  }
}

/// Extend `OpenAIApi` to conform to Microya’s `Endpoint` protocol.
/// This defines how requests are formed and executed.
extension OpenAIApi: Endpoint {
  // MARK: - Associated Types
  
  /// Specify the expected structure for error responses.
  /// You can implement `OpenAITranslateErrorResponse` based on the
  /// possible errors from the OpenAI API (or reuse a generic error structure).
  typealias ClientErrorType = OpenAITranslateErrorResponse
  
  // MARK: - JSON Decoder
  
  /// A JSON decoder for decoding responses from the OpenAI API.
  var decoder: JSONDecoder {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    return decoder
  }
  
  // MARK: - Path
  
  /// Subpath for the request. For Chat Completions, the endpoint is `/v1/chat/completions`.
  var subpath: String {
    switch self {
    case .translate:
      return "/v1/chat/completions"
    }
  }
  
  // MARK: - HTTP Method and Request Body
  
  /// HTTP method and body construction for each endpoint case.
  var method: HttpMethod {
    switch self {
    case let .translate(sources, sourceLanguage, targetLanguage, context, _):
      
      print("Starting OpenAIAPI request for \(sources.count) translations from \(sourceLanguage) to \(targetLanguage).")
      
      // --------------------------------------------------------------------------------
      // MODEL 4o (GPT-4-like model) & DATA EXTRACTION PARADIGM
      //
      // Below, we mimic the approach from:
      // https://cookbook.openai.com/examples/data_extraction_transformation
      //
      // We use an enhanced system prompt to instruct the model to:
      //  1. Translate the text from sourceLanguage to targetLanguage
      //  2. Produce JSON output with the extracted fields (translation, etc.)
      //
      // If you have a more complex schema, you can define it in the system message or
      // employ function calling. For brevity, we simply ask for a JSON object with
      // "translation" field.
      // --------------------------------------------------------------------------------
      
      let content: String = """
                You are an AI assistant specialized in data extraction and transformation. Your task is to provide translations from \(sourceLanguage.rawValue) to \(targetLanguage.rawValue) based on the provided input.
                
                You will be given:
                1. A series of text inputs to translate.
                2. A key for each input providing contextual information. The key appears at the end of each line, prefixed with 'KEY:'.
                3. An optional comment for additional context. The comment appears at the end of each line, prefixed with 'COMMENT:'. If no comment is provided, 'COMMENT: N/A' will be included.
                
                Instructions:
                - Analyze the 'KEY:' to determine the context of the translation.
                - Use the 'COMMENT:' to extract any additional context, if available.
                - For buttons, provide very short translations suitable for UI elements.
                - For marketing content, produce concise and engaging marketing copy.
                - Incorporate additional context, if provided: \(context).
                
                Input Format:
                Each text input appears on a new line, followed by its key ('KEY:') and optional comment ('COMMENT:').
                
                Example Input:
                Save Changes KEY:L10n.Localizable.HomeSUI.okButton COMMENT:N/A
                Limited Offer! Get 20% Off KEY:L10n.Localizable.Marketing.get20percentOff COMMENT:holiday promotion
                
                Output Format:
                Return ONLY valid JSON adhering to the following schema:
                {
                  "translations": [
                    { "text": "Your translated text here" }
                  ]
                }
                
                Important:
                - Do not include any extra text, comments, or keys outside the JSON structure.
                - Ensure the JSON syntax is valid and properly formatted.
                """
      let systemMessage = OpenAIChatMessage(
        role: "system",
        content: content
      )
      
      let userMessage = OpenAIChatMessage(
        role: "user",
        content: sources.map({ "\($0.text) KEY:\($0.key) COMMENT:\($0.comment ?? "N/A")" }).joined(separator: "\n")
      )
      
      let messages = [systemMessage, userMessage]
      
      // Create a structured request object to encode as JSON.
      let requestPayload = OpenAIChatCompletionRequest(
        model: "gpt-4o",
        messages: messages,
        temperature: 0.0
      )
      
      // Encode the request to JSON data.
      guard let bodyData = try? JSONEncoder().encode(requestPayload) else {
        fatalError("Failed to encode OpenAI request as JSON.")
      }
      
      // Return a POST request with the JSON body.
      return .post(body: bodyData)
    }
  }
  
  // MARK: - Headers
  
  /// Custom headers for the request.
  /// Note that OpenAI expects a Bearer token for authorization and JSON content.
  var headers: [String : String] {
    switch self {
    case let .translate(_, _, _, _, apiKey):
      return [
        "Authorization": "Bearer \(apiKey)",
        "Content-Type": "application/json"
      ]
    }
  }
  
  // MARK: - Base URL
  
  /// The base URL for the OpenAI API.
  static func baseUrl() -> URL {
    return URL(string: "https://api.openai.com")!
  }
}

// MARK: - Helper Models

/// Structure that represents a message in the OpenAI Chat API (system, user, or assistant).
/// - Parameters:
///   - role: The role of the message in the chat ("system", "user", "assistant").
///   - content: The actual text of the message.
struct OpenAIChatMessage: Codable {
  let role: String
  let content: String
}

/// Structure representing the request payload for Chat Completion.
/// - Parameters:
///   - model: The OpenAI model to use (e.g., "gpt-4", "model-40", etc.).
///   - messages: An array of messages for the Chat Completion API.
///   - temperature: What sampling temperature to use, 0 for deterministic output.
struct OpenAIChatCompletionRequest: Codable {
  let model: String
  let messages: [OpenAIChatMessage]
  let temperature: Double
}

/// An example error response structure from the OpenAI API.
/// Adjust it to match OpenAI's actual error response format as needed.
struct OpenAITranslateErrorResponse: Codable, Error {
  let error: OpenAIError
}

struct OpenAIError: Codable {
  let message: String
  let type: String?
  let code: String?
}
