import Foundation

/// Paging state for a lesson stage's slide deck. Assessment stages never construct one of these —
/// they skip straight to `PathQuizView` (design doc §5).
@Observable
final class PathLessonSession {
    let slides: [PathSlide]
    private(set) var currentIndex = 0

    init(slides: [PathSlide]) {
        self.slides = slides
    }

    var currentSlide: PathSlide? {
        guard currentIndex < slides.count else { return nil }
        return slides[currentIndex]
    }

    var isFinished: Bool { currentIndex >= slides.count }
    var isFirstSlide: Bool { currentIndex == 0 }
    var isLastSlide: Bool { currentIndex == slides.count - 1 }

    func advance() {
        currentIndex = min(currentIndex + 1, slides.count)
    }

    func goBack() {
        currentIndex = max(currentIndex - 1, 0)
    }
}
