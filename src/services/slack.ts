/**
 * Slack Posting Service for Fitbit Health Insights
 */

const SLACK_API_URL = 'https://slack.com/api/chat.postMessage';

export type HealthInsights = {
  summary: string;
  highlights: string[];
  improvements: string[];
  actionable_tips: string[];
};

export type Env = {
  SLACK_BOT_TOKEN?: string;
  SLACK_CHANNEL?: string;
};

/**
 * Post a message to Slack
 */
export async function postToSlack(env: Env, text: string): Promise<boolean> {
  const token = env.SLACK_BOT_TOKEN;
  const channel = env.SLACK_CHANNEL || '#limitless-音声-insight';

  if (!token) {
    console.error('SLACK_BOT_TOKEN not configured');
    return false;
  }

  try {
    const response = await fetch(SLACK_API_URL, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: new URLSearchParams({
        token,
        channel,
        username: 'けろよん',
        icon_url: 'https://emoji.slack-edge.com/T030A5CV2/keroyon/c3aa47f65017d188.png',
        text,
      }),
    });

    const result = await response.json() as { ok: boolean; error?: string };
    if (!result.ok) {
      console.error('Slack post failed:', result.error);
      return false;
    }

    return true;
  } catch (error) {
    console.error('Slack post error:', error);
    return false;
  }
}

/**
 * Format health insights for Slack message
 */
export function formatHealthInsightsForSlack(
  insights: HealthInsights,
  date: string
): string {
  const sections: string[] = [];

  // Header
  sections.push(`@kazuph :runner: *Fitbit 健康レポート*\n_${date} のサマリー_`);

  // Summary
  if (insights.summary) {
    sections.push(`\n:memo: *サマリー*\n${insights.summary}`);
  }

  // Highlights
  if (insights.highlights.length > 0) {
    const items = insights.highlights.map(h => `• ${h}`).join('\n');
    sections.push(`\n:sparkles: *良かった点*\n${items}`);
  }

  // Improvements
  if (insights.improvements.length > 0) {
    const items = insights.improvements.map(i => `• ${i}`).join('\n');
    sections.push(`\n:chart_with_upwards_trend: *改善ポイント*\n${items}`);
  }

  // Actionable Tips
  if (insights.actionable_tips.length > 0) {
    const items = insights.actionable_tips.map(t => `• ${t}`).join('\n');
    sections.push(`\n:bulb: *今日のアドバイス*\n${items}`);
  }

  return sections.join('\n');
}

/**
 * Post health insights to Slack
 */
export async function postHealthInsightsToSlack(
  env: Env,
  insights: HealthInsights,
  date: string
): Promise<boolean> {
  const hasContent =
    insights.summary ||
    insights.highlights.length > 0 ||
    insights.improvements.length > 0 ||
    insights.actionable_tips.length > 0;

  if (!hasContent) {
    console.log('No health insights to post');
    return false;
  }

  const message = formatHealthInsightsForSlack(insights, date);
  return postToSlack(env, message);
}

/**
 * Post error notification to Slack
 */
export async function postErrorToSlack(
  env: Env,
  error: Error | string,
  context?: string
): Promise<boolean> {
  const timestamp = new Date().toLocaleString('ja-JP', { timeZone: 'Asia/Tokyo' });
  const errorMessage = error instanceof Error ? error.message : error;
  const stack = error instanceof Error ? error.stack?.split('\n').slice(0, 5).join('\n') : '';

  const text = [
    `:warning: *Fitbit Cron処理エラー*`,
    `_${timestamp}_`,
    context ? `\n*コンテキスト:* ${context}` : '',
    `\n*エラー:* ${errorMessage}`,
    stack ? `\n\`\`\`${stack}\`\`\`` : '',
  ].filter(Boolean).join('\n');

  return postToSlack(env, text);
}
