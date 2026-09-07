import Foundation

@Observable
final class QuestionRepository {
    let todayQuestions: [Question]

    init(bundle: Bundle = .main) {
        todayQuestions = Self.decode([Question].self, filename: "questions", bundle: bundle) ?? []
    }
}

func decodeJSONResource<T: Decodable>(_ type: T.Type, filename: String, bundle: Bundle) -> T? {
    guard let url = bundle.url(forResource: filename, withExtension: "json"),
          let data = try? Data(contentsOf: url) else { return nil }
    return try? JSONDecoder().decode(T.self, from: data)
}

private extension QuestionRepository {
    static func decode<T: Decodable>(_ type: T.Type, filename: String, bundle: Bundle) -> T? {
        decodeJSONResource(type, filename: filename, bundle: bundle)
    }
}
