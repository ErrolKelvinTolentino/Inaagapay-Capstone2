// lib/models/ai_analysis.dart

class AIAnalysis {
  final String summary;
  final String trend;
  final List<String> recommendations;
  final Map<String, dynamic> insights;
  final double confidenceScore;

  AIAnalysis({
    required this.summary,
    required this.trend,
    required this.recommendations,
    required this.insights,
    required this.confidenceScore,
  });

  factory AIAnalysis.fromJson(Map<String, dynamic> json) {
    return AIAnalysis(
      summary: json['summary'] ?? 'No summary available',
      trend: json['trend'] ?? 'Unknown',
      recommendations: List<String>.from(json['recommendations'] ?? []),
      insights: json['insights'] ?? {},
      confidenceScore: (json['confidenceScore'] ?? 0.0).toDouble(),
    );
  }
}