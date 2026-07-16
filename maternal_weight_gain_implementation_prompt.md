# Maternal Weight Gain Monitoring — Implementation Prompt

> [!IMPORTANT]
> This prompt is designed to be given to an AI coding assistant to implement the full Maternal Weight Gain Monitoring Module inside the InaAgapay Flutter + Supabase project.

---

## 🎯 OBJECTIVE

Implement an **adaptive Maternal Weight Gain Monitoring Module** in the InaAgapay system. The module evaluates pregnancy weight progression using two modes:

- **Mode A (FULL):** When `pre_pregnancy_weight` exists → compare actual vs expected gain using IOM 2009 guidelines.
- **Mode B (TREND):** When baseline is missing → analyze rate/consistency of weight change across checkups.

This also **changes how BMI classification works** for pregnant mothers — BMI should be computed from pre-pregnancy weight when available, not current weight.

---

## 📁 CODEBASE CONTEXT

| Aspect | Details |
|---|---|
| **Framework** | Flutter (Dart) |
| **Backend** | Supabase (PostgreSQL) |
| **AI Service** | `lib/services/groq_service.dart` — Groq API via `generateTextInsight()` |
| **Risk Engine** | `lib/services/risk_engine.dart` (simple low/high flag) |
| **Smart Risk Engine** | `lib/services/smart_risk_engine.dart` (history + watch list builder) |
| **Risk Models** | `lib/models/smart_risk_models.dart` |
| **Mother Profile Service** | `lib/services/mother_profile_service.dart` |
| **Supabase Service** | `lib/services/supabase_service.dart` |
| **BMI Helpers** | `lib/widgets/profile_helpers.dart` — `getBMIStatus()`, `getBMIStatusColor()` |
| **Prenatal Checkup** | `lib/screens/midwife/add_prenatal_checkup_screen.dart` |
| **Mother Profile** | `lib/screens/mother/mother_profile_page.dart` |
| **Mother Dashboard** | `lib/screens/mother/mother_dashboard.dart` |
| **Add Mother** | `lib/screens/midwife/midwife_add_mother_screen.dart` |
| **DB Schema** | `database/supabase_setup.sql` |

### Key Existing Data Points

- **`mothers` table:** has `height` (cm), `weight` (kg — registration weight). Does **NOT** yet have `pre_pregnancy_weight`.
- **`prenatal_checkups` table:** has `checkup_weight`, `age_of_gestation`, `checkup_datetime`.
- **`pregnancies` table:** has `pregnancy_id`, `mother_id`, `last_menstrual_period`, `status`.
- **`ai_responses` table:** polymorphic storage for AI outputs (`reference_table`, `reference_id`, `response_type`, `response`).
- **`pregnancy_risk_assessments` + `pregnancy_risk_factors`:** store risk evaluations per checkup.

### Current BMI Logic (to be changed)

In `profile_helpers.dart`:
```dart
String getBMIStatus(double bmi) {
  if (bmi < 18.5) return 'Underweight';
  if (bmi < 25) return 'Normal';
  if (bmi < 30) return 'Overweight';
  return 'Obese';
}
```
Currently, BMI is calculated from **current checkup weight / height²** in `mother_profile_page.dart`. This must change to use **pre-pregnancy weight** when available.

---

## 🔧 IMPLEMENTATION STEPS

### STEP 1: Database Schema Changes

Add to `mothers` table:
```sql
ALTER TABLE mothers ADD COLUMN pre_pregnancy_weight DECIMAL(5, 2);
```

Add new table for weight gain evaluations:
```sql
CREATE TABLE weight_gain_evaluations (
    evaluation_id BIGSERIAL PRIMARY KEY,
    pregnancy_id BIGINT NOT NULL REFERENCES pregnancies(pregnancy_id) ON DELETE CASCADE,
    prenatal_checkup_id BIGINT REFERENCES prenatal_checkups(prenatal_checkup_id) ON DELETE CASCADE,
    mode VARCHAR(10) NOT NULL CHECK (mode IN ('FULL', 'TREND')),
    bmi_category VARCHAR(20), -- Underweight, Normal, Overweight, Obese
    baseline_weight DECIMAL(5,2),
    baseline_week DECIMAL(4,1),
    current_weight DECIMAL(5,2),
    current_week DECIMAL(4,1),
    expected_gain DECIMAL(5,2),
    actual_gain DECIMAL(5,2),
    weekly_gain DECIMAL(5,3),
    status VARCHAR(10) NOT NULL CHECK (status IN ('NORMAL', 'LOW', 'HIGH')),
    confidence VARCHAR(10) NOT NULL CHECK (confidence IN ('HIGH', 'MEDIUM', 'LOW')),
    message TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

ALTER TABLE weight_gain_evaluations DISABLE ROW LEVEL SECURITY;
CREATE INDEX idx_wge_pregnancy ON weight_gain_evaluations(pregnancy_id);
CREATE INDEX idx_wge_checkup ON weight_gain_evaluations(prenatal_checkup_id);
```

### STEP 2: Create the Weight Gain Engine Service

Create `lib/services/weight_gain_engine.dart`:

```dart
/// Maternal Weight Gain Monitoring Engine
/// Implements adaptive evaluation: FULL (BMI-based) or TREND (rate-based)
class WeightGainEngine {
  // IOM 2009 Guidelines
  static const Map<String, Map<String, double>> iomGuidelines = {
    'Underweight': {
      'total_min': 12.5, 'total_max': 18.0,
      'first_trimester': 2.0, 'weekly_rate': 0.51,
      'weekly_min': 0.44, 'weekly_max': 0.58,
    },
    'Normal': {
      'total_min': 11.5, 'total_max': 16.0,
      'first_trimester': 1.6, 'weekly_rate': 0.42,
      'weekly_min': 0.35, 'weekly_max': 0.50,
    },
    'Overweight': {
      'total_min': 7.0, 'total_max': 11.5,
      'first_trimester': 0.9, 'weekly_rate': 0.28,
      'weekly_min': 0.23, 'weekly_max': 0.33,
    },
    'Obese': {
      'total_min': 5.0, 'total_max': 9.0,
      'first_trimester': 0.7, 'weekly_rate': 0.22,
      'weekly_min': 0.17, 'weekly_max': 0.27,
    },
  };

  /// Main evaluation entry point
  static WeightGainResult evaluate({
    required double currentWeight,
    required double aogWeeks,
    required List<Map<String, dynamic>> allCheckups, // sorted by date ASC
    double? prePregnancyWeight,
    double? heightCm,
    String? midwifeBmiCategory,
  }) {
    // Determine BMI category using priority: pre-pregnancy BMI > current estimated > midwife input > default
    final bmiCategory = _determineBmiCategory(
      prePregnancyWeight: prePregnancyWeight,
      currentWeight: currentWeight,
      heightCm: heightCm,
      midwifeBmiCategory: midwifeBmiCategory,
    );

    if (prePregnancyWeight != null) {
      return _evaluateFull(
        currentWeight: currentWeight,
        prePregnancyWeight: prePregnancyWeight,
        aogWeeks: aogWeeks,
        bmiCategory: bmiCategory,
      );
    }

    return _evaluateTrend(
      currentWeight: currentWeight,
      aogWeeks: aogWeeks,
      allCheckups: allCheckups,
      bmiCategory: bmiCategory,
      heightCm: heightCm,
    );
  }

  // ... implement _evaluateFull, _evaluateTrend, _determineBmiCategory
  // ... handle all 8 scenarios from the spec
}

class WeightGainResult {
  final String mode;        // 'FULL' or 'TREND'
  final String bmiCategory;
  final double? expectedGain;
  final double? actualGain;
  final double? weeklyGain;
  final String status;      // 'NORMAL', 'LOW', 'HIGH'
  final String confidence;  // 'HIGH', 'MEDIUM', 'LOW'
  final String message;
  final List<String> flags; // alerts like 'weight_loss', 'plateau', 'spike'

  WeightGainResult({...});

  Map<String, dynamic> toJson() => { /* serialize for DB + AI */ };
}
```

#### Full Evaluation Logic (Mode A):
```
expected_gain = first_trimester_gain + max(0, (aogWeeks - 13)) * weekly_rate
actual_gain = current_weight - pre_pregnancy_weight
status:
  if actual_gain < (expected_lower_bound) → LOW
  if actual_gain > (expected_upper_bound) → HIGH
  else → NORMAL
confidence: HIGH
```

#### Trend Evaluation Logic (Mode B):
```
Requires ≥ 2 checkups. If only 1 → status: INSUFFICIENT, confidence: LOW
weekly_gain = (current_weight - previous_weight) / (weeks_between)
Compare weekly_gain against IOM weekly range for bmiCategory:
  if weekly_gain < weekly_min → LOW
  if weekly_gain > weekly_max → HIGH  
  else → NORMAL
confidence: MEDIUM (or LOW if no BMI data)
```

#### Scenario Flags:
- **Weight loss** (`current < previous`): flag `weight_loss` → HIGH RISK ALERT
- **Plateau** (`weekly_gain ≈ 0`): flag `plateau`
- **Spike** (`weekly_gain >> 2× upper_bound`): flag `abnormal_spike`
- **Late registration** (AoG > 28 weeks, no pre-pregnancy): DO NOT estimate total gain
- **Missing height**: use default "Normal" weekly range

### STEP 3: Update BMI Classification for Pregnant Mothers

In `lib/widgets/profile_helpers.dart`, add:

```dart
/// For pregnant mothers: BMI should use pre-pregnancy weight, not current weight.
/// Falls back to current weight if pre-pregnancy unavailable.
double? computePregnancyBMI({
  double? prePregnancyWeight,
  double? currentWeight,
  double? heightCm,
}) {
  final weight = prePregnancyWeight ?? currentWeight;
  if (weight == null || heightCm == null || heightCm <= 0) return null;
  final heightM = heightCm / 100;
  return weight / (heightM * heightM);
}
```

Update `mother_profile_page.dart` `_loadLatestGrowthData()`:
- Fetch `pre_pregnancy_weight` from `mothers` table
- Calculate BMI using `prePregnancyWeight` when available instead of `checkup_weight`
- Display indicator showing which weight was used for BMI

### STEP 4: Add Pre-Pregnancy Weight Input

In `lib/screens/midwife/midwife_add_mother_screen.dart`:
- Add an **optional** "Pre-Pregnancy Weight" field (30-200 kg range) in the physical info step
- Save to `mothers.pre_pregnancy_weight` column
- Show tooltip: "Weight before pregnancy, if known"

Update `SupabaseService` mother creation methods to include `pre_pregnancy_weight`.

### STEP 5: Integrate into Prenatal Checkup Flow

In `lib/screens/midwife/add_prenatal_checkup_screen.dart`:

After saving the checkup record in `_submit()`, call the weight gain engine:

```dart
// After checkup insert succeeds:
final motherData = await client.from('mothers')
    .select('height, pre_pregnancy_weight')
    .eq('mother_id', widget.motherId)
    .single();

final allCheckups = await client.from('prenatal_checkups')
    .select('checkup_weight, age_of_gestation, checkup_datetime')
    .eq('pregnancy_id', widget.pregnancyId)
    .order('checkup_datetime', ascending: true);

final result = WeightGainEngine.evaluate(
  currentWeight: weight,
  aogWeeks: _aogWeeks!,
  allCheckups: List<Map<String, dynamic>>.from(allCheckups),
  prePregnancyWeight: _toDouble(motherData['pre_pregnancy_weight']),
  heightCm: _toDouble(motherData['height']),
);

// Store evaluation
await client.from('weight_gain_evaluations').insert({
  'pregnancy_id': widget.pregnancyId,
  'prenatal_checkup_id': prenatalCheckupId,
  'mode': result.mode,
  'bmi_category': result.bmiCategory,
  'baseline_weight': result.mode == 'FULL' ? motherData['pre_pregnancy_weight'] : null,
  'baseline_week': result.mode == 'FULL' ? 0 : null,
  'current_weight': weight,
  'current_week': _aogWeeks,
  'expected_gain': result.expectedGain,
  'actual_gain': result.actualGain,
  'weekly_gain': result.weeklyGain,
  'status': result.status,
  'confidence': result.confidence,
  'message': result.message,
});
```

Also store in `ai_responses` table for AI explanation:

```dart
await client.from('ai_responses').insert({
  'response_type': 'weight_gain_analysis',
  'reference_table': 'prenatal_checkups',
  'reference_id': prenatalCheckupId,
  'ai_model': 'Rule Engine',
  'response': jsonEncode(result.toJson()),
  'response_category': 'analysis',
  'status': 'generated',
  'generated_by_ai': false,
});
```

### STEP 6: Feed Weight Gain Results into Risk Engine

In `lib/services/smart_risk_engine.dart` `buildWatchList()`:

Add weight trend analysis:
```dart
// Weight gain monitoring
final weightEvals = /* fetch weight_gain_evaluations for this pregnancy */;
if (weightEvals.isNotEmpty) {
  final latest = weightEvals.last;
  if (latest['status'] == 'HIGH') {
    items.add('Weight gain above recommended range (${latest['mode']} analysis)');
  } else if (latest['status'] == 'LOW') {
    items.add('Weight gain below recommended range — monitor nutrition');
  }
  // Check for weight loss flag
  if (latest['message']?.contains('weight_loss') ?? false) {
    items.add('⚠️ Weight loss detected — high risk alert');
  }
}
```

In `lib/services/risk_engine.dart` `evaluate()`:
```dart
// Add weight gain as a risk factor
// If weight gain status is HIGH or LOW with flags, add to findings
```

### STEP 7: AI Integration (Explanation Layer)

When weight gain result has status != NORMAL, use `GroqService.generateTextInsight()` to explain:

```dart
final prompt = '''
You are a maternal health assistant. Based on the following weight gain analysis, 
provide a brief, supportive explanation for a midwife.

Analysis Mode: ${result.mode}
BMI Category: ${result.bmiCategory}
Current Week: $aogWeeks
Status: ${result.status}
${result.mode == 'FULL' ? 'Expected Gain: ${result.expectedGain} kg' : ''}
${result.mode == 'FULL' ? 'Actual Gain: ${result.actualGain} kg' : ''}
Weekly Gain Rate: ${result.weeklyGain} kg/week
Flags: ${result.flags.join(', ')}

Rules:
- Do NOT diagnose. Explain the finding.
- Mention IOM 2009 guidelines.
- Keep it under 100 words.
- Suggest what the midwife should monitor or discuss.
''';
```

> [!IMPORTANT]
> AI should **explain** results, NOT compute them. The rule engine computes; AI interprets.

### STEP 8: UI Integration

#### A. Mother Profile Page (`mother_profile_page.dart`)

In the Overview tab growth card:
- Show BMI computed from **pre-pregnancy weight** (label: "Pre-Pregnancy BMI")
- If no pre-pregnancy weight, show current BMI with label: "Estimated BMI (current weight)"
- Add weight gain status badge (NORMAL/LOW/HIGH) with confidence indicator

#### B. Prenatal Checkup Summary (Step 5/6 in `add_prenatal_checkup_screen.dart`)

Show weight gain evaluation inline:
- Mode label: "Full Analysis" or "Trend-Based Analysis" or "Insufficient Data"
- Expected vs Actual gain (Mode A) or Weekly rate (Mode B)
- Status badge with color coding
- Confidence level indicator

#### C. Weight Trend Chart

In the mother profile's pregnancy tab, add a weight progression chart:
- X-axis: Gestational weeks
- Y-axis: Weight (kg)
- Lines: Actual weight points + Expected range band (if Mode A)
- Use `fl_chart` package (already in project for child growth charts)

#### D. Status Badge Colors
```dart
// NORMAL → green (AppColors.success)
// LOW → orange (AppColors.warning) 
// HIGH → red (AppColors.error)
// Confidence: HIGH → solid, MEDIUM → semi-transparent, LOW → outlined
```

### STEP 9: Confidence Level System

| Level | Conditions |
|---|---|
| **HIGH** | Pre-pregnancy weight available + height available + ≥2 checkups |
| **MEDIUM** | Trend-based mode + height available + ≥2 checkups |
| **LOW** | Missing height OR only 1 checkup OR no BMI category determinable |

### STEP 10: Update Mother Profile Service

In `lib/services/mother_profile_service.dart` `fetchMotherProfile()`:
- Include `pre_pregnancy_weight` in the mothers query (it's already `SELECT *`)
- Fetch `weight_gain_evaluations` for the current pregnancy
- Include latest evaluation in the profile response

---

## ⚠️ RISK MANAGEMENT RULES

1. **No guessing:** Never fabricate pre-pregnancy weight. If missing, use TREND mode.
2. **No forced BMI normalization:** Don't default to "Normal" BMI if we truly have no data — use widest safe range instead.
3. **Transparent fallback:** Always show which mode was used and why.
4. **Safe for incomplete data:** Single checkup → return "Insufficient data" with LOW confidence.
5. **Weight loss = HIGH RISK:** Always flag. Never normalize.
6. **Late registration (>28 weeks, no baseline):** Use TREND only. Do NOT estimate total expected gain.

---

## 📋 FILES TO CREATE/MODIFY

### New Files
| File | Purpose |
|---|---|
| `lib/services/weight_gain_engine.dart` | Core evaluation engine |
| `lib/models/weight_gain_models.dart` | `WeightGainResult`, `WeightGainMode` enum, etc. |

### Modified Files
| File | Changes |
|---|---|
| `database/supabase_setup.sql` | Add `pre_pregnancy_weight` column, `weight_gain_evaluations` table |
| `lib/widgets/profile_helpers.dart` | Add `computePregnancyBMI()`, update `getBMIStatus()` docs |
| `lib/screens/midwife/midwife_add_mother_screen.dart` | Add pre-pregnancy weight field |
| `lib/screens/midwife/add_prenatal_checkup_screen.dart` | Call weight gain engine on submit, show results in summary |
| `lib/services/supabase_service.dart` | Update mother creation to include pre-pregnancy weight |
| `lib/services/smart_risk_engine.dart` | Add weight gain to watch list |
| `lib/services/risk_engine.dart` | Add weight gain findings |
| `lib/services/mother_profile_service.dart` | Fetch weight gain evaluations |
| `lib/screens/mother/mother_profile_page.dart` | Update BMI display, add weight gain card |
| `lib/screens/mother/mother_dashboard.dart` | Show weight gain status |

---

## 🧪 TEST SCENARIOS

| # | Scenario | Expected Behavior |
|---|---|---|
| 1 | Complete data (pre-preg weight + height + 3 checkups) | FULL mode, HIGH confidence |
| 2 | No pre-pregnancy weight, 3 checkups | TREND mode, MEDIUM confidence |
| 3 | Only 1 checkup, no pre-pregnancy weight | "Insufficient data", LOW confidence |
| 4 | Late registration (30 weeks), no baseline | TREND only, DO NOT estimate total gain |
| 5 | Sudden spike (3kg in 1 week) | Flag: abnormal_spike, status: HIGH |
| 6 | No weight change between 2 checkups | Flag: plateau |
| 7 | Weight loss between checkups | Flag: weight_loss, HIGH RISK ALERT |
| 8 | Missing height | Use default "Normal" weekly range, note reduced confidence |

---

## 🔑 CRITICAL REMINDERS

1. **BMI for pregnant mothers must change** — use pre-pregnancy weight, not current checkup weight.
2. **The weight gain engine is rule-based** — it does NOT use AI to compute. AI only explains results.
3. **Store results in both** `weight_gain_evaluations` (structured) AND `ai_responses` (for AI explanation layer).
4. **Run evaluation on every new checkup save** and on record update.
5. **Follow existing code patterns** — use `SupabaseService.client`, existing model patterns, `AppColors` theme, `_sectionCard` UI pattern in checkup screen.
