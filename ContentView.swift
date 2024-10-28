//
//  ContentView.swift
//  Dog or Cat
//
//  Created by Ignacio Arias on 2024-09-17.
//

// MARK: - Sound Classifier

import SwiftUI
import AVFoundation
import SoundAnalysis

class AudioStreamAnalyzerObserver: NSObject, ObservableObject, SNResultsObserving {
    @Published var classificationLabel: String = "Press Record to Start"
    @Published var confidenceLevel: Double = 0.0

    func request(_ request: SNRequest, didProduce result: SNResult) {
        guard let classificationResult = result as? SNClassificationResult,
              let classification = classificationResult.classifications.first else { return }

        DispatchQueue.main.async {
            self.confidenceLevel = classification.confidence
            if classification.confidence > 0.5 {
                self.classificationLabel = "\(classification.identifier) (\(Int(classification.confidence * 100))% Confidence)"
            } else {
                self.classificationLabel = "Uncertain"
            }
        }
    }

    func request(_ request: SNRequest, didFailWithError error: Error) {
        DispatchQueue.main.async {
            print("Classification error: \(error.localizedDescription)")
        }
    }

    func requestDidComplete(_ request: SNRequest) {
        print("Analysis Complete")
    }
}

struct ContentView: View {
    @StateObject private var analyzerObserver = AudioStreamAnalyzerObserver()
    @State private var isRecording = false
    @State private var showAlert = false
    @State private var alertMessage = ""

    private let audioEngine = AVAudioEngine()
    @State private var inputFormat: AVAudioFormat?
    @State private var streamAnalyzer: SNAudioStreamAnalyzer?
    private let analysisQueue = DispatchQueue(label: "com.dogorcat.analysis")

    var body: some View {
        VStack(spacing: 20) {
            Text("Pet Sound Classifier")
                .font(.largeTitle)
                .fontWeight(.bold)
            Text("🐶 or 🐱")
                .font(.largeTitle)
                .fontWeight(.semibold)
                .padding()

            Text(analyzerObserver.classificationLabel)
                .font(.title2)
                .multilineTextAlignment(.center)
                .padding()
                .frame(height: 80)

            Button(action: toggleRecording) {
                Text(isRecording ? "Stop Recording" : "Start Recording")
                    .font(.headline)
                    .padding()
                    .frame(minWidth: 200)
                    .background(isRecording ? Color.red : Color.green)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }

            if isRecording {
                ProgressView("Analyzing...")
                    .progressViewStyle(CircularProgressViewStyle())
            }

            ConfidenceMeter(confidence: analyzerObserver.confidenceLevel)
                .frame(height: 20)
                .padding()
        }
        .padding()
        .onAppear(perform: setupAudio)
        .alert(isPresented: $showAlert) {
            Alert(title: Text("Error"), message: Text(alertMessage), dismissButton: .default(Text("OK")))
        }
    }

    private func setupAudio() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playAndRecord, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
            inputFormat = audioEngine.inputNode.inputFormat(forBus: 0)
            if let inputFormat = inputFormat {
                streamAnalyzer = SNAudioStreamAnalyzer(format: inputFormat)
            }

            AVAudioApplication.requestRecordPermission { granted in
                DispatchQueue.main.async {
                    if !granted {
                        self.showAlert = true
                        self.alertMessage = "Microphone access denied."
                    }
                }
            }
        } catch {
            DispatchQueue.main.async {
                showAlert = true
                alertMessage = "Error setting up audio: \(error.localizedDescription)"
            }
        }
    }

    private func toggleRecording() {
        isRecording.toggle()
        if isRecording {
            startRecording()
        } else {
            stopRecording()
        }
    }

    private func startRecording() {
        guard let inputFormat = inputFormat, let streamAnalyzer = streamAnalyzer else {
            showAlert = true
            alertMessage = "Audio setup incomplete"
            isRecording = false
            return
        }

        do {
            // Replace with the correct name of the generated Core ML model class
            let model = try CreateMLDogCatClassifier(configuration: MLModelConfiguration()) // Ensure this matches your model
            let request = try SNClassifySoundRequest(mlModel: model.model)
            streamAnalyzer.removeAllRequests()
            try streamAnalyzer.add(request, withObserver: analyzerObserver)

            let inputNode = audioEngine.inputNode
            inputNode.installTap(onBus: 0, bufferSize: 8192, format: inputFormat) { buffer, time in
                self.analysisQueue.async {
                    streamAnalyzer.analyze(buffer, atAudioFramePosition: time.sampleTime)
                }
            }
            try audioEngine.start()
        } catch {
            DispatchQueue.main.async {
                showAlert = true
                alertMessage = "Error starting recording: \(error.localizedDescription)"
                isRecording = false
            }
        }
    }

    private func stopRecording() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
    }
}

struct ConfidenceMeter: View {
    let confidence: Double

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: geometry.size.width, height: geometry.size.height)

                Rectangle()
                    .fill(confidence > 0.7 ? Color.green : (confidence > 0.4 ? Color.yellow : Color.red))
                    .frame(width: CGFloat(confidence) * geometry.size.width, height: geometry.size.height)
            }
            .cornerRadius(5)
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
