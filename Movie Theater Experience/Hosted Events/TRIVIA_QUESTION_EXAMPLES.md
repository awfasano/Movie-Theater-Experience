# Trivia Question Examples

## Question Types Supported

### 1. Multiple Choice
```swift
let question = TriviaQuestion(
    questionText: "What is the capital of France?",
    questionType: .multipleChoice,
    options: ["London", "Paris", "Berlin", "Madrid"],
    correctAnswer: 1, // Index of "Paris"
    points: 10,
    timeLimit: 30,
    category: "Geography"
)
```

### 2. True/False
```swift
let question = TriviaQuestion(
    questionText: "The Earth is flat.",
    questionType: .trueFalse,
    options: ["True", "False"],
    correctAnswer: 1, // Index of "False"
    points: 5,
    timeLimit: 15,
    category: "Science"
)
```

### 3. Text Input
```swift
let question = TriviaQuestion(
    questionText: "Who painted the Mona Lisa?",
    questionType: .textInput,
    correctTextAnswer: "Leonardo da Vinci",
    points: 15,
    timeLimit: 45,
    category: "Art"
)
```

## Media Support

### Image Question
```swift
let question = TriviaQuestion(
    questionText: "What landmark is shown in this image?",
    questionType: .multipleChoice,
    options: ["Eiffel Tower", "Big Ben", "Statue of Liberty", "Colosseum"],
    correctAnswer: 0,
    mediaType: .image,
    mediaURL: "https://example.com/landmark.jpg",
    category: "Geography"
)
```

### Video Question
```swift
let question = TriviaQuestion(
    questionText: "What movie is this scene from?",
    questionType: .textInput,
    correctTextAnswer: "The Matrix",
    mediaType: .video,
    mediaURL: "https://example.com/movie-clip.mp4",
    category: "Movies"
)
```

## Firebase Schema

Questions should be stored in Firebase with this structure:

```json
{
  "id": "question-123",
  "questionText": "What is 2+2?",
  "questionType": "multiple_choice",
  "options": ["2", "3", "4", "5"],
  "correctAnswer": 2,
  "correctTextAnswer": null,
  "points": 10,
  "timeLimit": 30,
  "mediaType": "none",
  "mediaURL": null,
  "category": "Math",
  "round": 1
}
```

## Answer Submission Format

When participants submit answers, they're stored as:

```json
{
  "tableNumber": 1,
  "submittedAt": "2025-01-07T10:30:00Z",
  "locked": true,
  "answer": "1" // For multiple choice (index) or text for text input
}
```

## UI Features

### Participant View
- **Multiple Choice**: Letter-labeled buttons (A, B, C, D)
- **True/False**: Large green/red buttons
- **Text Input**: Text field for typing answers
- **Media Display**: Automatic image/video player above question
- **Submit Button**: Locks in answer and prevents changes

### Host View
- **Submission Tracking**: See which tables have submitted
- **Real-time Updates**: Live count of submissions
- **Clear Submissions**: Reset for next question
- **Answer Display**: Can see submitted answers (if needed)
