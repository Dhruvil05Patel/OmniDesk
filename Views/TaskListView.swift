//
//  TaskListView.swift
//  OmniDesk
//
//  Created by Dhruvil Patel on 31/03/26.
//

import SwiftUI

struct TaskListView: View {
    @ObservedObject var viewModel: MainViewModel
    @State private var newTaskTitle: String = ""
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "checklist")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.indigo)
                    
                    Text("Tasks & Actions")
                        .font(.system(size: 17, weight: .bold))
                    
                    Text("\(viewModel.tasks.count)")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundColor(.indigo)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.indigo.opacity(0.15))
                        .clipShape(Capsule())
                }
                
                Spacer()
                
                if !viewModel.tasks.isEmpty {
                    Button(action: {
                        withAnimation {
                            viewModel.tasks.removeAll()
                        }
                    }) {
                        Text("Clear All")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            
            // Manual Add Row
            HStack(spacing: 8) {
                Image(systemName: "plus.circle.fill")
                    .foregroundColor(.secondary)
                
                TextField("Add task manually...", text: $newTaskTitle)
                    .textFieldStyle(PlainTextFieldStyle())
                    .onSubmit {
                        commitManualTask()
                    }
                
                if !newTaskTitle.isEmpty {
                    Button(action: commitManualTask) {
                        Text("Add")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Color.indigo)
                            .cornerRadius(6)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
            .cornerRadius(10)
            
            // Task List Content
            if viewModel.tasks.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.badge.questionmark")
                        .font(.system(size: 36))
                        .foregroundColor(.secondary.opacity(0.4))
                        .padding(.top, 20)
                    
                    Text("No tasks yet")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.secondary)
                    
                    Text("Speak into the microphone above or type to add items.")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .padding(.bottom, 20)
                }
                .frame(maxWidth: .infinity)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.2))
                .cornerRadius(12)
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(viewModel.tasks) { task in
                            TaskRowView(
                                task: task,
                                onToggle: { viewModel.toggleTask(id: task.id) },
                                onDelete: { viewModel.deleteTask(id: task.id) }
                            )
                        }
                    }
                    .padding(.vertical, 2)
                }
                .frame(maxHeight: 280)
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color(NSColor.windowBackgroundColor).opacity(0.75))
                .shadow(color: Color.black.opacity(0.08), radius: 10, x: 0, y: 3)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }
    
    private func commitManualTask() {
        guard !newTaskTitle.isEmpty else { return }
        viewModel.addManualTask(title: newTaskTitle)
        newTaskTitle = ""
    }
}

// Individual Task Card
private struct TaskRowView: View {
    let task: TodoTask
    let onToggle: () -> Void
    let onDelete: () -> Void
    
    @State private var isHovered: Bool = false
    
    var body: some View {
        HStack(spacing: 12) {
            // Checkmark Toggle
            Button(action: onToggle) {
                Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundColor(task.isCompleted ? .emerald : .secondary)
            }
            .buttonStyle(PlainButtonStyle())
            
            // Title & Badges
            VStack(alignment: .leading, spacing: 4) {
                Text(task.title)
                    .font(.system(size: 14, weight: .medium))
                    .strikethrough(task.isCompleted, color: .secondary)
                    .foregroundColor(task.isCompleted ? .secondary : .primary)
                
                if task.date != nil || task.time != nil {
                    HStack(spacing: 6) {
                        if let date = task.date {
                            Label(date, systemImage: "calendar")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.indigo)
                        }
                        if let time = task.time {
                            Label(time, systemImage: "clock")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.cyan)
                        }
                    }
                }
            }
            
            Spacer()
            
            // Delete button on hover
            if isHovered {
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 13))
                        .foregroundColor(.red.opacity(0.8))
                }
                .buttonStyle(PlainButtonStyle())
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color(NSColor.controlBackgroundColor).opacity(isHovered ? 0.7 : 0.4))
        .cornerRadius(10)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}

private extension Color {
    static let emerald = Color(red: 16/255, green: 185/255, blue: 129/255)
}
