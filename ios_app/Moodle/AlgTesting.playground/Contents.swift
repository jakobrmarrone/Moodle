import CreateML
import Foundation

// === EDIT THESE THREE PATHS ===
// Each should be a folder containing one subfolder per class
// (Low_Negative/, High_Positive/, Medium_Neutral/, etc.) with audio files inside.
let trainURL  = URL(fileURLWithPath: "/Users/jakobmarrone/Documents/PlatformIO/AppleML/Train")
let testURL   = URL(fileURLWithPath: "/Users/jakobmarrone/Documents/PlatformIO/AppleML/Test")
let outputCSV = URL(fileURLWithPath: "/Users/jakobmarrone/Documents/PlatformIO/AppleML/confusion.csv")

let trainingData = MLSoundClassifier.DataSource.labeledDirectories(at: trainURL)
let testingData  = MLSoundClassifier.DataSource.labeledDirectories(at: testURL)

print("Training… (a couple minutes)")
let classifier = try MLSoundClassifier(trainingData: trainingData)

print("Evaluating on test set…")
let metrics = classifier.evaluation(on: testingData)

// The confusion table — rows of (True Label, Predicted, Count)
let confusion = metrics.confusion
print(confusion)

try confusion.writeCSV(to: outputCSV)
print("Wrote confusion data to \(outputCSV.path)")

// Optional: also save the trained model so you don't have to redo this
let modelURL = URL(fileURLWithPath: "/Users/jakobmarrone/Documents/PlatformIO/AppleML/DogSense_fromSwift.mlmodel")
try classifier.write(to: modelURL)
