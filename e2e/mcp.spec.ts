import { test, expect } from '@playwright/test';
import * as dotenv from 'dotenv';

// Load environment variables
dotenv.config();

/**
 * MCP Server Integration Tests
 *
 * These tests verify the MCP API endpoints that AI clients use.
 * All endpoints require Bearer token authentication via MCP_API_KEY.
 *
 * Using native fetch instead of Playwright's request fixture to avoid
 * httpCredentials (Basic Auth) being sent with Bearer token requests.
 */

// Get API key from environment (required - no fallback for security)
const MCP_API_KEY = process.env.MCP_API_KEY;
if (!MCP_API_KEY) {
  throw new Error('MCP_API_KEY environment variable is required for MCP tests');
}

// Base URL from environment with fallback for local development
const BASE_URL = process.env.BASE_URL || 'http://localhost:18787';

test.describe('MCP Authentication', () => {
  test('should reject requests without API key', async () => {
    const response = await fetch(`${BASE_URL}/mcp/health`);
    expect(response.status).toBe(401);
  });

  test('should reject requests with invalid API key', async () => {
    const response = await fetch(`${BASE_URL}/mcp/health`, {
      headers: {
        'Authorization': 'Bearer invalid-api-key',
      },
    });
    expect(response.status).toBe(401);
  });

  test('should accept requests with valid API key', async () => {
    const response = await fetch(`${BASE_URL}/mcp/health`, {
      headers: {
        'Authorization': `Bearer ${MCP_API_KEY}`,
      },
    });
    expect(response.ok).toBe(true);
  });

  test('should accept both Bearer and raw token formats', async () => {
    // Test with Bearer prefix
    const response1 = await fetch(`${BASE_URL}/mcp/health`, {
      headers: {
        'Authorization': `Bearer ${MCP_API_KEY}`,
      },
    });
    expect(response1.ok).toBe(true);
  });
});

test.describe('MCP Tools Endpoint', () => {
  test('should return list of available tools', async () => {
    const response = await fetch(`${BASE_URL}/mcp/tools`, {
      headers: {
        'Authorization': `Bearer ${MCP_API_KEY}`,
      },
    });

    expect(response.ok).toBe(true);
    const data = await response.json();

    // Verify tools array exists
    expect(data.tools).toBeDefined();
    expect(Array.isArray(data.tools)).toBe(true);
    expect(data.tools.length).toBeGreaterThan(0);
  });

  test('should include required tool definitions', async () => {
    const response = await fetch(`${BASE_URL}/mcp/tools`, {
      headers: {
        'Authorization': `Bearer ${MCP_API_KEY}`,
      },
    });

    const data = await response.json();
    const toolNames = data.tools.map((t: { name: string }) => t.name);

    // Verify all expected tools exist
    expect(toolNames).toContain('get_health_summary');
    expect(toolNames).toContain('get_activity_data');
    expect(toolNames).toContain('get_sleep_data');
    expect(toolNames).toContain('get_heartrate_data');
    expect(toolNames).toContain('get_weight_data');
  });

  test('should have correct tool schema format', async () => {
    const response = await fetch(`${BASE_URL}/mcp/tools`, {
      headers: {
        'Authorization': `Bearer ${MCP_API_KEY}`,
      },
    });

    const data = await response.json();

    // Verify each tool has required fields
    for (const tool of data.tools) {
      expect(tool.name).toBeDefined();
      expect(typeof tool.name).toBe('string');
      expect(tool.description).toBeDefined();
      expect(typeof tool.description).toBe('string');
      expect(tool.parameters).toBeDefined();
      expect(tool.parameters.type).toBe('object');
      expect(tool.parameters.properties).toBeDefined();
    }
  });
});

test.describe('MCP Health Endpoint', () => {
  test('should return health summary data', async () => {
    const response = await fetch(`${BASE_URL}/mcp/health`, {
      headers: {
        'Authorization': `Bearer ${MCP_API_KEY}`,
      },
    });

    expect(response.ok).toBe(true);
    const data = await response.json();

    // Verify response structure
    expect(data.success).toBe(true);
    expect(data.data).toBeDefined();
    expect(data.data.summaries).toBeDefined();
    expect(Array.isArray(data.data.summaries)).toBe(true);
    expect(data.data.period).toBeDefined();
    expect(data.data.period.days).toBeDefined();
    expect(data.data.period.end_date).toBeDefined();
  });

  test('should accept days parameter', async () => {
    const response = await fetch(`${BASE_URL}/mcp/health?days=14`, {
      headers: {
        'Authorization': `Bearer ${MCP_API_KEY}`,
      },
    });

    expect(response.ok).toBe(true);
    const data = await response.json();
    expect(data.data.period.days).toBe(14);
  });

  test('should handle default days value', async () => {
    const response = await fetch(`${BASE_URL}/mcp/health`, {
      headers: {
        'Authorization': `Bearer ${MCP_API_KEY}`,
      },
    });

    const data = await response.json();
    expect(data.data.period.days).toBe(7); // Default is 7 days
  });
});

test.describe('MCP Activity Endpoint', () => {
  test('should return activity data', async () => {
    const response = await fetch(`${BASE_URL}/mcp/activity`, {
      headers: {
        'Authorization': `Bearer ${MCP_API_KEY}`,
      },
    });

    expect(response.ok).toBe(true);
    const data = await response.json();

    expect(data.success).toBe(true);
    expect(data.data).toBeDefined();
    expect(data.data.activities).toBeDefined();
    expect(Array.isArray(data.data.activities)).toBe(true);
  });

  test('should return activity data for specified days', async () => {
    const response = await fetch(`${BASE_URL}/mcp/activity?days=30`, {
      headers: {
        'Authorization': `Bearer ${MCP_API_KEY}`,
      },
    });

    expect(response.ok).toBe(true);
    const data = await response.json();
    expect(data.data.period.days).toBe(30);
  });
});

test.describe('MCP Sleep Endpoint', () => {
  test('should return sleep data', async () => {
    const response = await fetch(`${BASE_URL}/mcp/sleep`, {
      headers: {
        'Authorization': `Bearer ${MCP_API_KEY}`,
      },
    });

    expect(response.ok).toBe(true);
    const data = await response.json();

    expect(data.success).toBe(true);
    expect(data.data).toBeDefined();
    expect(data.data.sleep_data).toBeDefined();
    expect(Array.isArray(data.data.sleep_data)).toBe(true);
  });
});

test.describe('MCP Heart Rate Endpoint', () => {
  test('should return heart rate data', async () => {
    const response = await fetch(`${BASE_URL}/mcp/heartrate`, {
      headers: {
        'Authorization': `Bearer ${MCP_API_KEY}`,
      },
    });

    expect(response.ok).toBe(true);
    const data = await response.json();

    expect(data.success).toBe(true);
    expect(data.data).toBeDefined();
    expect(data.data.heart_rate_data).toBeDefined();
    expect(Array.isArray(data.data.heart_rate_data)).toBe(true);
  });
});

test.describe('MCP Weight Endpoint', () => {
  test('should return weight data', async () => {
    const response = await fetch(`${BASE_URL}/mcp/weight`, {
      headers: {
        'Authorization': `Bearer ${MCP_API_KEY}`,
      },
    });

    expect(response.ok).toBe(true);
    const data = await response.json();

    expect(data.success).toBe(true);
    expect(data.data).toBeDefined();
    expect(data.data.weight_data).toBeDefined();
    expect(Array.isArray(data.data.weight_data)).toBe(true);
  });

  test('should use 30 days default for weight', async () => {
    const response = await fetch(`${BASE_URL}/mcp/weight`, {
      headers: {
        'Authorization': `Bearer ${MCP_API_KEY}`,
      },
    });

    const data = await response.json();
    expect(data.data.period.days).toBe(30);
  });
});

test.describe('MCP Error Handling', () => {
  test('should return 404 for unknown endpoints', async () => {
    const response = await fetch(`${BASE_URL}/mcp/unknown`, {
      headers: {
        'Authorization': `Bearer ${MCP_API_KEY}`,
      },
    });

    expect(response.status).toBe(404);
  });

  test('should handle CORS preflight requests', async () => {
    const response = await fetch(`${BASE_URL}/mcp/tools`, {
      method: 'OPTIONS',
      headers: {
        'Origin': 'http://localhost:3000',
        'Access-Control-Request-Method': 'GET',
      },
    });

    // Should allow CORS
    const allowOrigin = response.headers.get('access-control-allow-origin');
    expect(allowOrigin).toBeDefined();
  });
});

test.describe('MCP JSON Response Format', () => {
  test('should return valid JSON with correct content type', async () => {
    const response = await fetch(`${BASE_URL}/mcp/health`, {
      headers: {
        'Authorization': `Bearer ${MCP_API_KEY}`,
      },
    });

    const contentType = response.headers.get('content-type');
    expect(contentType).toContain('application/json');

    // Verify JSON is parseable
    const data = await response.json();
    expect(typeof data).toBe('object');
  });

  test('should include timestamps in date format', async () => {
    const response = await fetch(`${BASE_URL}/mcp/health`, {
      headers: {
        'Authorization': `Bearer ${MCP_API_KEY}`,
      },
    });

    const data = await response.json();
    // end_date should be in YYYY-MM-DD format
    expect(data.data.period.end_date).toMatch(/^\d{4}-\d{2}-\d{2}$/);
  });
});
