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
    @FocusState private var isInputFieldFocused: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header
            HStack(alignment: .center) {
                HStack(spacing: 8) {
                    Image(systemName: "checklist")
                        .symbolRenderingMode(.hierarchical)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(Color.omniAccent)
                    
                    Text("TASKS & ACTIONS")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(Color.omniTextSecondary)
                        .tracking(0.6)
                    
                    Text("\(viewModel.tasks.count)")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(Color.omniTextPrimary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.omniPillBackground)
                        .clipShape(Capsule())
                }
                
                Spacer()
                
                if !viewModel.tasks.isEmpty {
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            viewModel.tasks.removeAll()
                        }
                    }) {
                        Text("Clear All")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(Color.omniTextSecondary)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .focusable(false)
                }
            }
            
            // Minimalist Quick Add Input Row
            HStack(spacing: 10) {
                Image(systemName: "plus")
                    .symbolRenderingMode(.hierarchical)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Color.omniTextMuted)
                
                TextField("Add task manually...", text: $newTaskTitle)
                    .textFieldStyle(PlainTextFieldStyle())
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(Color.omniTextPrimary)
                    .focused($isInputFieldFocused)
                    .onSubmit {
                        commitManualTask()
                    }
                
                if !newTaskTitle.isEmpty {
                    Button(action: commitManualTask) {
                        KeyboardShortcutBadge(shortcut: "↵")
                    }
                    .buttonStyle(PlainButtonStyle())
                    .focusable(false)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(Color.omniInputSurface)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(isInputFieldFocused ? Color.omniAccent.opacity(0.5) : Color.omniBorder, lineWidth: 1)
            )
            
            // Task List or Empty State
            if viewModel.tasks.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "tray")
                        .symbolRenderingMode(.hierarchical)
                        .font(.system(size: 26, weight: .light))
                        .foregroundColor(Color.omniTextMuted)
                        .padding(.top, 14)
                    
                    Text("No pending tasks")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(Color.omniTextSecondary)
                    
                    Text("Speak into the mic or type above to queue tasks.")
                        .font(.system(size: 11))
                        .foregroundColor(Color.omniTextMuted)
                        .padding(.bottom, 14)
                }
                .frame(maxWidth: .infinity)
                .background(Color.omniInputSurface.opacity(0.5))
                .cornerRadius(8)
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(viewModel.tasks) { task in
                            MinimalTaskRow(
                                task: task,
                                onToggle: { viewModel.toggleTask(id: task.id) },
                                onDelete: { viewModel.deleteTask(id: task.id) }
                            )
                        }
                    }
                    .padding(.vertical, 2)
                }
                .frame(maxHeight: 260)
            }
        }
        .minimalCard(padding: 18, cornerRadius: 14)
    }
    
    private func commitManualTask() {
        guard !newTaskTitle.isEmpty else { return }
        viewModel.addManualTask(title: newTaskTitle)
        newTaskTitle = ""
    }
}

// MARK: - Minimalist Linear-Style Task Row
private struct MinimalTaskRow: View {
    let task: TodoTask
    let onToggle: () -> Void
    let onDelete: () -> Void
    
    @State private var isHovered: Bool = false
    
    var body: some View {
        HStack(spacing: 10) {
            // Minimalist Radio Toggle
            Button(action: onToggle) {
                Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                    .symbolRenderingMode(.hierarchical)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(task.isCompleted ? Color.omniEmerald : Color.omniTextMuted)
            }
            .buttonStyle(PlainButtonStyle())
            .focusable(false)
            
            // Title & Chips
            VStack(alignment: .leading, spacing: 3) {
                Text(task.title)
                    .font(.system(size: 13, weight: .regular))
                    .strikethrough(task.isCompleted, color: Color.omniTextMuted)
                    .foregroundColor(task.isCompleted ? Color.omniTextMuted : Color.omniTextPrimary)
                
                if task.date != nil || task.time != nil {
                    HStack(spacing: 6) {
                        if let date = task.date {
                            HStack(spacing: 3) {
                                Image(systemName: "calendar")
                                    .font(.system(size: 9))
                                Text(date)
                            }
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundColor(Color.omniAccent)
                        }
                        if let time = task.time {
                            HStack(spacing: 3) {
                                Image(systemName: "clock")
                                    .font(.system(size: 9))
                                Text(time)
                            }
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundColor(Color.omniTextSecondary)
                        }
                    }
                }
            }
            
            Spacer()
            
            // Delete action on hover
            if isHovered {
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .symbolRenderingMode(.hierarchical)
                        .font(.system(size: 12))
                        .foregroundColor(Color.omniRed)
                }
                .buttonStyle(PlainButtonStyle())
                .focusable(false)
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(isHovered ? Color.omniPillBackground : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) {
                isHovered = hovering
            }
        }
    }
}
