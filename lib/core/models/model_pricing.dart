/// Pricing data for a single model.
///
/// Prices are in USD per 1,000 tokens (prompt/completion/cached-input).
class ModelPricing {
  final String modelGlob;
  final String? providerKey;
  final double inputPricePer1k;
  final double outputPricePer1k;
  final double cachedInputPricePer1k;

  const ModelPricing({
    required this.modelGlob,
    this.providerKey,
    required this.inputPricePer1k,
    required this.outputPricePer1k,
    required this.cachedInputPricePer1k,
  });
}

/// Calculator for model usage costs.
///
/// Maintains a static registry of known model pricing and provides
/// lookup + calculation utilities. Unknown models return null cost.
class CostCalculator {
  CostCalculator._();

  static const List<ModelPricing> _registry = [
    // --- OpenAI GPT-4o ---
    ModelPricing(
      modelGlob: 'gpt-4o',
      providerKey: 'OpenAI',
      inputPricePer1k: 0.0025,
      outputPricePer1k: 0.01,
      cachedInputPricePer1k: 0.00125,
    ),
    ModelPricing(
      modelGlob: 'gpt-4o-*',
      providerKey: 'OpenAI',
      inputPricePer1k: 0.0025,
      outputPricePer1k: 0.01,
      cachedInputPricePer1k: 0.00125,
    ),
    // --- OpenAI GPT-4o-mini ---
    ModelPricing(
      modelGlob: 'gpt-4o-mini',
      providerKey: 'OpenAI',
      inputPricePer1k: 0.00015,
      outputPricePer1k: 0.0006,
      cachedInputPricePer1k: 0.000075,
    ),
    ModelPricing(
      modelGlob: 'gpt-4o-mini-*',
      providerKey: 'OpenAI',
      inputPricePer1k: 0.00015,
      outputPricePer1k: 0.0006,
      cachedInputPricePer1k: 0.000075,
    ),
    // --- OpenAI o1 ---
    ModelPricing(
      modelGlob: 'o1',
      providerKey: 'OpenAI',
      inputPricePer1k: 0.015,
      outputPricePer1k: 0.06,
      cachedInputPricePer1k: 0.0075,
    ),
    ModelPricing(
      modelGlob: 'o1-*',
      providerKey: 'OpenAI',
      inputPricePer1k: 0.015,
      outputPricePer1k: 0.06,
      cachedInputPricePer1k: 0.0075,
    ),
    // --- OpenAI o3-mini ---
    ModelPricing(
      modelGlob: 'o3-mini',
      providerKey: 'OpenAI',
      inputPricePer1k: 0.0011,
      outputPricePer1k: 0.0044,
      cachedInputPricePer1k: 0.00055,
    ),
    ModelPricing(
      modelGlob: 'o3-mini-*',
      providerKey: 'OpenAI',
      inputPricePer1k: 0.0011,
      outputPricePer1k: 0.0044,
      cachedInputPricePer1k: 0.00055,
    ),
    // --- OpenAI GPT-4-turbo ---
    ModelPricing(
      modelGlob: 'gpt-4-turbo',
      providerKey: 'OpenAI',
      inputPricePer1k: 0.01,
      outputPricePer1k: 0.03,
      cachedInputPricePer1k: 0.01,
    ),
    // --- Anthropic Claude 3.5 Sonnet ---
    ModelPricing(
      modelGlob: 'claude-3.5-sonnet*',
      providerKey: 'Claude',
      inputPricePer1k: 0.003,
      outputPricePer1k: 0.015,
      cachedInputPricePer1k: 0.0015,
    ),
    // --- Anthropic Claude 3.5 Haiku ---
    ModelPricing(
      modelGlob: 'claude-3.5-haiku*',
      providerKey: 'Claude',
      inputPricePer1k: 0.0008,
      outputPricePer1k: 0.004,
      cachedInputPricePer1k: 0.0004,
    ),
    // --- Anthropic Claude 3 Opus ---
    ModelPricing(
      modelGlob: 'claude-3-opus*',
      providerKey: 'Claude',
      inputPricePer1k: 0.015,
      outputPricePer1k: 0.075,
      cachedInputPricePer1k: 0.0075,
    ),
    // --- Google Gemini 1.5 Pro ---
    ModelPricing(
      modelGlob: 'gemini-1.5-pro*',
      providerKey: 'Gemini',
      inputPricePer1k: 0.00125,
      outputPricePer1k: 0.005,
      cachedInputPricePer1k: 0.0003125,
    ),
    // --- Google Gemini 1.5 Flash ---
    ModelPricing(
      modelGlob: 'gemini-1.5-flash*',
      providerKey: 'Gemini',
      inputPricePer1k: 0.000075,
      outputPricePer1k: 0.0003,
      cachedInputPricePer1k: 0.00001875,
    ),
    // --- Google Gemini 2.0 Flash ---
    ModelPricing(
      modelGlob: 'gemini-2.0-flash*',
      providerKey: 'Gemini',
      inputPricePer1k: 0.0001,
      outputPricePer1k: 0.0004,
      cachedInputPricePer1k: 0.000025,
    ),
    // --- DeepSeek V3 ---
    ModelPricing(
      modelGlob: 'deepseek*',
      providerKey: 'DeepSeek',
      inputPricePer1k: 0.0005,
      outputPricePer1k: 0.00219,
      cachedInputPricePer1k: 0.0001,
    ),
    // --- DeepSeek R1 ---
    ModelPricing(
      modelGlob: 'deepseek-reasoner',
      providerKey: 'DeepSeek',
      inputPricePer1k: 0.00055,
      outputPricePer1k: 0.00219,
      cachedInputPricePer1k: 0.0001,
    ),
    // --- Grok 2 ---
    ModelPricing(
      modelGlob: 'grok-2*',
      providerKey: 'Grok',
      inputPricePer1k: 0.002,
      outputPricePer1k: 0.01,
      cachedInputPricePer1k: 0.002,
    ),
    // --- Qwen (Aliyun / DashScope) ---
    ModelPricing(
      modelGlob: 'qwen-max*',
      providerKey: 'Aliyun',
      inputPricePer1k: 0.0008,
      outputPricePer1k: 0.002,
      cachedInputPricePer1k: 0.0008,
    ),
    ModelPricing(
      modelGlob: 'qwen-plus*',
      providerKey: 'Aliyun',
      inputPricePer1k: 0.0004,
      outputPricePer1k: 0.0012,
      cachedInputPricePer1k: 0.0004,
    ),
    ModelPricing(
      modelGlob: 'qwen-turbo*',
      providerKey: 'Aliyun',
      inputPricePer1k: 0.00015,
      outputPricePer1k: 0.0006,
      cachedInputPricePer1k: 0.00015,
    ),
    // --- SiliconFlow hosted models (approximate) ---
    ModelPricing(
      modelGlob: 'Qwen/*',
      providerKey: 'SiliconFlow',
      inputPricePer1k: 0.0005,
      outputPricePer1k: 0.0015,
      cachedInputPricePer1k: 0.0005,
    ),
    ModelPricing(
      modelGlob: 'THUDM/*',
      providerKey: 'SiliconFlow',
      inputPricePer1k: 0.0003,
      outputPricePer1k: 0.0008,
      cachedInputPricePer1k: 0.0003,
    ),
    // --- Zhipu AI / GLM ---
    ModelPricing(
      modelGlob: 'glm-4*',
      providerKey: 'Zhipu AI',
      inputPricePer1k: 0.001,
      outputPricePer1k: 0.003,
      cachedInputPricePer1k: 0.001,
    ),
  ];

  /// Look up pricing for a given provider + model.
  ///
  /// Returns `null` if no matching pricing is found.
  static ModelPricing? lookup(String providerKey, String modelId) {
    final lowerModel = modelId.toLowerCase();
    final lowerProvider = providerKey.toLowerCase();

    // First try exact match
    for (final p in _registry) {
      if (p.providerKey != null &&
          p.providerKey!.toLowerCase() != lowerProvider) {
        continue;
      }
      if (_matchesGlob(lowerModel, p.modelGlob.toLowerCase())) {
        return p;
      }
    }

    // Fallback: try provider-agnostic match
    for (final p in _registry) {
      if (p.providerKey != null) continue;
      if (_matchesGlob(lowerModel, p.modelGlob.toLowerCase())) {
        return p;
      }
    }

    return null;
  }

  /// Calculate the total cost in USD for a request.
  ///
  /// Returns `null` if the model is unknown (no pricing data).
  static double? calculateCost({
    required String providerKey,
    required String modelId,
    required int promptTokens,
    required int completionTokens,
    int cachedTokens = 0,
  }) {
    final pricing = lookup(providerKey, modelId);
    if (pricing == null) return null;

    final promptCost =
        (promptTokens / 1000.0) * pricing.inputPricePer1k;
    final completionCost =
        (completionTokens / 1000.0) * pricing.outputPricePer1k;

    // If we have cached tokens, charge the reduced rate for that portion
    // and the full rate for the remainder.
    final effectiveCached = (cachedTokens > 0)
        ? cachedTokens.clamp(0, promptTokens)
        : 0;
    final effectivePrompt = promptTokens - effectiveCached;

    final totalPromptCost = (effectivePrompt / 1000.0) * pricing.inputPricePer1k +
        (effectiveCached / 1000.0) * pricing.cachedInputPricePer1k;
    final totalCost = totalPromptCost + completionCost;

    return totalCost;
  }

  /// Format a cost value as a USD string.
  static String formatCost(double cost) {
    if (cost < 0.0001) return '\$${(cost * 1000000).toStringAsFixed(0)}μ';
    if (cost < 0.01) return '\$${cost.toStringAsFixed(4)}';
    if (cost < 1) return '\$${cost.toStringAsFixed(3)}';
    return '\$${cost.toStringAsFixed(2)}';
  }

  /// Format a cost value for compact display (short).
  static String formatCostCompact(double cost) {
    if (cost < 0.0001) return '\$${(cost * 1000000).toStringAsFixed(0)}μ';
    if (cost < 0.001) return '\$${cost.toStringAsFixed(5)}';
    if (cost < 0.01) return '\$${cost.toStringAsFixed(4)}';
    if (cost < 1) return '\$${cost.toStringAsFixed(3)}';
    return '\$${cost.toStringAsFixed(2)}';
  }

  /// Check if a model name matches a glob pattern.
  ///
  /// Supports:
  /// - `*` suffix (e.g., `gpt-4o-*`)
  /// - Exact match
  /// - `prefix*` prefix match
  /// - `*prefix` suffix match
  /// - `*substring*` contains match
  /// - `Qwen/*` prefixed provider-style match
  static bool _matchesGlob(String model, String glob) {
    if (glob == model) return true;

    if (glob.endsWith('*')) {
      final prefix = glob.substring(0, glob.length - 1);
      if (prefix.isEmpty) return true; // bare `*` matches all
      if (glob.startsWith('*')) {
        // *substring*
        final substr = glob.substring(1, glob.length - 1);
        return substr.isEmpty || model.contains(substr);
      }
      // prefix*
      return model.startsWith(prefix);
    }

    if (glob.startsWith('*')) {
      final suffix = glob.substring(1);
      return model.endsWith(suffix);
    }

    return false;
  }
}
