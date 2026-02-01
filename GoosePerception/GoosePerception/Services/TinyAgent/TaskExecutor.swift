//
// TaskExecutor.swift
//
// Executes parsed tasks with dependency resolution and parallel execution.
//

import Foundation

/// Result of executing a single task
struct TaskExecutionResult {
    let taskId: Int
    let toolName: String
    let success: Bool
    let output: String
    let error: String?
    let duration: TimeInterval
}

/// Result of executing a full plan
struct PlanExecutionResult {
    let taskResults: [TaskExecutionResult]
    let observations: [Int: String]  // taskId -> output
    let totalDuration: TimeInterval
    let allSucceeded: Bool
    
    /// Format as observation string for joinner
    var observationText: String {
        taskResults.map { result in
            """
            \(result.toolName)(...)
            Observation: \(result.success ? result.output : "Error: \(result.error ?? "Unknown error")")
            """
        }.joined(separator: "\n")
    }
}

/// Executes tasks from a parsed plan
actor TaskExecutor {
    static let shared = TaskExecutor()
    
    private init() {}
    
    /// Execute a plan with parallel task execution where possible
    func execute(tasks: [ParsedTask]) async -> PlanExecutionResult {
        let startTime = Date()
        var taskResults: [TaskExecutionResult] = []
        var outputs: [Int: String] = [:]
        var allSucceeded = true
        
        // Build dependency graph
        let dependencyGraph = buildDependencyGraph(tasks: tasks)
        
        // Group tasks by dependency level (tasks with same dependencies can run in parallel)
        let executionLevels = buildExecutionLevels(tasks: tasks, dependencyGraph: dependencyGraph)
        
        // Execute each level
        for level in executionLevels {
            // Execute tasks at this level in parallel
            let levelResults = await withTaskGroup(of: TaskExecutionResult.self) { group in
                for task in level {
                    // Skip join() - it's handled separately
                    if task.isJoin {
                        continue
                    }
                    
                    group.addTask {
                        await self.executeTask(task, outputs: outputs)
                    }
                }
                
                var results: [TaskExecutionResult] = []
                for await result in group {
                    results.append(result)
                }
                return results
            }
            
            // Collect results
            for result in levelResults {
                taskResults.append(result)
                outputs[result.taskId] = result.output
                if !result.success {
                    allSucceeded = false
                }
            }
        }
        
        let totalDuration = Date().timeIntervalSince(startTime)
        
        return PlanExecutionResult(
            taskResults: taskResults,
            observations: outputs,
            totalDuration: totalDuration,
            allSucceeded: allSucceeded
        )
    }
    
    /// Execute a single task
    private func executeTask(_ task: ParsedTask, outputs: [Int: String]) async -> TaskExecutionResult {
        let startTime = Date()
        
        // Resolve arguments
        let resolvedArgs = task.arguments.map { arg -> Any in
            arg.resolve(with: outputs) ?? ""
        }
        
        // Get tool
        guard let toolName = TinyAgentToolName(rawValue: task.toolName) else {
            return TaskExecutionResult(
                taskId: task.id,
                toolName: task.toolName,
                success: false,
                output: "",
                error: "Unknown tool: \(task.toolName)",
                duration: Date().timeIntervalSince(startTime)
            )
        }
        
        guard let tool = await ToolRegistry.shared.getTool(toolName) else {
            return TaskExecutionResult(
                taskId: task.id,
                toolName: task.toolName,
                success: false,
                output: "",
                error: "Tool not available: \(task.toolName)",
                duration: Date().timeIntervalSince(startTime)
            )
        }
        
        // Execute tool
        do {
            let output = try await tool.execute(arguments: resolvedArgs)
            return TaskExecutionResult(
                taskId: task.id,
                toolName: task.toolName,
                success: true,
                output: output,
                error: nil,
                duration: Date().timeIntervalSince(startTime)
            )
        } catch {
            return TaskExecutionResult(
                taskId: task.id,
                toolName: task.toolName,
                success: false,
                output: "",
                error: error.localizedDescription,
                duration: Date().timeIntervalSince(startTime)
            )
        }
    }
    
    /// Build a dependency graph from tasks
    private func buildDependencyGraph(tasks: [ParsedTask]) -> [Int: Set<Int>] {
        var graph: [Int: Set<Int>] = [:]
        
        for task in tasks {
            graph[task.id] = Set(task.dependencies)
        }
        
        return graph
    }
    
    /// Build execution levels (topological sort with parallelization)
    private func buildExecutionLevels(tasks: [ParsedTask], dependencyGraph: [Int: Set<Int>]) -> [[ParsedTask]] {
        var levels: [[ParsedTask]] = []
        var completed: Set<Int> = []
        var remaining = tasks
        
        while !remaining.isEmpty {
            // Find tasks that have all dependencies satisfied
            let ready = remaining.filter { task in
                task.dependencies.allSatisfy { completed.contains($0) }
            }
            
            if ready.isEmpty && !remaining.isEmpty {
                // Circular dependency or missing dependency - just execute remaining sequentially
                levels.append(remaining)
                break
            }
            
            levels.append(ready)
            completed.formUnion(ready.map { $0.id })
            remaining.removeAll { task in ready.contains { $0.id == task.id } }
        }
        
        return levels
    }
}
