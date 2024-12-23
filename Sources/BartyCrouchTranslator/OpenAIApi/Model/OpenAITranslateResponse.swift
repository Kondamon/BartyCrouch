import Foundation

struct OpenAITranslateResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable {
            struct Content: Decodable {
                struct Translation: Decodable {
                    let text: String
                }
                let translations: [Translation]
            }

            let role: String
            let content: Content
            let refusal: String?

            // Custom decoding to parse JSON string in 'content'
            private enum CodingKeys: String, CodingKey {
                case role, content, refusal
            }

            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                role = try container.decode(String.self, forKey: .role)

                // Decode `content` as a JSON string and parse it as JSON
                let contentString = try container.decode(String.self, forKey: .content)
                let contentData = Data(contentString.utf8)
                content = try JSONDecoder().decode(Content.self, from: contentData)

                refusal = try container.decodeIfPresent(String.self, forKey: .refusal)
            }
        }

        let index: Int
        let message: Message
        let logprobs: String?
        let finishReason: String
    }

    let id: String
    let object: String
    let created: Int
    let model: String
    let choices: [Choice]
}
