//
//  ContentView.swift
//  OmniDesk
//
//  Created by Dhruvil Patel on 31/03/26.
//

import SwiftUI

struct DashboardView: View {
    
    @StateObject private var voiceService = VoiceService()
    @StateObject private var viewModel = MainViewModel()
    
    var body: some View {
        VStack(spacing: 20) {
            
            Text("OmniDesk")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            Text("Your AI Assistant Hub")
                .foregroundColor(.gray)
            
            Button(action: {
                voiceService.startRecording()
            }) {
                Text("🎙️ Start Speaking")
                    .padding()
                    .frame(width: 220)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }
            
            Button(action: {
                voiceService.stopRecording()
                viewModel.addTask(from: voiceService.recognizedText)
            }) {
                Text("⏹ Stop & Save Task")
                    .padding()
                    .frame(width: 220)
                    .background(Color.red)
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }
            
            Text("Recognized:")
                .font(.headline)
            
            Text(voiceService.recognizedText)
                .padding()
            
            List {
                ForEach(viewModel.tasks) { task in
                    Text(task.title)
                }
            }
        }
        .padding()
    }
}

#Preview {
    DashboardView()
}
