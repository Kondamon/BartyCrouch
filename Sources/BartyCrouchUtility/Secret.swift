import Foundation

public enum Secret: Equatable {
  case microsoftTranslator(secret: String)
  case deepL(secret: String)
  case openAI(secret: String, context: String)
}
