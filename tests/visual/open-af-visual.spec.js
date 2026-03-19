/**
 * Playwright visual test for Open AF LWC
 * 
 * This test navigates to the Salesforce Open AF app and takes a screenshot
 * to verify the UI renders correctly.
 * 
 * Prerequisites:
 * 1. npm install -D playwright @playwright/test
 * 2. npx playwright install chromium
 * 3. Set environment variables:
 *    - SF_USERNAME: Salesforce username
 *    - SF_PASSWORD: Salesforce password
 *    - SF_LOGIN_URL: Salesforce login URL (default: https://login.salesforce.com)
 *    - SF_APP_URL: Direct URL to Open AF app (optional)
 * 
 * Usage:
 *   npx playwright test tests/visual/open-af-visual.spec.js
 */

const { test, expect } = require('@playwright/test');

// Helper to get Salesforce credentials
function getCredentials() {
    const username = process.env.SF_USERNAME;
    const password = process.env.SF_PASSWORD;
    const loginUrl = process.env.SF_LOGIN_URL || 'https://login.salesforce.com';
    
    if (!username || !password) {
        throw new Error('SF_USERNAME and SF_PASSWORD environment variables are required');
    }
    
    return { username, password, loginUrl };
}

// Helper to get app URL
function getAppUrl() {
    return process.env.SF_APP_URL || 'https://wise-badger-94mfwi-dev-ed.trailblaze.my.salesforce.com/lightning/n/Open_AF_Chat';
}

test.describe('Open AF Visual Tests', () => {
    test('renders the chat interface correctly', async ({ page }) => {
        const { username, password, loginUrl } = getCredentials();
        const appUrl = getAppUrl();
        
        // Navigate to Salesforce login
        await page.goto(loginUrl);
        
        // Fill in credentials
        await page.fill('input[name="username"]', username);
        await page.fill('input[name="pw"]', password);
        await page.click('input[name="Login"]');
        
        // Wait for navigation to complete
        await page.waitForURL('**/lightning/**', { timeout: 30000 });
        
        // Navigate to Open AF app
        await page.goto(appUrl);
        
        // Wait for the LWC component to load
        await page.waitForSelector('.page', { timeout: 30000 });
        
        // Wait a bit more for any dynamic content
        await page.waitForTimeout(2000);
        
        // Take a screenshot
        const screenshot = await page.screenshot({ fullPage: true });
        
        // Save screenshot with timestamp
        const timestamp = new Date().toISOString().replace(/[:.]/g, '-');
        const screenshotPath = `tests/visual/snapshots/open-af-${timestamp}.png`;
        
        // Ensure directory exists
        const fs = require('fs');
        const path = require('path');
        const dir = path.dirname(screenshotPath);
        if (!fs.existsSync(dir)) {
            fs.mkdirSync(dir, { recursive: true });
        }
        
        fs.writeFileSync(screenshotPath, screenshot);
        
        console.log(`Screenshot saved to: ${screenshotPath}`);
        
        // Basic assertion: page should not be empty
        const pageContent = await page.content();
        expect(pageContent).toContain('openAfChat');
    });
    
    test('sidebar and chat layout are visible', async ({ page }) => {
        const { username, password, loginUrl } = getCredentials();
        const appUrl = getAppUrl();
        
        // Login and navigate
        await page.goto(loginUrl);
        await page.fill('input[name="username"]', username);
        await page.fill('input[name="pw"]', password);
        await page.click('input[name="Login"]');
        await page.waitForURL('**/lightning/**', { timeout: 30000 });
        await page.goto(appUrl);
        
        // Wait for components
        await page.waitForSelector('.page', { timeout: 30000 });
        await page.waitForTimeout(2000);
        
        // Check sidebar exists
        const sidebar = await page.$('.sidebar');
        expect(sidebar).toBeTruthy();
        
        // Check chat area exists
        const chatArea = await page.$('.chat-area');
        expect(chatArea).toBeTruthy();
        
        // Check layout structure
        const layout = await page.$('.layout');
        expect(layout).toBeTruthy();
        
        // Take screenshot for visual verification
        await page.screenshot({ fullPage: true, path: 'tests/visual/snapshots/layout-check.png' });
    });
    
    test('input area is visible and functional', async ({ page }) => {
        const { username, password, loginUrl } = getCredentials();
        const appUrl = getAppUrl();
        
        // Login and navigate
        await page.goto(loginUrl);
        await page.fill('input[name="username"]', username);
        await page.fill('input[name="pw"]', password);
        await page.click('input[name="Login"]');
        await page.waitForURL('**/lightning/**', { timeout: 30000 });
        await page.goto(appUrl);
        
        // Wait for components
        await page.waitForSelector('.page', { timeout: 30000 });
        await page.waitForTimeout(2000);
        
        // Check input area exists
        const inputArea = await page.$('.chat-input');
        expect(inputArea).toBeTruthy();
        
        // Check textarea exists
        const textarea = await page.$('lightning-textarea');
        expect(textarea).toBeTruthy();
        
        // Check send button exists
        const sendButton = await page.$('.send-button');
        expect(sendButton).toBeTruthy();
        
        // Try typing in the textarea
        await textarea.click();
        await page.keyboard.type('Test message');
        
        // Take screenshot
        await page.screenshot({ fullPage: true, path: 'tests/visual/snapshots/input-check.png' });
    });
});

// Helper test for debugging
test.describe('Visual Debug', () => {
    test('take screenshot of current state', async ({ page }) => {
        // This test just takes a screenshot for debugging purposes
        // It doesn't require login
        
        const appUrl = getAppUrl();
        
        try {
            await page.goto(appUrl, { waitUntil: 'networkidle' });
            await page.waitForTimeout(3000);
            
            // Take screenshot
            await page.screenshot({ 
                fullPage: true, 
                path: 'tests/visual/snapshots/debug-current.png' 
            });
            
            console.log('Debug screenshot saved to: tests/visual/snapshots/debug-current.png');
            
            // Log page title for debugging
            const title = await page.title();
            console.log(`Page title: ${title}`);
            
        } catch (error) {
            console.log(`Navigation failed: ${error.message}`);
            await page.screenshot({ 
                fullPage: true, 
                path: 'tests/visual/snapshots/debug-error.png' 
            });
        }
    });
});
