//
//  ImmersiveQuestionBoard.swift
//  Movie Theater Experience
//
//  VisionOS-friendly overlays that surface the active trivia question
//  (including media) above each collaborative table.
//

import SwiftUI
import AVKit

struct ImmersiveQuestionBoard: View {
    let question: TriviaQuestion
    let tableNumber: Int
    let timeRemaining: Int

    private var questionTypeLabel: String {
        switch question.questionType {
        case .multipleChoice:
            return "Multiple choice"
        case .trueFalse:
            return "True or false"
        case .textInput:
            return "Free response"
        }
    }

    private var timerDescription: String {
        timeRemaining > 0 ? "\(timeRemaining)s left" : "Awaiting host"
    }

    var body: some View {
        VStack(spacing: 16) {
            header

            if question.mediaType != .none {
                mediaSection
            }

            Text(question.questionText)
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            metadataRow

            if !question.options.isEmpty {
                optionsList
            } else if let answer = question.correctTextAnswer {
                Text("Type your answer: \(answer.count) characters")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
        }
        .padding(24)
        .frame(width: 420)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: .black.opacity(0.15), radius: 16, x: 0, y: 12)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Table \(tableNumber)")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)

                Text(question.category ?? "General Trivia")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Label(timerDescription, systemImage: "clock.fill")
                .font(.caption.weight(.medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.orange.opacity(0.15), in: Capsule())
        }
    }

    @ViewBuilder
    private var mediaSection: some View {
        switch question.mediaType {
        case .image:
            if let urlString = question.mediaURL, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        ProgressView()
                            .frame(height: 180)
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 200)
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    case .failure:
                        placeholderMedia(icon: "photo.fill", message: "Media unavailable")
                    @unknown default:
                        EmptyView()
                    }
                }
            } else {
                placeholderMedia(icon: "photo.fill", message: "Image missing")
            }
        case .video:
            if let urlString = question.mediaURL, let url = URL(string: urlString) {
                VideoPlayer(player: AVPlayer(url: url))
                    .frame(height: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            } else {
                placeholderMedia(icon: "play.rectangle.fill", message: "Video unavailable")
            }
        case .none:
            EmptyView()
        }
    }

    private func placeholderMedia(icon: String, message: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(message)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 180)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var metadataRow: some View {
        HStack {
            Label("\(question.points) pts", systemImage: "star.fill")
                .foregroundStyle(.yellow)
                .font(.caption.weight(.semibold))

            Spacer()

            Text(questionTypeLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal)
    }

    private var optionsList: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(question.options.enumerated()), id: \.offset) { index, option in
                HStack(alignment: .top, spacing: 8) {
                    Text(String(UnicodeScalar(65 + index)!))
                        .font(.caption.weight(.bold))
                        .frame(width: 20, height: 20)
                        .background(.blue.opacity(0.2), in: Circle())

                    Text(option)
                        .font(.subheadline)
                        .foregroundColor(.primary)
                        .multilineTextAlignment(.leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal)
    }
}

struct ImmersiveWaitingBoard: View {
    let tableNumber: Int

    var body: some View {
        VStack(spacing: 16) {
            Text("Table \(tableNumber)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Image(systemName: "hourglass")
                .font(.largeTitle)
                .foregroundStyle(.secondary)

            Text("Waiting for the host to start the next question.")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
        }
        .padding(24)
        .frame(width: 320)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.1), radius: 12, x: 0, y: 10)
    }
}
