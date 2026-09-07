import Foundation
import MCPContextEngineCore
import MCPContextEngineMCP
import MCPContextEngineFoundationModels

print("\n====================================================")
print("                MCP CONTEXT ENGINE DEMO             ")
print("====================================================")

// STEP 1: Discovery across MCP Servers
print("\n[STEP 1: DISCOVERY]")
let catalog = DemoScenario.createCatalog()
let serverGroups = Dictionary(grouping: catalog, by: \.serverId)

print("Connected MCP Servers:")
for (server, tools) in serverGroups.sorted(by: { $0.key < $1.key }) {
    print("  ✓ \(server.uppercased()) (\(tools.count) tools)")
}
print("Total Discovered Tools: \(catalog.count)")

// STEP 2: User Task Query
let task = "Find open Swift concurrency issues related to our project and tell me which ones are probably relevant."
print("\n[STEP 2: USER TASK]")
print("User Query: \"\(task)\"")

// STEP 3: Intelligent Tool Routing
print("\n[STEP 3: TOOL ROUTING]")
let router = ToolRouter()
let routingResult = router.route(tools: catalog, forTask: task, topK: 4)

print("Tool Router Evaluation (Top Selected / Total: \(routingResult.selectedTools.count)/\(catalog.count)):")
for (index, scored) in routingResult.selectedScores.enumerated() {
    print(String(format: "  %d. %-28@ [Score: %.2f] (name: %.2f, desc: %.2f, query: %.2f)",
                 index + 1, scored.tool.name, scored.score,
                 scored.breakdown.nameMatchScore,
                 scored.breakdown.descriptionMatchScore,
                 scored.breakdown.queryKeywordScore))
}
print(String(format: "Routing overhead: %.2f ms", routingResult.routingDurationMs))

// STEP 4: Context Budget Allocation
print("\n[STEP 4: CONTEXT BUDGET CALCULATION]")
let tokenProvider = MockTokenProvider()
let budgetManager = ContextBudgetManager(
    totalCapacity: 4096,
    reservedResponseTokens: 700,
    systemPromptTokens: 300,
    historyTokens: 700,
    tokenProvider: tokenProvider
)
budgetManager.setSelectedTools(routingResult.selectedTools)

let budget = budgetManager.currentBudget
print("Runtime Context Capacity: \(budget.totalCapacity) tokens")
print("  - Reserved for model response: \(budget.reservedResponseTokens) tokens")
print("  - System instructions:         \(budget.systemPromptTokens) tokens")
print("  - Conversation history:        \(budget.historyTokens) tokens")
print("  - Selected 4 tool schemas:     \(budget.toolSchemaTokens) tokens")
print("----------------------------------------------------")
print("Available Headroom for Result:   \(budget.availableForResultTokens) tokens")

// STEP 5: MCP Tool Execution
print("\n[STEP 5: MCP EXECUTION]")
print("Executing selected tool: '\(routingResult.selectedTools[0].name)'...")
let rawMCPResult = DemoScenario.makeSyntheticLargeGitHubResult()
let rawTokens = tokenProvider.countTokens(text: rawMCPResult)
print("Received raw MCP payload: \(rawMCPResult.count) characters (~\(rawTokens) tokens)")

let initialFit = budgetManager.evaluateResultFit(resultText: rawMCPResult)
print("Budget Fit Pre-check: \(initialFit.fits ? "FITS" : "OVERFLOW DETECTED (Deficit: \(initialFit.deficit) tokens)")")

// STEP 6: Deterministic Result Reduction
print("\n[STEP 6: RESULT REDUCTION]")
let reducer = ResultReducer(tokenProvider: tokenProvider)
let reductionResult = reducer.reduce(rawContent: rawMCPResult, availableBudgetTokens: budget.availableForResultTokens)

print("Compaction Summary:")
print("  - Raw input tokens:     \(reductionResult.originalTokens)")
print("  - Reduced tokens:       \(reductionResult.reducedTokens)")
print(String(format: "  - Reduction achieved:   %.1f%%", reductionResult.reductionRatio * 100))
print("  - Strategies applied:   \(reductionResult.appliedStrategies.joined(separator: ", "))")
print(String(format: "  - Reduction overhead:   %.2f ms", reductionResult.durationMs))

let finalFit = budgetManager.evaluateResultFit(resultText: reductionResult.reducedData)
print("Budget Fit Post-check: \(finalFit.fits ? "FITS WITHIN BUDGET" : "OVERFLOW")")

// STEP 7: Benchmark Comparison
print("\n[STEP 7: BENCHMARK COMPARISON]")
let baselineSchemaTokens = catalog.reduce(0) { $0 + $1.estimatedSchemaTokens() }
let baselineTotal = budget.systemPromptTokens + budget.historyTokens + baselineSchemaTokens + budget.reservedResponseTokens + rawTokens
let engineTotal = budget.systemPromptTokens + budget.historyTokens + budget.toolSchemaTokens + budget.reservedResponseTokens + reductionResult.reducedTokens

let metrics = ContextMetrics(
    scenarioName: "GitHub Issue Search (Concurrency)",
    toolsDiscovered: catalog.count,
    baselineToolsExposed: catalog.count,
    baselineSchemaTokens: baselineSchemaTokens,
    baselineResultTokens: rawTokens,
    baselineTotalContext: baselineTotal,
    baselineOverflow: baselineTotal > budget.totalCapacity,
    baselineTaskSuccess: false,
    engineToolsExposed: routingResult.selectedTools.count,
    engineSchemaTokens: budget.toolSchemaTokens,
    engineResultTokens: reductionResult.reducedTokens,
    engineTotalContext: engineTotal,
    engineOverflow: engineTotal > budget.totalCapacity,
    engineTaskSuccess: true,
    routingOverheadMs: routingResult.routingDurationMs,
    reductionOverheadMs: reductionResult.durationMs
)

print(metrics.formattedReport())
