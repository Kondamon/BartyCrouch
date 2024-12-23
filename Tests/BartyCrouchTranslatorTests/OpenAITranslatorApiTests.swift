@testable import BartyCrouchTranslator
import Foundation
import Microya
import XCTest

class OpenAITranslatorApiTests: XCTestCase {
  func testTranslate() {
    let apiKey = try! Secrets.load().openAIApiKey  // swiftlint:disable:this force_try
    guard !apiKey.isEmpty else { return }

    let endpoint = OpenAIApi.translate(
      sources: [.init(key: "noKey", text: "How old are you?", comment: nil),
              .init(key: "key.button", text: "Love", comment: nil),
              .init(key: "key.button", text: "Completed", comment: nil)
      ],
      from: .english,
      to: .german,
      context: "You have to use informal tone!",
      apiKey: apiKey
    )

    let apiProvider = ApiProvider<OpenAIApi>(baseUrl: OpenAIApi.baseUrl())

    switch apiProvider.performRequestAndWait(on: endpoint, decodeBodyTo: OpenAITranslateResponse.self) {
    case let .success(translateResponses):
      XCTAssertEqual(translateResponses.choices.first?.message.content.translations[0].text, "Wie alt bist du?")
      XCTAssertEqual(translateResponses.choices.first?.message.content.translations[1].text, "Liebe")
      XCTAssertEqual(translateResponses.choices.first?.message.content.translations[2].text, "Abgeschlossen")
    case let .failure(failure):
      XCTFail(failure.localizedDescription)
    }
  }
}
