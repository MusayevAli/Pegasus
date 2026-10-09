export interface MetricRecord {
 id: string; label: string; value: number; unit: 'count'|'ms'|'minor'|'ratio'; sampleSize: number; denominator: number;
 windowStart: string; windowEnd: string; dataSource: string; cohort: string;
}
export interface AnalyticsResponse {
  meta: { provenance: string; days: number; generatedAt: string; windowStart: string; windowEnd: string; label: string; eventCount: number; minimumCohort: number; abandonmentMinutes: number; activeTimeThresholdSeconds: number; timingDefinition: string; abandonmentDefinition: string; funnelDefinition: string };
  overview: { startedFlows: number; completedBookings: number; demoBookings: number; realTickets: number; completionRate: number; medianCompletionMs: number | null; medianActiveCompletionMs: number | null; p90ActiveCompletionMs: number | null; errors: number; extrasSelectedMinor: number; realisedRevenueMinor: number; activeFlows: number; abandonedFlows: number; resumedFlows: number; currency: "EUR" };
  funnel: Array<{ step: string; label: string; reached: number; denominator: number; dropoffs: number; active: number; abandoned: number; completed: number }>;
  friction: Array<{ screen: string; visits: number; journeys: number; revisits: number; foregroundMedianMs: number; foregroundP90Ms: number; activeMedianMs: number; activeP90Ms: number; loadingMedianMs: number; loadingTotalMs: number; backtracks: number; errors: number; exits: number; completedMedianMs: number | null; incompleteMedianMs: number | null }>;
  components: Array<{ componentId: string; screen: string; interactions: number; errors: number }>;
  recommendations: Array<{ type: string; journeys: number; generated: number; impressions: number; expanded: number; accepts: number; dismissals: number; applications: number; reversals: number; retained: number; retainedAtCheckout: number; acceptanceRate: number; pairDefinition: string }>;
  gaps: Array<{ code: string; label: string; count: number; flowCount: number; exampleRoute: string | null }>;
  sessions: Array<{ id: string; flowId: string; provenance: string; startedAt: string; lastSeenAt: string; status: "completed" | "active" | "abandoned"; resumed: boolean; durationMs: number; activeMs: number; loadingMs: number; eventCount: number; errorCount: number; lastScreen: string }>;
  metrics: MetricRecord[];
  insights: Array<{ id: string; title: string; issue: string; metric: string; sampleSize: number; cohort: string; hypothesis: string; proposal: string; experiment: string; successMetric: string; evidence: Array<{ metricKey: string; label: string; value: number }>; source: "rules" }>;
}
export interface SessionResponse {
  id: string;
  label: string;
  events: Array<{ id: string; name: string; sequence: number; flowId: string; screen: string; componentId: string; clientTimestamp: string; serverReceivedAt: string; properties: Record<string, string | number | boolean> }>;
}
export interface StructuredAnalyticsInsight {
 id: string; observation: string; evidenceMetricIds: string[]; hypothesis: string; proposedChange: string; suggestedExperiment: string;
 sampleAdequacy: 'adequate'|'insufficient'; evidenceNumbers: Array<{metricId: string; value: number; sampleSize: number; denominator: number}>;
}
