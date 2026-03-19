/**
 * Quick Playwright test to verify Open AF layout
 * Run with: npx playwright test tests/visual/layout-check.spec.js
 */

const { test, expect } = require('@playwright/test');

test('Open AF layout fits on one screen', async ({ page }) => {
    // Navigate to Salesforce login
    await page.goto('https://login.salesforce.com');
    
    // Fill credentials (set these as environment variables)
    await page.fill('input[name="username"]', process.env.SF_USERNAME || 'kudryk@wise-badger-94mfwi.com');
    await page.fill('input[name="pw"]', process.env.SF_PASSWORD || '');
    await page.click('input[name="Login"]');
    
    // Wait for navigation
    await page.waitForURL('**/lightning/**', { timeout: 30000 });
    
    // Navigate to Open AF app
    await page.goto('https://wise-badger-94mfwi-dev-ed.trailblaze.my.salesforce.com/lightning/n/Open_AF_Chat');
    
    // Wait for component to load
    await page.waitForSelector('.page', { timeout: 30000 });
    await page.waitForTimeout(2000);
    
    // Check page height matches viewport (no scrolling)
    const pageHeight = await page.evaluate(() => {
        const page = document.querySelector('.page');
        return page ? page.getBoundingClientRect().height : 0;
    });
    
    const viewportHeight = await page.evaluate(() => window.innerHeight);
    
    console.log(`Page height: ${pageHeight}px, Viewport height: ${viewportHeight}px`);
    
    // Page should fit within viewport (allow 5px tolerance)
    expect(pageHeight).toBeLessThanOrEqual(viewportHeight + 5);
    
    // Check chat-input is visible
    const chatInput = await page.$('.chat-input');
    expect(chatInput).toBeTruthy();
    
    // Check chat-input is within viewport
    const chatInputBox = await chatInput.boundingBox();
    if (chatInputBox) {
        console.log(`Chat input: top=${chatInputBox.top}, bottom=${chatInputBox.bottom}`);
        expect(chatInputBox.bottom).toBeLessThanOrEqual(viewportHeight + 5);
    }
    
    // Take screenshot
    await page.screenshot({ 
        path: 'tests/visual/snapshots/layout-fixed.png',
        fullPage: true 
    });
    
    console.log('Layout check passed - chat input is within viewport');
});
