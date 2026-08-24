import Foundation

nonisolated public enum BuiltInBenchmark {
  /// Both candidates intentionally share one deterministic provider configuration so that
  /// the benchmark observes instruction differences without changing sampling behavior.
  private static let deterministicGenerationOptions = PromptGenerationOptions(
    temperature: 0.2, topP: 0.9, maxTokens: 512, seed: 42, stream: true)

  private static func check(
    _ id: String, _ kind: EvalCheckKind, _ value: String = "", _ label: String = "",
    _ expected: EvalExpectedValue? = nil
  ) -> EvalCheck { EvalCheck(id: id, kind: kind, value: value, label: label, expected: expected) }
  public static let suite = EvalSuite(
    id: "support-ticket-json-v1", version: 1, name: "Support-ticket JSON extraction",
    description:
      "A transparent mechanical benchmark: candidates extract stable fields from the same support tickets. It does not score subjective quality.",
    cases: [
      EvalCase(
        id: "ticket-login", name: "Login failure",
        input:
          "Ticket T-100: Maya cannot sign in after a password reset. Priority high. Assign to identity.",
        checks: [
          check("login-json", .validJSON), check("login-type", .requiredJSONPath, "ticketType"),
          check("login-priority", .equalsJSONPath, "priority", "", .string("high")),
          check("login-owner", .equalsJSONPath, "owner", "", .string("identity")),
        ]),
      EvalCase(
        id: "ticket-billing", name: "Billing question",
        input:
          "Ticket T-101: The customer sees a duplicate charge on the March invoice. Priority medium. Assign to billing.",
        checks: [
          check("billing-json", .validJSON), check("billing-type", .requiredJSONPath, "ticketType"),
          check("billing-owner", .equalsJSONPath, "owner", "", .string("billing")),
          check("billing-priority", .equalsJSONPath, "priority", "", .string("medium")),
        ]),
      EvalCase(
        id: "ticket-outage", name: "Service outage",
        input:
          "Ticket T-102: API requests return 503 for every workspace since 09:10 UTC. Priority urgent. Assign to platform.",
        checks: [
          check("outage-json", .validJSON),
          check("outage-priority", .equalsJSONPath, "priority", "", .string("urgent")),
          check("outage-owner", .equalsJSONPath, "owner", "", .string("platform")),
          check("outage-summary", .requiredJSONPath, "summary"),
        ]),
      EvalCase(
        id: "ticket-export", name: "Data export",
        input:
          "Ticket T-103: Please export the team's records as CSV before Friday. Priority low. Assign to data.",
        checks: [
          check("export-json", .validJSON), check("export-type", .requiredJSONPath, "ticketType"),
          check("export-format", .contains, "CSV"),
          check("export-owner", .equalsJSONPath, "owner", "", .string("data")),
        ]),
      EvalCase(
        id: "ticket-permission", name: "Permission request",
        input:
          "Ticket T-104: Jordan needs read-only access to the analytics project. Priority medium. Assign to access.",
        checks: [
          check("permission-json", .validJSON),
          check("permission-owner", .equalsJSONPath, "owner", "", .string("access")),
          check("permission-priority", .equalsJSONPath, "priority", "", .string("medium")),
        ]),
      EvalCase(
        id: "ticket-mobile", name: "Mobile bug",
        input:
          "Ticket T-105: The iOS app crashes when opening a saved search. Priority high. Assign to mobile.",
        checks: [
          check("mobile-json", .validJSON), check("mobile-type", .requiredJSONPath, "ticketType"),
          check("mobile-summary", .requiredJSONPath, "summary"),
          check("mobile-priority", .equalsJSONPath, "priority", "", .string("high")),
        ]),
      EvalCase(
        id: "ticket-privacy", name: "Privacy request",
        input:
          "Ticket T-106: Remove the former employee's personal data under the deletion policy. Priority urgent. Assign to privacy.",
        checks: [
          check("privacy-json", .validJSON),
          check("privacy-priority", .equalsJSONPath, "priority", "", .string("urgent")),
          check("privacy-owner", .equalsJSONPath, "owner", "", .string("privacy")),
        ]),
      EvalCase(
        id: "ticket-feedback", name: "Product feedback",
        input:
          "Ticket T-107: Customers want keyboard shortcuts for switching projects. Priority low. Assign to product.",
        checks: [
          check("feedback-json", .validJSON),
          check("feedback-type", .requiredJSONPath, "ticketType"),
          check("feedback-summary", .requiredJSONPath, "summary"),
          check("feedback-priority", .equalsJSONPath, "priority", "", .string("low")),
        ]),
    ])
  public static func originalCandidate(model: String = "phi4-mini:latest")
    -> EvalCandidateConfiguration
  {
    EvalCandidateConfiguration(
      id: "original-v1", version: 1, label: "Original extraction", model: model,
      instruction:
        "Extract the support ticket into JSON. Preserve the ticket facts and return one JSON object.",
      generationOptions: deterministicGenerationOptions, format: .json)
  }
  public static func refinedCandidate(model: String = "phi4-mini:latest")
    -> EvalCandidateConfiguration
  {
    EvalCandidateConfiguration(
      id: "refined-v1", version: 1, label: "Refined extraction", model: model,
      instruction:
        "Extract the support ticket into exactly one JSON object with keys ticketType, summary, priority, and owner. Preserve facts; use concise strings and no commentary.",
      generationOptions: deterministicGenerationOptions, format: .json)
  }
}
