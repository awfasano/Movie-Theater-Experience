//
//  TriviaQuestionView.swift
//  Movie Theater Experience
//
//  Displays trivia questions to participants with media support
//

import SwiftUI
import AVKit

struct TriviaQuestionView: View {
    let question: TriviaQuestion
    let onSubmit: (String) -> Void

    @State private var selectedAnswerIndex: Int?
    @State private var textAnswer: String = ""
    @State private var hasSubmitted: Bool = false

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Question header
                questionHeader

                // Media display (image or video)
                if question.mediaType != .none {
                    mediaSection
                }

                // Question text
                Text(question.questionText)
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)
                    .padding()

                // Answer input based on question type
                answerInputSection

                // Submit button
                submitButton
            }
            .padding()
        }
        .background(.ultraThinMaterial)
    }

    // MARK: - Question Header

    private var questionHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                if let category = question.category {
                    Text(category.uppercased())
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.blue)
                }

                Text("\(question.points) Points")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            HStack(spacing: 4) {
                Image(systemName: "clock.fill")
                Text("\(question.timeLimit)s")
            }
            .font(.caption)
            .foregroundColor(.orange)
        }
        .padding()
        .background(.regularMaterial)
        .cornerRadius(12)
    }

    // MARK: - Media Section

    private var mediaSection: some View {
        Group {
            switch question.mediaType {
            case .image:
                if let urlString = question.mediaURL, let url = URL(string: urlString) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .empty:
                            ProgressView()
                                .frame(height: 300)
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(maxHeight: 300)
                                .cornerRadius(12)
                        case .failure:
                            VStack {
                                Image(systemName: "photo.fill")
                                    .font(.largeTitle)
                                    .foregroundColor(.secondary)
                                Text("Failed to load image")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .frame(height: 300)
                        @unknown default:
                            EmptyView()
                        }
                    }
                }

            case .video:
                if let urlString = question.mediaURL, let url = URL(string: urlString) {
                    VideoPlayer(player: AVPlayer(url: url))
                        .frame(height: 300)
                        .cornerRadius(12)
                }

            case .none:
                EmptyView()
            }
        }
    }

    // MARK: - Answer Input

    private var answerInputSection: some View {
        Group {
            switch question.questionType {
            case .multipleChoice:
                multipleChoiceSection

            case .trueFalse:
                trueFalseSection

            case .textInput:
                textInputSection
            }
        }
    }

    private var multipleChoiceSection: some View {
        VStack(spacing: 12) {
            Text("Select your answer:")
                .font(.headline)
                .foregroundColor(.secondary)

            ForEach(Array(question.options.enumerated()), id: \.offset) { index, option in
                Button {
                    if !hasSubmitted {
                        selectedAnswerIndex = index
                    }
                } label: {
                    HStack {
                        // Option letter (A, B, C, D)
                        Text(String(UnicodeScalar(65 + index)!))
                            .font(.title3.bold())
                            .foregroundColor(selectedAnswerIndex == index ? .white : .blue)
                            .frame(width: 40, height: 40)
                            .background(selectedAnswerIndex == index ? .blue : .blue.opacity(0.1))
                            .clipShape(Circle())

                        Text(option)
                            .font(.body)
                            .foregroundColor(.primary)
                            .multilineTextAlignment(.leading)

                        Spacer()

                        if selectedAnswerIndex == index {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.blue)
                                .font(.title3)
                        }
                    }
                    .padding()
                    .background(selectedAnswerIndex == index ? .blue.opacity(0.1) : .gray.opacity(0.05))
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(selectedAnswerIndex == index ? Color.blue : Color.clear, lineWidth: 2)
                    )
                }
                .buttonStyle(.plain)
                .disabled(hasSubmitted)
            }
        }
    }

    private var trueFalseSection: some View {
        HStack(spacing: 16) {
            // True button
            Button {
                if !hasSubmitted {
                    selectedAnswerIndex = 0
                }
            } label: {
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 50))
                        .foregroundColor(selectedAnswerIndex == 0 ? .white : .green)

                    Text("TRUE")
                        .font(.title3.bold())
                        .foregroundColor(selectedAnswerIndex == 0 ? .white : .green)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 30)
                .background(selectedAnswerIndex == 0 ? .green : .green.opacity(0.1))
                .cornerRadius(16)
            }
            .buttonStyle(.plain)
            .disabled(hasSubmitted)

            // False button
            Button {
                if !hasSubmitted {
                    selectedAnswerIndex = 1
                }
            } label: {
                VStack(spacing: 8) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 50))
                        .foregroundColor(selectedAnswerIndex == 1 ? .white : .red)

                    Text("FALSE")
                        .font(.title3.bold())
                        .foregroundColor(selectedAnswerIndex == 1 ? .white : .red)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 30)
                .background(selectedAnswerIndex == 1 ? .red : .red.opacity(0.1))
                .cornerRadius(16)
            }
            .buttonStyle(.plain)
            .disabled(hasSubmitted)
        }
    }

    private var textInputSection: some View {
        VStack(spacing: 12) {
            Text("Type your answer:")
                .font(.headline)
                .foregroundColor(.secondary)

            TextField("Enter your answer here...", text: $textAnswer, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .font(.body)
                .lineLimit(1...3)
                .disabled(hasSubmitted)
                .padding()
                .background(.white.opacity(0.9))
                .cornerRadius(12)
        }
    }

    // MARK: - Submit Button

    private var submitButton: some View {
        Button {
            submitAnswer()
        } label: {
            HStack {
                Image(systemName: hasSubmitted ? "checkmark.circle.fill" : "lock.circle.fill")
                Text(hasSubmitted ? "Answer Submitted" : "Submit Answer")
            }
            .font(.headline)
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding()
            .background(hasSubmitted ? .green : canSubmit ? .blue : .gray)
            .cornerRadius(12)
        }
        .disabled(!canSubmit || hasSubmitted)
    }

    private var canSubmit: Bool {
        switch question.questionType {
        case .multipleChoice, .trueFalse:
            return selectedAnswerIndex != nil
        case .textInput:
            return !textAnswer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private func submitAnswer() {
        guard !hasSubmitted else { return }

        hasSubmitted = true

        let answer: String
        switch question.questionType {
        case .multipleChoice, .trueFalse:
            answer = "\(selectedAnswerIndex ?? -1)"
        case .textInput:
            answer = textAnswer.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        onSubmit(answer)
    }
}

// MARK: - Preview

#if DEBUG
struct TriviaQuestionView_Previews: PreviewProvider {
    static var previews: some View {
        VStack {
            // Multiple choice with image
            TriviaQuestionView(
                question: TriviaQuestion(
                    questionText: "What is the capital of France?",
                    questionType: .multipleChoice,
                    options: ["London", "Paris", "Berlin", "Madrid"],
                    correctAnswer: 1,
                    mediaType: .image,
                    mediaURL: "https://example.com/france.jpg",
                    category: "Geography"
                ),
                onSubmit: { _ in }
            )

            // True/False
            TriviaQuestionView(
                question: TriviaQuestion(
                    questionText: "The Earth is flat.",
                    questionType: .trueFalse,
                    options: ["True", "False"],
                    correctAnswer: 1,
                    category: "Science"
                ),
                onSubmit: { _ in }
            )

            // Text input
            TriviaQuestionView(
                question: TriviaQuestion(
                    questionText: "Who painted the Mona Lisa?",
                    questionType: .textInput,
                    correctTextAnswer: "Leonardo da Vinci",
                    category: "Art"
                ),
                onSubmit: { _ in }
            )
        }
    }
}
#endif
