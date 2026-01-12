/**
 * Gemini AI Service for Health Data Analysis
 */

const GEMINI_MODEL = 'gemini-2.0-flash';
const GEMINI_API_URL = 'https://generativelanguage.googleapis.com/v1beta/models';

export type HealthSummary = {
  date: string;
  steps: number;
  calories: number;
  distance: number;
  active_minutes: number;
  resting_heart_rate: number | null;
  sleep_duration_minutes: number;
  sleep_efficiency: number | null;
  weight: number | null;
  vo2max: string | null;
  spo2_avg: number | null;
  // Additional detailed data
  sleep_stages?: {
    deep: number;
    light: number;
    rem: number;
    wake: number;
  };
  heart_rate_zones?: {
    fat_burn: number;
    cardio: number;
    peak: number;
  };
};

export type HealthInsights = {
  summary: string;
  highlights: string[];
  improvements: string[];
  actionable_tips: string[];
};

export type Env = {
  GEMINI_API_KEY?: string;
};

const SYSTEM_PROMPT = `あなたは健康アドバイザーです。以下のFitbit健康データを分析し、具体的な行動改善アドバイスを日本語で提供してください。

分析対象:
1. 活動量（歩数、アクティブ時間、消費カロリー）
2. 睡眠（時間、効率、ステージ）
3. 心拍数（安静時HR、ゾーン別時間）
4. 体重/BMI
5. VO2max（心肺機能スコア）- 範囲または数値で提供
6. SpO2（血中酸素濃度）- 睡眠中の平均値

重要な注意事項:
- データがない項目（null）は「データなし」として扱い、無理に評価しないこと
- 具体的で実行可能なアドバイスを提供すること
- ポジティブな点を必ず含めること
- 各配列は最大3個までにすること

出力はJSON形式で以下のスキーマに従ってください:
{
  "summary": "全体評価（1-2文）",
  "highlights": ["良かった点1", "良かった点2", ...],
  "improvements": ["改善すべき点1", "改善すべき点2", ...],
  "actionable_tips": ["今日から実践できるアドバイス1", ...]
}`;

/**
 * Analyze health data using Gemini API
 */
export async function analyzeHealthData(
  env: Env,
  healthData: HealthSummary
): Promise<HealthInsights | null> {
  const apiKey = env.GEMINI_API_KEY;

  if (!apiKey) {
    console.error('GEMINI_API_KEY not configured');
    return null;
  }

  const dataPayload = formatHealthDataForPrompt(healthData);
  const prompt = `${SYSTEM_PROMPT}\n\n---\n\n健康データ:\n${dataPayload}`;

  try {
    const response = await fetch(
      `${GEMINI_API_URL}/${GEMINI_MODEL}:generateContent?key=${apiKey}`,
      {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          contents: [
            {
              parts: [{ text: prompt }],
            },
          ],
          generationConfig: {
            responseMimeType: 'application/json',
            temperature: 0.7,
            maxOutputTokens: 2048,
          },
        }),
      }
    );

    if (!response.ok) {
      const errorText = await response.text();
      console.error('Gemini API error:', response.status, errorText);
      return null;
    }

    const result = await response.json() as {
      candidates?: Array<{
        content?: {
          parts?: Array<{ text?: string }>;
        };
      }>;
    };

    const text = result.candidates?.[0]?.content?.parts?.[0]?.text;
    if (!text) {
      console.error('No response text from Gemini');
      return null;
    }

    const insights = JSON.parse(text) as HealthInsights;

    // Ensure arrays exist and are properly typed
    return {
      summary: insights.summary || '',
      highlights: Array.isArray(insights.highlights) ? insights.highlights : [],
      improvements: Array.isArray(insights.improvements) ? insights.improvements : [],
      actionable_tips: Array.isArray(insights.actionable_tips) ? insights.actionable_tips : [],
    };
  } catch (error) {
    console.error('Gemini analysis error:', error);
    return null;
  }
}

/**
 * Format health data into a readable prompt
 */
function formatHealthDataForPrompt(data: HealthSummary): string {
  const lines: string[] = [
    `日付: ${data.date}`,
    '',
    '## 活動量',
    `- 歩数: ${data.steps.toLocaleString()} 歩`,
    `- 消費カロリー: ${data.calories.toLocaleString()} kcal`,
    `- 移動距離: ${data.distance.toFixed(2)} km`,
    `- アクティブ時間: ${data.active_minutes} 分`,
  ];

  // Heart rate zones
  if (data.heart_rate_zones) {
    lines.push('- 心拍ゾーン:');
    lines.push(`  - 脂肪燃焼: ${data.heart_rate_zones.fat_burn} 分`);
    lines.push(`  - 有酸素: ${data.heart_rate_zones.cardio} 分`);
    lines.push(`  - ピーク: ${data.heart_rate_zones.peak} 分`);
  }

  lines.push('');
  lines.push('## 睡眠');
  lines.push(`- 睡眠時間: ${formatMinutesToHours(data.sleep_duration_minutes)}`);
  lines.push(`- 睡眠効率: ${data.sleep_efficiency !== null ? `${data.sleep_efficiency}%` : 'データなし'}`);

  if (data.sleep_stages) {
    lines.push('- 睡眠ステージ:');
    lines.push(`  - 深い睡眠: ${data.sleep_stages.deep} 分`);
    lines.push(`  - 浅い睡眠: ${data.sleep_stages.light} 分`);
    lines.push(`  - レム睡眠: ${data.sleep_stages.rem} 分`);
    lines.push(`  - 覚醒: ${data.sleep_stages.wake} 分`);
  }

  lines.push('');
  lines.push('## 心拍数');
  lines.push(`- 安静時心拍数: ${data.resting_heart_rate !== null ? `${data.resting_heart_rate} bpm` : 'データなし'}`);

  lines.push('');
  lines.push('## 体重');
  lines.push(`- 体重: ${data.weight !== null ? `${data.weight} kg` : 'データなし'}`);

  lines.push('');
  lines.push('## 心肺機能 (VO2max)');
  lines.push(`- スコア: ${data.vo2max || 'データなし'}`);

  lines.push('');
  lines.push('## 血中酸素 (SpO2)');
  lines.push(`- 平均: ${data.spo2_avg !== null ? `${data.spo2_avg}%` : 'データなし'}`);

  return lines.join('\n');
}

/**
 * Format minutes to hours and minutes
 */
function formatMinutesToHours(minutes: number): string {
  if (minutes === 0) return 'データなし';
  const hours = Math.floor(minutes / 60);
  const mins = minutes % 60;
  return `${hours}時間${mins}分`;
}
